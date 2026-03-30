package com.example.helloworld;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class AIService {
    private static final String TAG = "AIService";
    private static final String API_BASE_URL = "http://10.0.2.2:8080/api";
    private static final String CHAT_API_URL = API_BASE_URL + "/chat";
    private static final String RECOGNIZE_API_URL = API_BASE_URL + "/recognize";
    private static final String DIAGRAM_API_URL = API_BASE_URL + "/diagram";

    private final OkHttpClient client = new OkHttpClient();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static final MediaType JSON = MediaType.parse("application/json; charset=utf-8");

    public interface AIResponseListener {
        void onSuccess(String response);
        void onError(String error);
    }
    
    public AIService(Context context) {
        // Constructor is kept for consistency, but OkHttpClient is initialized directly.
    }

    public void getAiResponse(String text, AIResponseListener listener) {
        try {
            JSONObject jsonBody = new JSONObject();
            jsonBody.put("prompt", text);

            RequestBody body = RequestBody.create(jsonBody.toString(), JSON);
            Request request = new Request.Builder()
                    .url(CHAT_API_URL)
                    .post(body)
                    .build();

            client.newCall(request).enqueue(new SimpleCallback(listener));
        } catch (JSONException e) {
            listener.onError("Failed to create JSON request: " + e.getMessage());
        }
    }

    public void recognizeAudio(File audioFile, AIResponseListener listener) {
        RequestBody requestBody = new MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("audio", audioFile.getName(),
                        RequestBody.create(audioFile, MediaType.parse("audio/3gpp")))
                .build();

        Request request = new Request.Builder()
                .url(RECOGNIZE_API_URL)
                .post(requestBody)
                .build();

        client.newCall(request).enqueue(new SimpleCallback(listener));
    }
    
    public void generateDiagram(AIResponseListener listener) {
        Request request = new Request.Builder()
                .url(DIAGRAM_API_URL)
                .get()
                .build();

        client.newCall(request).enqueue(new SimpleCallback(listener));
    }

    private class SimpleCallback implements Callback {
        private final AIResponseListener listener;

        SimpleCallback(AIResponseListener listener) {
            this.listener = listener;
        }

        @Override
        public void onFailure(Call call, IOException e) {
            Log.e(TAG, "API call failed", e);
            mainHandler.post(() -> listener.onError("Network Error: " + e.getMessage()));
        }

        @Override
        public void onResponse(Call call, Response response) throws IOException {
            if (!response.isSuccessful()) {
                String errorBody = response.body() != null ? response.body().string() : "Unknown error";
                Log.e(TAG, "API response not successful: " + response.code() + " " + errorBody);
                mainHandler.post(() -> listener.onError("Server Error: " + response.code()));
                return;
            }

            String responseBody = response.body() != null ? response.body().string() : "";
            mainHandler.post(() -> listener.onSuccess(responseBody));
        }
    }
}