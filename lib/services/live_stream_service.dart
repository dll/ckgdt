import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum LiveStreamStatus { idle, initializing, ready, recording, error }

class LiveStreamState {
  final LiveStreamStatus status;
  final bool isCameraOn;
  final bool isMicOn;
  final Duration recordDuration;
  final String? error;
  final int cameraCount;

  bool get isRecording => status == LiveStreamStatus.recording;

  const LiveStreamState({
    this.status = LiveStreamStatus.idle,
    this.isCameraOn = false,
    this.isMicOn = false,
    this.recordDuration = Duration.zero,
    this.error,
    this.cameraCount = 0,
  });

  LiveStreamState copyWith({
    LiveStreamStatus? status,
    bool? isCameraOn,
    bool? isMicOn,
    Duration? recordDuration,
    String? error,
    int? cameraCount,
  }) =>
      LiveStreamState(
        status: status ?? this.status,
        isCameraOn: isCameraOn ?? this.isCameraOn,
        isMicOn: isMicOn ?? this.isMicOn,
        recordDuration: recordDuration ?? this.recordDuration,
        error: error ?? this.error,
        cameraCount: cameraCount ?? this.cameraCount,
      );
}

class LiveStreamService {
  LiveStreamService._();
  static final LiveStreamService _instance = LiveStreamService._();
  factory LiveStreamService() => _instance;

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  bool _isInitialized = false;

  final _stateController = StreamController<LiveStreamState>.broadcast();
  Stream<LiveStreamState> get state => _stateController.stream;
  LiveStreamState _currentState = const LiveStreamState();
  LiveStreamState get currentState => _currentState;

  Timer? _recordTimer;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _lastRecordPath;

  VoidCallback? _cameraListener;

  Future<void> initializeCamera() async {
    if (_isInitialized) return;
    _emit(LiveStreamStatus.initializing);

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _emit(LiveStreamStatus.error,
            error: '未检测到摄像头，请在设备连接后重试');
        return;
      }

      await _initCameraController(0);
      _isInitialized = true;
      _emit(LiveStreamStatus.ready,
          isCameraOn: true, cameraCount: _cameras.length);
    } catch (e) {
      _emit(LiveStreamStatus.error,
          error: '摄像头初始化失败: $e');
    }
  }

  Future<void> _initCameraController(int index) async {
    _cameraListener?.call();
    _cameraListener = null;
    await _cameraController?.dispose();

    _currentCameraIndex = index.clamp(0, _cameras.length - 1);
    final cam = _cameras[_currentCameraIndex];

    _cameraController = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();

    _cameraListener = () {
      if (_cameraController!.value.hasError) {
        _emit(LiveStreamStatus.error,
            error: _cameraController!.value.errorDescription);
      }
    };
    _cameraController!.addListener(_cameraListener!);
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    final next = (_currentCameraIndex + 1) % _cameras.length;
    try {
      await _initCameraController(next);
      _emit(LiveStreamStatus.ready,
          isCameraOn: true, cameraCount: _cameras.length);
    } catch (e) {
      // 切换失败，保留当前
    }
  }

  Future<void> toggleCamera() async {
    if (_currentState.isCameraOn) {
      _cameraListener?.call();
      _cameraListener = null;
      await _cameraController?.dispose();
      _cameraController = null;
      _isInitialized = false;
      _emit(LiveStreamStatus.ready,
          isCameraOn: false, cameraCount: _cameras.length);
    } else {
      await initializeCamera();
    }
  }

  Future<void> toggleMic() async {
    _emit(_currentState.status,
        isMicOn: !_currentState.isMicOn);
  }

  Future<void> startRecording() async {
    if (_currentState.isRecording) return;

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _lastRecordPath = '${dir.path}/live_record_$ts.mp4';

    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!.startVideoRecording();
      }
      if (_currentState.isMicOn) {
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: '${dir.path}/live_audio_$ts.m4a',
        );
      }

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _emit(LiveStreamStatus.recording,
            recordDuration: _currentState.recordDuration +
                const Duration(seconds: 1));
      });

      _emit(LiveStreamStatus.recording);
    } catch (e) {
      _emit(LiveStreamStatus.error, error: '录制启动失败: $e');
    }
  }

  Future<String?> stopRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;

    try {
      if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
        await _cameraController!.stopVideoRecording();
      }
      if (_currentState.isMicOn) {
        await _audioRecorder.stop();
      }
    } catch (_) {}

    _emit(LiveStreamStatus.ready,
        isCameraOn: _currentState.isCameraOn,
        isMicOn: _currentState.isMicOn,
        cameraCount: _currentState.cameraCount);

    return _lastRecordPath;
  }

  Future<String?> takeSnapshot() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }
    try {
      final xFile = await _cameraController!.takePicture();
      return xFile.path;
    } catch (_) {
      return null;
    }
  }

  void _emit(LiveStreamStatus status,
      {bool? isCameraOn, bool? isMicOn, Duration? recordDuration,
       String? error, int? cameraCount}) {
    _currentState = _currentState.copyWith(
      status: status,
      isCameraOn: isCameraOn,
      isMicOn: isMicOn,
      recordDuration: recordDuration,
      error: error,
      cameraCount: cameraCount,
    );
    _stateController.add(_currentState);
  }

  CameraController? get cameraController => _cameraController;
  List<CameraDescription> get cameras => _cameras;
  int get currentCameraIndex => _currentCameraIndex;

  Future<void> dispose() async {
    _recordTimer?.cancel();
    if (_cameraListener != null) {
      _cameraController?.removeListener(_cameraListener!);
    }
    await _cameraController?.dispose();
    await _audioRecorder.dispose();
    await _stateController.close();
  }
}
