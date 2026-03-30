package com.example.helloworld;

/**
 * 服务管理器单例类，用于在Activity和Fragment之间共享服务实例
 */
public class ServiceManager {
    private static ServiceManager instance;
    
    private MessageAdapter messageAdapter;
    private StorageService storageService;
    private ApiService apiService;
    
    private ServiceManager() {
        // 私有构造函数，防止外部实例化
    }
    
    /**
     * 获取ServiceManager单例实例
     * @return ServiceManager实例
     */
    public static synchronized ServiceManager getInstance() {
        if (instance == null) {
            instance = new ServiceManager();
        }
        return instance;
    }
    
    /**
     * Set the message adapter
     * @param messageAdapter The message adapter instance
     */
    public void setMessageAdapter(MessageAdapter messageAdapter) {
        this.messageAdapter = messageAdapter;
    }
    
    /**
     * Get the message adapter
     * @return The message adapter instance
     */
    public MessageAdapter getMessageAdapter() {
        return messageAdapter;
    }
    
    /**
     * Set the storage service
     * @param storageService The storage service instance
     */
    public void setStorageService(StorageService storageService) {
        this.storageService = storageService;
    }
    
    /**
     * Get the storage service
     * @return The storage service instance
     */
    public StorageService getStorageService() {
        return storageService;
    }
    
    /**
     * Set the AI service
     * @param apiService The AI service instance
     */
    public void setApiService(ApiService apiService) {
        this.apiService = apiService;
    }
    
    /**
     * Get the AI service
     * @return The AI service instance
     */
    public ApiService getApiService() {
        return apiService;
    }
}