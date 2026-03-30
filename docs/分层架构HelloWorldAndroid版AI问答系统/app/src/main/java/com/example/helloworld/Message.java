package com.example.helloworld;

public class Message {
    public static final String TYPE_SENT = "sent";
    public static final String TYPE_RECEIVED = "received";
    public static final String TYPE_SYSTEM = "system";
    
    private String sender;
    private String content;
    private String type;
    private String timestamp;
    
    public Message(String sender, String content, String type, String timestamp) {
        this.sender = sender;
        this.content = content;
        this.type = type;
        this.timestamp = timestamp;
    }
    
    public String getSender() {
        return sender;
    }
    
    public void setSender(String sender) {
        this.sender = sender;
    }
    
    public String getContent() {
        return content;
    }
    
    public void setContent(String content) {
        this.content = content;
    }
    
    public String getType() {
        return type;
    }
    
    public void setType(String type) {
        this.type = type;
    }
    
    public String getTimestamp() {
        return timestamp;
    }
    
    public void setTimestamp(String timestamp) {
        this.timestamp = timestamp;
    }
}