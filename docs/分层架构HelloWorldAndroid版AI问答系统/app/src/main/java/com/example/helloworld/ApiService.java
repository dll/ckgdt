package com.example.helloworld;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.annotation.NonNull;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.HttpUrl;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;
import okio.ByteString;
import java.util.Arrays;
import java.util.Collections;
import java.util.concurrent.TimeUnit;
import java.net.URLEncoder;

public class ApiService {
    private static final String TAG = "ApiService";
    private static final String USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36";


    // PUML Servers
    public static final int SERVER_PLANTUML = 1;
    public static final int SERVER_KROKI = 2;

    // Model Constants
    public static final String MODEL_ZHIPU = "zhipu";
    public static final String MODEL_DEEPSEEK = "deepseek";

    // ZHIPU AI
    private static final String ZHIPU_AI_API_KEY = "5dc44da8d9dd4c28bf38cde316950f1e.nNIf7AXWrJXIcSyQ";
    private static final String ZHIPU_API_URL = "https://open.bigmodel.cn/api/paas/v4/chat/completions";
    private static final String ZHIPU_MODEL_ID = "glm-4";
    
    // DEEPSEEK
    private static final String DEEPSEEK_API_KEY = "sk-717ef9146311424daa2fbead8ed4682b";
    private static final String DEEPSEEK_API_URL = "https://api.deepseek.com/v1/chat/completions";
    private static final String DEEPSEEK_MODEL_ID = "deepseek-chat";

    // XUNFEI (IFlytek)
    private static final String XF_APP_ID = "ae4a0e4a";
    private static final String XF_API_KEY = "7385e5cb32d3465474e613dfbfc69310";
    private static final String XF_API_SECRET = "NTI2NzVlOWQ0ZTM5YTgzNGYzZDI5NjQx";
    private static final String XF_SPEECH_URL = "wss://iat-api.xfyun.cn/v2/iat";

    // PLANTUML
    private static final String PLANTUML_SERVER_URL = "http://www.plantuml.com/plantuml/png";
    private static final String KROKI_SERVER_URL = "https://kroki.io/plantuml/png";

    private final OkHttpClient client;
    private final Handler mainHandler;
    private static final MediaType JSON = MediaType.parse("application/json; charset=utf-8");

    public interface ApiResponseListener<T> {
        void onSuccess(T response);
        void onError(String error);
    }

    public ApiService(Context context) {
        this.client = new OkHttpClient.Builder()
                .connectTimeout(60, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .writeTimeout(60, TimeUnit.SECONDS)
                .protocols(Collections.singletonList(okhttp3.Protocol.HTTP_1_1))
                .build();
        this.mainHandler = new Handler(Looper.getMainLooper());
    }

    public void getAiCompletion(String prompt, String model, ApiResponseListener<String> listener) {
        String apiKey;
        String apiUrl;
        String modelId;

        if (MODEL_DEEPSEEK.equals(model)) {
            apiKey = DEEPSEEK_API_KEY;
            apiUrl = DEEPSEEK_API_URL;
            modelId = DEEPSEEK_MODEL_ID;
        } else { // Default to Zhipu
            apiKey = ZHIPU_AI_API_KEY;
            apiUrl = ZHIPU_API_URL;
            modelId = ZHIPU_MODEL_ID;
        }

        if (apiKey == null || apiKey.isEmpty()) { 
             listener.onError("API Key for " + model + " is not configured.");
             return;
        }

        try {
            JSONObject jsonBody = new JSONObject();
            jsonBody.put("model", modelId);
            JSONArray messages = new JSONArray();
            JSONObject message = new JSONObject();
            message.put("role", "user");
            message.put("content", prompt);
            messages.put(message);
            jsonBody.put("messages", messages);

            RequestBody body = RequestBody.create(jsonBody.toString(), JSON);
            Request request = new Request.Builder()
                    .url(apiUrl)
                    .header("Authorization", "Bearer " + apiKey)
                    .post(body)
                    .build();

            client.newCall(request).enqueue(new Callback() {
                @Override
                public void onFailure(@NonNull Call call, @NonNull IOException e) {
                    handleError(listener, "Network Error: " + e.getMessage());
                }

                @Override
                public void onResponse(@NonNull Call call, @NonNull Response response) throws IOException {
                    if (!response.isSuccessful()) {
                        handleError(listener, "Server Error: " + response.code() + " " + response.message());
                        return;
                    }
                    try (ResponseBody responseBody = response.body()) {
                        if (responseBody != null) {
                            String responseBodyString = responseBody.string();
                            JSONObject jsonResponse = new JSONObject(responseBodyString);
                            String content = jsonResponse.getJSONArray("choices").getJSONObject(0).getJSONObject("message").getString("content");
                            mainHandler.post(() -> listener.onSuccess(content));
                        } else {
                             handleError(listener, "Empty response body");
                        }
                    } catch (JSONException e) {
                        handleError(listener, "JSON Parsing Error: " + e.getMessage());
                    }
                }
            });
        } catch (JSONException e) {
            handleError(listener, "Failed to create JSON request: " + e.getMessage());
        }
    }

    public void recognizeAudio(File audioFile, ApiResponseListener<String> listener) {
        try {
            String authUrl = getAuthUrl(XF_SPEECH_URL, XF_API_KEY, XF_API_SECRET);
            Request request = new Request.Builder().url(authUrl).build();
            StringBuilder resultBuilder = new StringBuilder();

            client.newWebSocket(request, new WebSocketListener() {
                @Override
                public void onOpen(@NonNull WebSocket webSocket, @NonNull Response response) {
                    sendAudio(webSocket, audioFile);
                }

                @Override
                public void onMessage(@NonNull WebSocket webSocket, @NonNull String text) {
                    try {
                        JSONObject jsonResponse = new JSONObject(text);
                        if (jsonResponse.optInt("code", -1) != 0) {
                            handleError(listener, "XF API Error: " + jsonResponse.optString("message", "Unknown error"));
                            webSocket.close(1001, "API Error");
                            return;
                        }

                        JSONObject data = jsonResponse.getJSONObject("data");
                        JSONObject result = data.getJSONObject("result");
                        JSONArray ws = result.getJSONArray("ws");
                        for (int i = 0; i < ws.length(); i++) {
                            JSONObject wordInfo = ws.getJSONObject(i);
                            JSONArray cw = wordInfo.getJSONArray("cw");
                            JSONObject word = cw.getJSONObject(0);
                            resultBuilder.append(word.getString("w"));
                        }

                        if (data.getInt("status") == 2) {
                            String finalResult = resultBuilder.toString();
                            mainHandler.post(() -> {
                                if (finalResult.isEmpty()){
                                    listener.onError("未能识别语音");
                                } else {
                                    listener.onSuccess(finalResult);
                                }
                            });
                            webSocket.close(1000, "Transcription finished");
                        }
                    } catch (JSONException e) {
                        handleError(listener, "JSON Parsing Error: " + e.getMessage());
                    }
                }

                @Override
                public void onFailure(@NonNull WebSocket webSocket, @NonNull Throwable t, Response response) {
                    handleError(listener, "WebSocket Failure: " + t.getMessage());
                }
            });
        } catch (Exception e) {
            handleError(listener, "Authentication or WebSocket error: " + e.getMessage());
        }
    }

    private void sendAudio(WebSocket webSocket, File audioFile) {
        new Thread(() -> {
            try {
                // Frame 1: Start frame
                JSONObject startFrame = new JSONObject();
                JSONObject common = new JSONObject();
                common.put("app_id", XF_APP_ID);
                startFrame.put("common", common);
                JSONObject business = new JSONObject();
                business.put("language", "zh_cn");
                business.put("domain", "iat");
                business.put("accent", "mandarin");
                startFrame.put("business", business);
                JSONObject data = new JSONObject();
                data.put("status", 0);
                data.put("format", "audio/L16;rate=8000");
                data.put("encoding", "amr");
                startFrame.put("data", data);
                webSocket.send(startFrame.toString());

                // Frame 2: Audio data frames
                try (FileInputStream fis = new FileInputStream(audioFile)) {
                    byte[] buffer = new byte[1280];
                    int len;
                    while ((len = fis.read(buffer)) != -1) {
                        byte[] chunk = (len == buffer.length) ? buffer : Arrays.copyOf(buffer, len);
                        String audioBase64 = android.util.Base64.encodeToString(chunk, android.util.Base64.NO_WRAP);
                        
                        JSONObject audioFrame = new JSONObject();
                        JSONObject dataPayload = new JSONObject();
                        dataPayload.put("status", 1);
                        dataPayload.put("audio", audioBase64);
                        audioFrame.put("data", dataPayload);
                        
                        webSocket.send(audioFrame.toString());
                        Thread.sleep(40); // Simulate real-time audio flow
                    }
                }

                // Frame 3: End frame
                JSONObject endFrame = new JSONObject();
                JSONObject dataEnd = new JSONObject();
                dataEnd.put("status", 2);
                endFrame.put("data", dataEnd);
                webSocket.send(endFrame.toString());

            } catch (Exception e) {
                Log.e(TAG, "Error sending audio: " + e.getMessage());
            }
        }).start();
    }

    private String getAuthUrl(String hostUrl, String apiKey, String apiSecret) throws Exception {
        // Use OkHttp's HttpUrl to parse the URL, as java.net.URL doesn't support wss
        HttpUrl parsedUrl = HttpUrl.parse(hostUrl.replace("wss://", "https://"));
        String host = parsedUrl.host();
        String path = parsedUrl.encodedPath();

        SimpleDateFormat format = new SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss z", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("GMT"));
        String date = format.format(new Date());

        String builder = "host: " + host + "\n" +
                "date: " + date + "\n" +
                "GET " + path + " HTTP/1.1";

        Mac mac = Mac.getInstance("HmacSHA256");
        SecretKeySpec spec = new SecretKeySpec(apiSecret.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
        mac.init(spec);
        byte[] hexDigits = mac.doFinal(builder.getBytes(StandardCharsets.UTF_8));
        String sha = android.util.Base64.encodeToString(hexDigits, android.util.Base64.NO_WRAP);

        String authorization = String.format("api_key=\"%s\", algorithm=\"%s\", headers=\"%s\", signature=\"%s\"", apiKey, "hmac-sha256", "host date request-line", sha);

        HttpUrl authUrl = parsedUrl.newBuilder()
                .addQueryParameter("authorization", android.util.Base64.encodeToString(authorization.getBytes(StandardCharsets.UTF_8), android.util.Base64.NO_WRAP))
                .addQueryParameter("date", date)
                .addQueryParameter("host", host)
                .build();
        
        return authUrl.toString().replace("https://", "wss://");
    }

    public void generateDiagram(String pumlText, int serverType, ApiResponseListener<Bitmap> listener) {
        // Start the process with the user's selected server, with failover enabled.
        tryGenerateDiagram(pumlText, serverType, listener, false);
    }

    private void tryGenerateDiagram(String pumlText, final int serverType, final ApiResponseListener<Bitmap> listener, final boolean isFailover) {
        String serverName = (serverType == SERVER_KROKI) ? "Kroki" : "PlantUML";
        Log.d(TAG, "Attempting diagram generation with " + serverName + ". Is failover attempt: " + isFailover);

        String url = (serverType == SERVER_KROKI) ? KROKI_SERVER_URL : PLANTUML_SERVER_URL;

        RequestBody body = RequestBody.create(pumlText, MediaType.parse("text/plain; charset=utf-8"));
        Request request = new Request.Builder()
                .url(url)
                .header("User-Agent", USER_AGENT)
                .post(body)
                .build();

        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(@NonNull Call call, @NonNull IOException e) {
                if (!isFailover) {
                    int failoverServerType = (serverType == SERVER_PLANTUML) ? SERVER_KROKI : SERVER_PLANTUML;
                    Log.w(TAG, serverName + " failed (network error), failing over to " + ((failoverServerType == SERVER_KROKI) ? "Kroki" : "PlantUML"));
                    tryGenerateDiagram(pumlText, failoverServerType, listener, true);
                } else {
                    handleError(listener, "网络错误，两台服务器均无法连接。");
                }
            }

            @Override
            public void onResponse(@NonNull Call call, @NonNull Response response) {
                if (!response.isSuccessful()) {
                    try (ResponseBody responseBody = response.body()) { // Ensure body is consumed
                        if (!isFailover) {
                            int failoverServerType = (serverType == SERVER_PLANTUML) ? SERVER_KROKI : SERVER_PLANTUML;
                            Log.w(TAG, serverName + " failed with code " + response.code() + ", failing over to " + ((failoverServerType == SERVER_KROKI) ? "Kroki" : "PlantUML"));
                            tryGenerateDiagram(pumlText, failoverServerType, listener, true);
                        } else {
                            String serverError = "服务器错误: " + response.code();
                            if (response.code() == 400) {
                                serverError = "生成失败：服务器返回400错误，可能是PUML语法有误或服务器繁忙。";
                            }
                            handleError(listener, serverError);
                        }
                    }
                    return;
                }

                try (ResponseBody responseBody = response.body()) {
                    if (responseBody == null) {
                        handleError(listener, "服务器返回了空的响应体。");
                        return;
                    }
                    Bitmap bitmap = BitmapFactory.decodeStream(responseBody.byteStream());
                    if (bitmap != null) {
                        mainHandler.post(() -> listener.onSuccess(bitmap));
                    } else {
                        // This can happen if the response is not a valid image (e.g., an HTML error page)
                        if (!isFailover) {
                            int failoverServerType = (serverType == SERVER_PLANTUML) ? SERVER_KROKI : SERVER_PLANTUML;
                            Log.w(TAG, serverName + " returned invalid image data, failing over to " + ((failoverServerType == SERVER_KROKI) ? "Kroki" : "PlantUML"));
                            tryGenerateDiagram(pumlText, failoverServerType, listener, true);
                        } else {
                             handleError(listener, "图片数据无效，两台服务器均无法生成有效图片。");
                        }
                    }
                } catch (Exception e) {
                    handleError(listener, "解析服务器响应时出错: " + e.getMessage());
                }
            }
        });
    }

    private <T> void handleError(ApiResponseListener<T> listener, String message) {
        Log.e(TAG, message);
        mainHandler.post(() -> listener.onError(message));
    }
}
