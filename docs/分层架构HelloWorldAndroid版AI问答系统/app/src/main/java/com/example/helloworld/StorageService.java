package com.example.helloworld;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;
import android.os.Environment;

public class StorageService {
    private static final String TAG = "StorageService";
    private static final String PREFS_NAME = "AppPrefs";
    public static final String KEY_SELECTED_AI_MODEL = "selected_ai_model";
    private static final String MESSAGES_FILE = "messages.json";
    private static final String SETTINGS_FILE = "settings.json";
    
    private Context context;
    private SharedPreferences prefs;
    
    public StorageService(Context context) {
        this.context = context;
        this.prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }
    
    // 保存消息到本地存储
    public void saveMessages(List<Message> messages) {
        try {
            JSONObject messagesJson = new JSONObject();
            
            for (int i = 0; i < messages.size(); i++) {
                Message message = messages.get(i);
                JSONObject messageJson = new JSONObject();
                messageJson.put("sender", message.getSender());
                messageJson.put("content", message.getContent());
                messageJson.put("type", message.getType());
                messageJson.put("timestamp", message.getTimestamp());
                
                messagesJson.put("message_" + i, messageJson);
            }
            
            // 保存到内部存储
            FileOutputStream fos = context.openFileOutput(MESSAGES_FILE, Context.MODE_PRIVATE);
            fos.write(messagesJson.toString().getBytes());
            fos.close();
            
            Log.d(TAG, "Messages saved successfully");
        } catch (JSONException | IOException e) {
            Log.e(TAG, "Failed to save messages", e);
        }
    }
    
    // 从本地存储加载消息
    public List<Message> loadMessages() {
        List<Message> messages = new ArrayList<>();
        
        try {
            File file = new File(context.getFilesDir(), MESSAGES_FILE);
            if (!file.exists()) {
                Log.d(TAG, "Messages file does not exist");
                return messages;
            }
            
            FileInputStream fis = context.openFileInput(MESSAGES_FILE);
            BufferedReader reader = new BufferedReader(new InputStreamReader(fis));
            StringBuilder jsonBuilder = new StringBuilder();
            String line;
            
            while ((line = reader.readLine()) != null) {
                jsonBuilder.append(line);
            }
            
            reader.close();
            fis.close();
            
            JSONObject messagesJson = new JSONObject(jsonBuilder.toString());
            
            // 解析消息
            for (int i = 0; i < messagesJson.length(); i++) {
                String key = "message_" + i;
                if (messagesJson.has(key)) {
                    JSONObject messageJson = messagesJson.getJSONObject(key);
                    String sender = messageJson.getString("sender");
                    String content = messageJson.getString("content");
                    String type = messageJson.getString("type");
                    String timestamp = messageJson.getString("timestamp");
                    
                    Message message = new Message(sender, content, type, timestamp);
                    messages.add(message);
                }
            }
            
            Log.d(TAG, "Messages loaded successfully, count: " + messages.size());
        } catch (JSONException | IOException e) {
            Log.e(TAG, "Failed to load messages", e);
        }
        
        return messages;
    }
    
    // 清空消息
    public void clearMessages() {
        try {
            File file = new File(context.getFilesDir(), MESSAGES_FILE);
            if (file.exists()) {
                file.delete();
                Log.d(TAG, "Messages cleared successfully");
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to clear messages", e);
        }
    }
    
    // 保存设置
    public void saveSetting(String key, String value) {
        SharedPreferences.Editor editor = prefs.edit();
        editor.putString(key, value);
        editor.apply();
    }
    
    // 加载设置
    public String loadSetting(String key, String defaultValue) {
        return prefs.getString(key, defaultValue);
    }
    
    // 保存设置JSON
    public void saveSettings(JSONObject settings) {
        try {
            // 保存到内部存储
            FileOutputStream fos = context.openFileOutput(SETTINGS_FILE, Context.MODE_PRIVATE);
            fos.write(settings.toString().getBytes());
            fos.close();
            
            Log.d(TAG, "Settings saved successfully");
        } catch (IOException e) {
            Log.e(TAG, "Failed to save settings", e);
        }
    }
    
    // 加载设置JSON
    public JSONObject loadSettings() {
        try {
            File file = new File(context.getFilesDir(), SETTINGS_FILE);
            if (!file.exists()) {
                Log.d(TAG, "Settings file does not exist");
                return new JSONObject();
            }
            
            FileInputStream fis = context.openFileInput(SETTINGS_FILE);
            BufferedReader reader = new BufferedReader(new InputStreamReader(fis));
            StringBuilder jsonBuilder = new StringBuilder();
            String line;
            
            while ((line = reader.readLine()) != null) {
                jsonBuilder.append(line);
            }
            
            reader.close();
            fis.close();
            
            return new JSONObject(jsonBuilder.toString());
        } catch (JSONException | IOException e) {
            Log.e(TAG, "Failed to load settings", e);
            return new JSONObject();
        }
    }
    
    // 保存PUML图表
    public void savePUMLChart(String name, String pumlCode) {
        try {
            File pumlDir = new File(context.getFilesDir(), "puml");
            if (!pumlDir.exists()) {
                pumlDir.mkdir();
            }
            
            File pumlFile = new File(pumlDir, name + ".puml");
            FileOutputStream fos = new FileOutputStream(pumlFile);
            fos.write(pumlCode.getBytes());
            fos.close();
            
            Log.d(TAG, "PUML chart saved successfully: " + name);
        } catch (IOException e) {
            Log.e(TAG, "Failed to save PUML chart", e);
        }
    }
    
    // 加载PUML图表
    public String loadPUMLChart(String name) {
        try {
            File pumlFile = new File(context.getFilesDir(), "puml/" + name + ".puml");
            if (!pumlFile.exists()) {
                Log.d(TAG, "PUML chart file does not exist: " + name);
                return null;
            }
            
            FileInputStream fis = new FileInputStream(pumlFile);
            BufferedReader reader = new BufferedReader(new InputStreamReader(fis));
            StringBuilder pumlBuilder = new StringBuilder();
            String line;
            
            while ((line = reader.readLine()) != null) {
                pumlBuilder.append(line).append("\n");
            }
            
            reader.close();
            fis.close();
            
            return pumlBuilder.toString();
        } catch (IOException e) {
            Log.e(TAG, "Failed to load PUML chart", e);
            return null;
        }
    }
    
    // 获取所有PUML图表名称
    public List<String> getPUMLChartNames() {
        List<String> chartNames = new ArrayList<>();
        
        try {
            File pumlDir = new File(context.getFilesDir(), "puml");
            if (!pumlDir.exists()) {
                return chartNames;
            }
            
            File[] files = pumlDir.listFiles();
            if (files != null) {
                for (File file : files) {
                    if (file.getName().endsWith(".puml")) {
                        String name = file.getName().replace(".puml", "");
                        chartNames.add(name);
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to get PUML chart names", e);
        }
        
        return chartNames;
    }
    
    // 添加缺失的savePUML方法
    public void savePUML(String fileName, String pumlCode) {
        try {
            File pumlDir = new File(context.getFilesDir(), "puml");
            if (!pumlDir.exists()) {
                pumlDir.mkdir();
            }
            
            File pumlFile = new File(pumlDir, fileName);
            FileOutputStream fos = new FileOutputStream(pumlFile);
            fos.write(pumlCode.getBytes());
            fos.close();
            
            Log.d(TAG, "PUML file saved successfully: " + fileName);
        } catch (IOException e) {
            Log.e(TAG, "Failed to save PUML file", e);
        }
    }
    
    // 添加缺失的loadPUML方法
    public String loadPUML(String fileName) {
        try {
            File pumlFile = new File(context.getFilesDir(), "puml/" + fileName);
            if (!pumlFile.exists()) {
                Log.d(TAG, "PUML file does not exist: " + fileName);
                return null;
            }
            
            FileInputStream fis = new FileInputStream(pumlFile);
            BufferedReader reader = new BufferedReader(new InputStreamReader(fis));
            StringBuilder pumlBuilder = new StringBuilder();
            String line;
            
            while ((line = reader.readLine()) != null) {
                pumlBuilder.append(line).append("\n");
            }
            
            reader.close();
            fis.close();
            
            return pumlBuilder.toString();
        } catch (IOException e) {
            Log.e(TAG, "Failed to load PUML file", e);
            return null;
        }
    }
    
    // 添加缺失的getPUMLFiles方法
    public List<String> getPUMLFiles() {
        List<String> pumlFiles = new ArrayList<>();
        
        try {
            File pumlDir = new File(context.getFilesDir(), "puml");
            if (!pumlDir.exists()) {
                return pumlFiles;
            }
            
            File[] files = pumlDir.listFiles();
            if (files != null) {
                for (File file : files) {
                    if (file.getName().endsWith(".puml")) {
                        pumlFiles.add(file.getName());
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to get PUML files", e);
        }
        
        return pumlFiles;
    }

    public File createAudioFile() throws IOException {
        // Create an audio file name
        String timeStamp = new java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.getDefault()).format(new java.util.Date());
        String audioFileName = "AUDIO_" + timeStamp + "_";
        File storageDir = context.getExternalFilesDir(Environment.DIRECTORY_MUSIC);
        if (storageDir != null && !storageDir.exists()){
            storageDir.mkdirs();
        }
        File audio = File.createTempFile(
                audioFileName,  /* prefix */
                ".3gp",         /* suffix */
                storageDir      /* directory */
        );
        return audio;
    }
    
    // 添加缺失的saveAudioFile方法
    public void saveAudioFile(String audioFilePath) {
        try {
            // 创建音频文件目录
            File audioDir = new File(context.getFilesDir(), "audio");
            if (!audioDir.exists()) {
                audioDir.mkdir();
            }
            
            // 获取原始文件名
            File originalFile = new File(audioFilePath);
            String fileName = originalFile.getName();
            
            // 创建目标文件
            File destFile = new File(audioDir, fileName);
            
            // 复制文件
            FileInputStream fis = new FileInputStream(originalFile);
            FileOutputStream fos = new FileOutputStream(destFile);
            
            byte[] buffer = new byte[1024];
            int length;
            while ((length = fis.read(buffer)) > 0) {
                fos.write(buffer, 0, length);
            }
            
            fis.close();
            fos.close();
            
            Log.d(TAG, "Audio file saved successfully: " + destFile.getAbsolutePath());
        } catch (IOException e) {
            Log.e(TAG, "Failed to save audio file", e);
        }
    }
    
    // 添加缺失的saveTranscription方法
    public void saveTranscription(String audioFilePath, String transcription) {
        try {
            // 创建转录文件目录
            File transcriptionDir = new File(context.getFilesDir(), "transcriptions");
            if (!transcriptionDir.exists()) {
                transcriptionDir.mkdir();
            }
            
            // 获取原始文件名（不含扩展名）
            File originalFile = new File(audioFilePath);
            String fileName = originalFile.getName();
            if (fileName.contains(".")) {
                fileName = fileName.substring(0, fileName.lastIndexOf('.'));
            }
            
            // 创建转录文件
            File transcriptionFile = new File(transcriptionDir, fileName + ".txt");
            FileOutputStream fos = new FileOutputStream(transcriptionFile);
            fos.write(transcription.getBytes());
            fos.close();
            
            Log.d(TAG, "Transcription saved successfully: " + transcriptionFile.getAbsolutePath());
        } catch (IOException e) {
            Log.e(TAG, "Failed to save transcription", e);
        }
    }
}