#include "mad_voice_capture.h"

#include <audioclient.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <windows.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <future>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

constexpr int kOutputSampleRate = 16000;
constexpr size_t kMaxQueuedBytes = kOutputSampleRate * 2 * 3;

std::string HResultError(const char* step, HRESULT hr) {
  char code[32];
  sprintf_s(code, "0x%08X", static_cast<unsigned int>(hr));
  return std::string(step) + " failed hr=" + code;
}

class MadVoiceCapture {
 public:
  MadVoiceCapture() = default;
  ~MadVoiceCapture() { Stop(); }

  bool Start(std::string* error) {
    Stop();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      buffer_.clear();
    }
    running_.store(true);
    std::promise<std::string> init_result;
    auto init_future = init_result.get_future();
    worker_ = std::thread([this, init_result = std::move(init_result)]() mutable {
      CaptureLoop(std::move(init_result));
    });

    if (init_future.wait_for(std::chrono::seconds(3)) !=
        std::future_status::ready) {
      if (error) {
        *error = "WASAPI capture init timed out";
      }
      Stop();
      return false;
    }

    const auto init_error = init_future.get();
    if (!init_error.empty()) {
      if (error) {
        *error = init_error;
      }
      Stop();
      return false;
    }

    return true;
  }

  std::vector<uint8_t> Read() {
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<uint8_t> out;
    out.swap(buffer_);
    return out;
  }

  void Stop() {
    running_.store(false);
    if (worker_.joinable()) {
      worker_.join();
    }
  }

 private:
  void PushBytes(const std::vector<uint8_t>& bytes) {
    if (bytes.empty()) return;
    std::lock_guard<std::mutex> lock(mutex_);
    buffer_.insert(buffer_.end(), bytes.begin(), bytes.end());
    if (buffer_.size() > kMaxQueuedBytes) {
      const auto drop = buffer_.size() - kMaxQueuedBytes;
      buffer_.erase(buffer_.begin(), buffer_.begin() + drop);
    }
  }

  static bool IsFloatFormat(const WAVEFORMATEX* format) {
    if (format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
    if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
      const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
      return IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
    }
    return false;
  }

  static bool IsPcmFormat(const WAVEFORMATEX* format) {
    if (format->wFormatTag == WAVE_FORMAT_PCM) return true;
    if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
      const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
      return IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_PCM);
    }
    return false;
  }

  double ReadMonoSample(const BYTE* data, UINT32 frame, const WAVEFORMATEX* format) {
    const auto channels = std::max<WORD>(1, format->nChannels);
    const auto block_align = std::max<WORD>(1, format->nBlockAlign);
    const BYTE* frame_ptr = data + frame * block_align;
    double sum = 0.0;

    if (IsFloatFormat(format) && format->wBitsPerSample == 32) {
      const auto* samples = reinterpret_cast<const float*>(frame_ptr);
      for (WORD c = 0; c < channels; ++c) {
        sum += samples[c];
      }
    } else if (IsPcmFormat(format) && format->wBitsPerSample == 16) {
      const auto* samples = reinterpret_cast<const int16_t*>(frame_ptr);
      for (WORD c = 0; c < channels; ++c) {
        sum += static_cast<double>(samples[c]) / 32768.0;
      }
    } else if (IsPcmFormat(format) && format->wBitsPerSample == 24) {
      for (WORD c = 0; c < channels; ++c) {
        const BYTE* p = frame_ptr + c * 3;
        int32_t v = (static_cast<int32_t>(p[0]) |
                     (static_cast<int32_t>(p[1]) << 8) |
                     (static_cast<int32_t>(p[2]) << 16));
        if (v & 0x00800000) v |= static_cast<int32_t>(0xFF000000);
        sum += static_cast<double>(v) / 8388608.0;
      }
    } else if (IsPcmFormat(format) && format->wBitsPerSample == 32) {
      const auto* samples = reinterpret_cast<const int32_t*>(frame_ptr);
      for (WORD c = 0; c < channels; ++c) {
        sum += static_cast<double>(samples[c]) / 2147483648.0;
      }
    }

    return std::clamp(sum / channels, -1.0, 1.0);
  }

  void ConvertAndPush(const BYTE* data,
                      UINT32 frames,
                      const WAVEFORMATEX* format,
                      bool silent) {
    if (frames == 0 || format->nSamplesPerSec == 0) return;
    const double ratio =
        static_cast<double>(format->nSamplesPerSec) / kOutputSampleRate;
    const int64_t start_frame = input_frames_seen_;
    const int64_t end_frame = start_frame + frames;
    std::vector<uint8_t> bytes;

    while (next_output_source_frame_ < static_cast<double>(end_frame)) {
      const int64_t src_abs =
          static_cast<int64_t>(next_output_source_frame_ + 0.5);
      if (src_abs >= start_frame && src_abs < end_frame) {
        const UINT32 local = static_cast<UINT32>(src_abs - start_frame);
        double sample = silent ? 0.0 : ReadMonoSample(data, local, format);
        int32_t pcm = static_cast<int32_t>(sample * 32767.0);
        pcm = std::clamp(pcm, -32768, 32767);
        const int16_t s = static_cast<int16_t>(pcm);
        bytes.push_back(static_cast<uint8_t>(s & 0xFF));
        bytes.push_back(static_cast<uint8_t>((s >> 8) & 0xFF));
      }
      next_output_source_frame_ += ratio;
    }

    input_frames_seen_ = end_frame;
    PushBytes(bytes);
  }

  void CaptureLoop(std::promise<std::string> init_result) {
    bool init_reported = false;
    auto report_init = [&](const std::string& message) {
      if (!init_reported) {
        init_result.set_value(message);
        init_reported = true;
      }
    };

    HRESULT co_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool should_uninitialize = SUCCEEDED(co_hr);
    if (FAILED(co_hr) && co_hr != RPC_E_CHANGED_MODE) {
      report_init(HResultError("CoInitializeEx", co_hr));
      return;
    }

    input_frames_seen_ = 0;
    next_output_source_frame_ = 0.0;

    ComPtr<IMMDeviceEnumerator> enumerator;
    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
    const char* step = "CoCreateInstance(MMDeviceEnumerator)";
    ComPtr<IMMDevice> device;
    if (SUCCEEDED(hr)) {
      step = "GetDefaultAudioEndpoint";
      hr = enumerator->GetDefaultAudioEndpoint(eCapture, eCommunications, &device);
      if (FAILED(hr)) {
        hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
      }
    }

    ComPtr<IAudioClient> audio_client;
    if (SUCCEEDED(hr)) {
      step = "IMMDevice::Activate(IAudioClient)";
      hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                            reinterpret_cast<void**>(audio_client.GetAddressOf()));
    }

    WAVEFORMATEX* mix_format = nullptr;
    if (SUCCEEDED(hr)) {
      step = "IAudioClient::GetMixFormat";
      hr = audio_client->GetMixFormat(&mix_format);
    }

    if (SUCCEEDED(hr)) {
      step = "IAudioClient::Initialize";
      hr = audio_client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 1000000, 0,
                                    mix_format, nullptr);
    }

    ComPtr<IAudioCaptureClient> capture_client;
    if (SUCCEEDED(hr)) {
      step = "IAudioClient::GetService(IAudioCaptureClient)";
      hr = audio_client->GetService(IID_PPV_ARGS(&capture_client));
    }

    if (SUCCEEDED(hr)) {
      step = "IAudioClient::Start";
      hr = audio_client->Start();
    }

    if (FAILED(hr)) {
      report_init(HResultError(step, hr));
      if (mix_format) {
        CoTaskMemFree(mix_format);
      }
      if (should_uninitialize) {
        CoUninitialize();
      }
      return;
    }

    report_init("");

    while (SUCCEEDED(hr) && running_.load()) {
      UINT32 packet_frames = 0;
      hr = capture_client->GetNextPacketSize(&packet_frames);
      if (FAILED(hr)) break;
      if (packet_frames == 0) {
        Sleep(8);
        continue;
      }

      BYTE* data = nullptr;
      UINT32 frames = 0;
      DWORD flags = 0;
      hr = capture_client->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
      if (FAILED(hr)) break;

      ConvertAndPush(data, frames, mix_format,
                     (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0);
      capture_client->ReleaseBuffer(frames);
    }

    if (audio_client) {
      audio_client->Stop();
    }
    if (mix_format) {
      CoTaskMemFree(mix_format);
    }
    if (should_uninitialize) {
      CoUninitialize();
    }
  }

  std::atomic<bool> running_{false};
  std::thread worker_;
  std::mutex mutex_;
  std::vector<uint8_t> buffer_;
  int64_t input_frames_seen_ = 0;
  double next_output_source_frame_ = 0.0;
};

std::unique_ptr<MadVoiceCapture> g_capture;

}  // namespace

void RegisterMadVoiceCapture(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "mad_voice_pcm",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (!g_capture) {
          g_capture = std::make_unique<MadVoiceCapture>();
        }

        const auto& method = call.method_name();
        if (method == "start") {
          std::string error;
          if (g_capture->Start(&error)) {
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Error("voice_capture_start_failed", error);
          }
          return;
        }

        if (method == "read") {
          auto bytes = g_capture->Read();
          result->Success(flutter::EncodableValue(bytes));
          return;
        }

        if (method == "stop") {
          g_capture->Stop();
          result->Success(flutter::EncodableValue(true));
          return;
        }

        result->NotImplemented();
      });

  // Deliberately leak the channel for the lifetime of the process, matching
  // the runner lifetime and avoiding static destruction ordering issues.
  channel.release();
}
