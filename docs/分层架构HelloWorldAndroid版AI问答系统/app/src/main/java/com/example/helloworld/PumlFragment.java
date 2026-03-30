package com.example.helloworld;

import android.graphics.Bitmap;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.RadioGroup;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.fragment.app.Fragment;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public class PumlFragment extends Fragment {

    // --- UI Components ---
    private Button generateClassDiagramButton;
    private Button generateSequenceDiagramButton;
    private Button clearDiagramsButton;
    private RadioGroup serverRadioGroup;
    private ImageView pumlImageView;
    private TextView pumlStatusText;

    private ApiService apiService;
    private File diagramsDir;

    // --- PUML Source Code Constants ---

    private static final String CLASS_DIAGRAM_PUML = 
        "@startuml\n" +
        "title Android App - Architecture Class Diagram\n\n" +
        "package \"UI Layer (Fragments)\" {\n" +
        "  class ChatFragment\n" +
        "  class VoiceFragment\n" +
        "  class PumlFragment\n" +
        "}\n\n" +
        "package \"Service Layer\" {\n" +
        "  class ApiService {\n" +
        "    + getAiCompletion(...)\n" +
        "    + recognizeAudio(...)\n" +
        "    + generateDiagram(...)\n" +
        "  }\n" +
        "  class StorageService {\n" +
        "    + saveMessages(...)\n" +
        "    + loadMessages()\n" +
        "  }\n" +
        "}\n\n" +
        "package \"Adapter\" {\n" +
        "  class MessageAdapter\n" +
        "}\n\n" +
        "ChatFragment --> ApiService\n" +
        "ChatFragment --> StorageService\n" +
        "ChatFragment --> MessageAdapter\n" +
        "VoiceFragment --> ApiService\n" +
        "PumlFragment --> ApiService\n" +
        "@enduml";

    private static final String SEQUENCE_DIAGRAM_PUML =
        "@startuml\n" +
        "title Android App - AI QA Sequence Diagram\n\n" +
        "actor User\n" +
        "participant \"ChatFragment\" as Fragment\n" +
        "participant \"ApiService\" as Service\n" +
        "participant \"ZhiPu AI API\" as API\n" +
        "participant \"MessageAdapter\" as Adapter\n\n" +
        "User -> Fragment : 输入问题, 点击 \"发送\"\n" +
        "activate Fragment\n\n" +
        "Fragment -> Adapter : addMessage(userMsg)\n" +
        "Fragment -> Fragment : 更新UI\n\n" +
        "Fragment -> Service : getAiCompletion(prompt)\n" +
        "activate Service\n\n" +
        "Service -> API : POST /chat/completions\n" +
        "activate API\n" +
        "API --> Service : 返回答案JSON\n" +
        "deactivate API\n\n" +
        "Service -> Fragment : onSuccess(aiResponse)\n" +
        "deactivate Service\n\n" +
        "Fragment -> Adapter : addMessage(aiMsg)\n" +
        "Fragment -> Fragment : 滚动并更新UI\n" +
        "deactivate Fragment\n\n" +
        "@enduml";

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        apiService = ServiceManager.getInstance().getApiService();
        if (getContext() != null) {
            diagramsDir = new File(getContext().getFilesDir(), "diagrams");
            if (!diagramsDir.exists()) {
                diagramsDir.mkdirs();
            }
        }
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        View view = inflater.inflate(R.layout.fragment_puml, container, false);

        generateClassDiagramButton = view.findViewById(R.id.generateClassDiagramButton);
        generateSequenceDiagramButton = view.findViewById(R.id.generateSequenceDiagramButton);
        clearDiagramsButton = view.findViewById(R.id.clearDiagramsButton);
        serverRadioGroup = view.findViewById(R.id.serverRadioGroup);
        pumlImageView = view.findViewById(R.id.pumlImageView);
        pumlStatusText = view.findViewById(R.id.pumlStatusText);

        generateClassDiagramButton.setOnClickListener(v -> generateDiagram("class-diagram", CLASS_DIAGRAM_PUML));
        generateSequenceDiagramButton.setOnClickListener(v -> generateDiagram("sequence-diagram", SEQUENCE_DIAGRAM_PUML));
        clearDiagramsButton.setOnClickListener(v -> clearDiagrams());

        return view;
    }

    private void generateDiagram(String baseFileName, String pumlContent) {
        updateStatus("正在生成 " + baseFileName + "...");

        int selectedId = serverRadioGroup.getCheckedRadioButtonId();
        int serverType;
        if (selectedId == R.id.krokiRadioButton) {
            serverType = ApiService.SERVER_KROKI;
        } else {
            serverType = ApiService.SERVER_PLANTUML;
        }

        // 1. Save .puml file
        File pumlFile = new File(diagramsDir, baseFileName + ".puml");
        try (FileOutputStream fos = new FileOutputStream(pumlFile)) {
            fos.write(pumlContent.getBytes(StandardCharsets.UTF_8));
            showToast(baseFileName + ".puml 已保存");
        } catch (IOException e) {
            updateStatus("错误: 无法保存 .puml 文件");
            showToast("错误: " + e.getMessage());
            return;
        }
        
        // 2. Generate and save .png file
        apiService.generateDiagram(pumlContent, serverType, new ApiService.ApiResponseListener<Bitmap>() {
            @Override
            public void onSuccess(Bitmap bitmap) {
                pumlImageView.setImageBitmap(bitmap);
                File pngFile = new File(diagramsDir, baseFileName + ".png");
                try (FileOutputStream out = new FileOutputStream(pngFile)) {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
                    updateStatus(baseFileName + ".png 已生成并保存");
                    showToast(baseFileName + ".png 已保存");
                } catch (IOException e) {
                    updateStatus("错误: 无法保存 .png 文件");
                    showToast("错误: " + e.getMessage());
                }
            }

            @Override
            public void onError(String error) {
                updateStatus("错误: " + error);
                showToast("生成失败: " + error);
            }
        });
    }

    private void clearDiagrams() {
        if (diagramsDir != null && diagramsDir.exists()) {
            File[] files = diagramsDir.listFiles();
            if (files != null) {
                for (File file : files) {
                    file.delete();
                }
            }
            pumlImageView.setImageDrawable(null);
            updateStatus("所有图表已清除");
            showToast("所有图表已清除");
        }
    }

    private void updateStatus(String text) {
        if (pumlStatusText != null) {
            pumlStatusText.setText(text);
        }
    }

    private void showToast(String message) {
        if (getContext() != null) {
            Toast.makeText(getContext(), message, Toast.LENGTH_SHORT).show();
        }
    }
}