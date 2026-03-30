package com.example.helloworld;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.fragment.app.Fragment;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import java.util.ArrayList;
import java.util.List;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;

public class ChatFragment extends Fragment implements TextToSpeech.OnInitListener {
    
    private RecyclerView messagesRecyclerView;
    private EditText messageInput;
    private Button sendButton;
    private Button clearButton;
    
    private MessageAdapter messageAdapter;
    private ApiService apiService;
    private StorageService storageService;
    private TextToSpeech tts;
    private String currentSpokenText;
    private int lastSpokenIndex = 0;
    
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // Initialize TextToSpeech engine
        tts = new TextToSpeech(getContext(), this);
        tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
            @Override
            public void onStart(String utteranceId) {
                // Not needed for this implementation
            }

            @Override
            public void onDone(String utteranceId) {
                // Reset progress when speech is finished
                lastSpokenIndex = 0;
            }

            @Override
            public void onError(String utteranceId) {
                // Reset progress on error
                lastSpokenIndex = 0;
            }

            @Override
            public void onRangeStart(String utteranceId, int start, int end, int frame) {
                // Update the last spoken index
                lastSpokenIndex = end;
            }
        });

        // From ServiceManager get service instance
        ServiceManager serviceManager = ServiceManager.getInstance();
        storageService = serviceManager.getStorageService();
        apiService = serviceManager.getApiService();
        
        if (storageService == null) {
            storageService = new StorageService(getContext());
            serviceManager.setStorageService(storageService);
        }
        
        if (apiService == null) {
            apiService = new ApiService(getContext());
            serviceManager.setApiService(apiService);
        }
        
        List<Message> messageList = storageService.loadMessages();
        messageAdapter = new MessageAdapter(getContext(), messageList, this);
        serviceManager.setMessageAdapter(messageAdapter);
    }
    
    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        View view = inflater.inflate(R.layout.fragment_chat, container, false);
        
        messagesRecyclerView = view.findViewById(R.id.messagesRecyclerView);
        messageInput = view.findViewById(R.id.messageInput);
        sendButton = view.findViewById(R.id.sendButton);
        clearButton = view.findViewById(R.id.clearButton);

        messagesRecyclerView.setLayoutManager(new LinearLayoutManager(getContext()));
        messagesRecyclerView.setAdapter(messageAdapter);

        sendButton.setOnClickListener(v -> sendMessage());
        clearButton.setOnClickListener(v -> clearMessages());

        return view;
    }
    
    @Override
    public void onResume() {
        super.onResume();
        // Ensure you get the latest service instances every time you return
        ServiceManager serviceManager = ServiceManager.getInstance();
        apiService = serviceManager.getApiService();
        storageService = serviceManager.getStorageService();
    }
    
    @Override
    public void onPause() {
        super.onPause();
    }
    
    private void sendMessage() {
        String messageText = messageInput.getText().toString().trim();
        if (!messageText.isEmpty()) {
            String timestamp = new SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(new Date());
            Message message = new Message("用户", messageText, Message.TYPE_SENT, timestamp);
            messageAdapter.addMessage(message);
            messageInput.setText("");

            getAiCompletion(messageText);
        }
    }

    private void clearMessages() {
        if (storageService != null) {
            storageService.clearMessages();
        }
        if (messageAdapter != null) {
            messageAdapter.clearMessages();
        }
    }

    private void getAiCompletion(String prompt) {
        if (apiService != null) {
            String selectedModel = storageService.loadSetting(StorageService.KEY_SELECTED_AI_MODEL, ApiService.MODEL_ZHIPU);
            apiService.getAiCompletion(prompt, selectedModel, new ApiService.ApiResponseListener<String>() {
                @Override
                public void onSuccess(String response) {
                    if (messageAdapter != null) {
                        String timestamp = new SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(new Date());
                        messageAdapter.addMessage(new Message("AI Assistant", response, Message.TYPE_RECEIVED, timestamp));
                    }
                }
                
                @Override
                public void onError(String error) {
                    if (messageAdapter != null) {
                        String timestamp = new SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(new Date());
                        messageAdapter.addMessage(new Message("System", "Error: " + error, Message.TYPE_SYSTEM, timestamp));
                    }
                }
            });
        }
    }
    
    private void loadMessages() {
        if (storageService != null && messageAdapter != null) {
            List<Message> loadedMessages = storageService.loadMessages();
            if (loadedMessages != null) {
                messageAdapter.setMessages(loadedMessages);
            }
        }
    }
    
    private void saveMessages() {
        if (storageService != null && messageAdapter != null) {
            storageService.saveMessages(messageAdapter.getMessages());
        }
    }
    
    private String getCurrentTimestamp() {
        return new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
                .format(new java.util.Date());
    }
    
    public void setMessageAdapter(MessageAdapter adapter) {
        this.messageAdapter = adapter;
    }
    
    @Override
    public void onDestroy() {
        // Shutdown TTS engine
        if (tts != null) {
            tts.stop();
            tts.shutdown();
        }
        super.onDestroy();
        saveMessages();
    }

    @Override
    public void onInit(int status) {
        if (status == TextToSpeech.SUCCESS) {
            int result = tts.setLanguage(Locale.CHINA);
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                // Log error or inform user
            }
        } else {
            // Log error
        }
    }

    public void speak(String text) {
        if (tts != null && !text.isEmpty()) {
            Bundle params = new Bundle();
            params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "UniqueID");

            if (text.equals(currentSpokenText)) {
                // If the same text is clicked again, it's a pause/resume action
                if (tts.isSpeaking()) {
                    tts.stop(); // This effectively pauses the speech
                } else {
                    // Resume from where it left off
                    if (lastSpokenIndex < text.length()) {
                        String remainingText = text.substring(lastSpokenIndex);
                        tts.speak(remainingText, TextToSpeech.QUEUE_FLUSH, params, "UniqueID");
                    }
                }
            } else {
                // New text is clicked, start from the beginning
                currentSpokenText = text;
                lastSpokenIndex = 0;
                tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, "UniqueID");
            }
        }
    }
}