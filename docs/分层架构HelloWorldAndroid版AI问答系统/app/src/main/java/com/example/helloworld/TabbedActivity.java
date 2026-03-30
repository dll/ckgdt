package com.example.helloworld;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.IBinder;
import android.view.Menu;
import android.view.MenuItem;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;
import androidx.viewpager2.widget.ViewPager2;

import com.example.helloworld.databinding.ActivityTabbedBinding;
import com.google.android.material.tabs.TabLayout;
import com.google.android.material.tabs.TabLayoutMediator;

import java.util.ArrayList;
import java.util.List;

public class TabbedActivity extends AppCompatActivity {

    private ActivityTabbedBinding binding;
    
    private MessageAdapter messageAdapter;
    private final List<Message> messageList = new ArrayList<>();
    private StorageService storageService;
    private ApiService apiService;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        binding = ActivityTabbedBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        setSupportActionBar(binding.toolbar);

        initServices();
        setupViewPager();
    }

    private void initServices() {
        ServiceManager serviceManager = ServiceManager.getInstance();

        storageService = new StorageService(this);
        apiService = new ApiService(this);

        // MessageAdapter is now created within ChatFragment, no need to create it here.
        // List<Message> messageList = storageService.loadMessages();
        // messageAdapter = new MessageAdapter(this, messageList);

        serviceManager.setStorageService(storageService);
        serviceManager.setApiService(apiService);
        // serviceManager.setMessageAdapter(messageAdapter);
    }

    private void setupViewPager() {
        SectionsPagerAdapter sectionsPagerAdapter = new SectionsPagerAdapter(this);
        binding.container.setAdapter(sectionsPagerAdapter);
        binding.container.setOffscreenPageLimit(3);

        new TabLayoutMediator(binding.tabs, binding.container, (tab, position) -> {
            if (position == 0) {
                    tab.setText(R.string.tab_text_1);
            } else if (position == 1) {
                    tab.setText(R.string.tab_text_2);
            } else {
                    tab.setText(R.string.tab_text_3);
            }
        }).attach();
    }
    
    @Override
    protected void onStart() {
        super.onStart();
    }
    
    @Override
    protected void onStop() {
        super.onStop();
    }
    
    @Override
    protected void onDestroy() {
        saveMessages();
        super.onDestroy();
    }
    
    private void saveMessages() {
        if (storageService != null && messageAdapter != null) {
            storageService.saveMessages(messageAdapter.getMessages());
        }
    }
    
    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.main_menu, menu);
        // Set the checked item based on current selection
        String currentModel = storageService.loadSetting(StorageService.KEY_SELECTED_AI_MODEL, ApiService.MODEL_ZHIPU);
        if (ApiService.MODEL_DEEPSEEK.equals(currentModel)) {
            menu.findItem(R.id.action_select_deepseek).setChecked(true);
        } else {
            menu.findItem(R.id.action_select_zhipu).setChecked(true);
        }
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        int id = item.getItemId();
        String selectedModel = null;
        String modelName = "";

        if (id == R.id.action_select_zhipu) {
            selectedModel = ApiService.MODEL_ZHIPU;
            modelName = "智谱大模型";
            item.setChecked(true);
        } else if (id == R.id.action_select_deepseek) {
            selectedModel = ApiService.MODEL_DEEPSEEK;
            modelName = "DeepSeek大模型";
            item.setChecked(true);
        }

        if (selectedModel != null) {
            storageService.saveSetting(StorageService.KEY_SELECTED_AI_MODEL, selectedModel);
            Toast.makeText(this, "已切换到: " + modelName, Toast.LENGTH_SHORT).show();
            return true;
        }

        return super.onOptionsItemSelected(item);
    }
}