package com.example.helloworld;

import android.Manifest;
import android.content.pm.PackageManager;
import android.media.MediaRecorder;
import android.os.Bundle;
import android.os.Environment;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.fragment.app.Fragment;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.io.File;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class VoiceFragment extends Fragment {
    
    private static final String TAG = "VoiceFragment";
    private static final int REQUEST_RECORD_AUDIO_PERMISSION = 200;
    
    private Button recordButton;
    private TextView statusText; // This can be removed if not in the layout
    private LinearLayout confirmationLayout;
    private EditText recognizedTextView;
    private Button sendToAiButton;
    private Button retryButton;
    private RecyclerView messagesRecyclerView;

    private MediaRecorder mediaRecorder;
    private String audioFilePath;
    private boolean isRecording = false;
    private long recordingStartTime;

    private MessageAdapter messageAdapter;
    private ApiService apiService;
    private StorageService storageService;
    
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // From ServiceManager get service instance
        ServiceManager serviceManager = ServiceManager.getInstance();
        apiService = serviceManager.getApiService();
        storageService = serviceManager.getStorageService();
        messageAdapter = serviceManager.getMessageAdapter();
        
        // If service is null, create a new instance
        if (apiService == null) {
            apiService = new ApiService(requireContext());
            serviceManager.setApiService(apiService);
        }
        
        if (storageService == null) {
            storageService = new StorageService(requireContext());
            serviceManager.setStorageService(storageService);
        }
    }
    
    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        View view = inflater.inflate(R.layout.fragment_voice, container, false);
        
        initViews(view);
        setupListeners();
        
        return view;
    }

    @Override
    public void onResume() {
        super.onResume();
        ServiceManager serviceManager = ServiceManager.getInstance();
        messageAdapter = serviceManager.getMessageAdapter();
        apiService = serviceManager.getApiService();
        storageService = serviceManager.getStorageService();
        messagesRecyclerView.setAdapter(messageAdapter);
    }
    
    private void initViews(View view) {
        messagesRecyclerView = view.findViewById(R.id.messagesRecyclerView);
        messagesRecyclerView.setLayoutManager(new LinearLayoutManager(getContext()));
        messagesRecyclerView.setAdapter(messageAdapter);

        recordButton = view.findViewById(R.id.recordButton);
        statusText = view.findViewById(R.id.statusText);
        confirmationLayout = view.findViewById(R.id.confirmationLayout);
        recognizedTextView = view.findViewById(R.id.recognizedTextView);
        sendToAiButton = view.findViewById(R.id.sendToAiButton);
        retryButton = view.findViewById(R.id.retryButton);

        updateStatus("按住按钮开始录音");
    }
    
    private void setupListeners() {
        recordButton.setOnTouchListener((v, event) -> {
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    startRecording();
                    return true;
                case MotionEvent.ACTION_UP:
                    stopRecording();
                    return true;
            }
            return false;
        });

        sendToAiButton.setOnClickListener(v -> {
            String transcribedText = recognizedTextView.getText().toString();
            if (!transcribedText.isEmpty()) {
                updateStatus("正在获取AI回复...");
                String timestamp = getCurrentTimestamp();
                messageAdapter.addMessage(new Message("用户", transcribedText, Message.TYPE_SENT, timestamp));
                getAiResponse(transcribedText);
                resetToRecordingState();
            }
        });

        retryButton.setOnClickListener(v -> resetToRecordingState());
    }
    
    private void startRecording() {
        if (checkPermissions()) {
            try {
                File audioFile = storageService.createAudioFile();
                audioFilePath = audioFile.getAbsolutePath();

                mediaRecorder = new MediaRecorder();
                mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC);
                mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP);
                mediaRecorder.setOutputFile(audioFilePath);
                mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AMR_NB);

                mediaRecorder.prepare();
                mediaRecorder.start();

                isRecording = true;
                recordingStartTime = System.currentTimeMillis();
                recordButton.setText("松开结束");
                updateStatus("正在录音...");
                messageAdapter.addMessage(new Message("系统", "开始录音...", Message.TYPE_SYSTEM, getCurrentTimestamp()));

            } catch (IOException e) {
                Log.e(TAG, "录音准备失败", e);
                updateStatus("录音准备失败");
            }
        }
    }
    
    private void stopRecording() {
        if (mediaRecorder != null && isRecording) {
            long duration = System.currentTimeMillis() - recordingStartTime;
            if (duration < 1000) { // If recording is less than 1 second
                mediaRecorder.release();
                mediaRecorder = null;
                isRecording = false;
                recordButton.setText("按住说话");
                updateStatus("录音时间太短");
                messageAdapter.addMessage(new Message("系统", "录音时间太短", Message.TYPE_SYSTEM, getCurrentTimestamp()));
                return;
            }

            try {
                mediaRecorder.stop();
            } catch (RuntimeException stopException) {
                Log.e(TAG, "停止录音失败", stopException);
            } finally {
                mediaRecorder.release();
                mediaRecorder = null;
                isRecording = false;
                recordButton.setText("按住说话");
                updateStatus("录音完成，正在识别...");
                messageAdapter.addMessage(new Message("系统", "录音完成", Message.TYPE_SYSTEM, getCurrentTimestamp()));

                // Call recognition service
                if (apiService != null && audioFilePath != null) {
                    apiService.recognizeAudio(new File(audioFilePath), new ApiService.ApiResponseListener<String>() {
                        @Override
                        public void onSuccess(String response) {
                            requireActivity().runOnUiThread(() -> {
                                updateStatus("识别成功");
                                recognizedTextView.setText(response);
                                showConfirmationState();
                            });
                        }

                        @Override
                        public void onError(String error) {
                            requireActivity().runOnUiThread(() -> {
                                updateStatus("识别失败: " + error);
                                messageAdapter.addMessage(new Message("系统", "语音识别失败: " + error, Message.TYPE_SYSTEM, getCurrentTimestamp()));
                                resetToRecordingState();
                            });
                        }
                    });
                }
            }
        }
    }

    private void showConfirmationState() {
        recordButton.setVisibility(View.GONE);
        statusText.setVisibility(View.GONE);
        confirmationLayout.setVisibility(View.VISIBLE);
    }

    private void resetToRecordingState() {
        confirmationLayout.setVisibility(View.GONE);
        recordButton.setVisibility(View.VISIBLE);
        statusText.setVisibility(View.VISIBLE);
        recordButton.setText("按住说话");
        updateStatus("按住按钮开始录音");
    }
    
    private void getAiResponse(String userMessage) {
        if (apiService != null) {
            String selectedModel = storageService.loadSetting(StorageService.KEY_SELECTED_AI_MODEL, ApiService.MODEL_ZHIPU);
            apiService.getAiCompletion(userMessage, selectedModel, new ApiService.ApiResponseListener<String>() {
                @Override
                public void onSuccess(String response) {
                    requireActivity().runOnUiThread(() -> {
                        if (messageAdapter != null) {
                            String timestamp = getCurrentTimestamp();
                            messageAdapter.addMessage(new Message("AI", response, Message.TYPE_RECEIVED, timestamp));
                        }
                        updateStatus("按住按钮开始录音");
                    });
                }
                
                @Override
                public void onError(String error) {
                    requireActivity().runOnUiThread(() -> {
                        if (messageAdapter != null) {
                            String timestamp = getCurrentTimestamp();
                            messageAdapter.addMessage(new Message("AI", "回复失败: " + error, Message.TYPE_SYSTEM, timestamp));
                        }
                        updateStatus("AI回复失败");
                    });
                }
            });
        }
    }
    
    private void updateStatus(String status) {
        if (statusText != null) {
            statusText.setText("状态: " + status);
        }
        Log.d(TAG, "Status: " + status);
    }
    
    private String getCurrentTimestamp() {
        SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss", Locale.getDefault());
        return sdf.format(new Date());
    }

    private boolean checkPermissions() {
        if (ContextCompat.checkSelfPermission(requireContext(), Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(requireActivity(), new String[]{Manifest.permission.RECORD_AUDIO}, REQUEST_RECORD_AUDIO_PERMISSION);
            return false;
        }
        return true;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_RECORD_AUDIO_PERMISSION) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                updateStatus("权限已授予，请重试");
            } else {
                updateStatus("需要麦克风权限");
            }
        }
    }
    
    @Override
    public void onDestroy() {
        super.onDestroy();
        
        // 释放录音资源
        if (mediaRecorder != null) {
            mediaRecorder.release();
            mediaRecorder = null;
        }
    }
    
    public void setMessageAdapter(MessageAdapter adapter) {
        this.messageAdapter = adapter;
        if (messagesRecyclerView != null) {
            messagesRecyclerView.setAdapter(adapter);
        }
    }
}