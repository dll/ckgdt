package com.example.helloworld;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import java.util.ArrayList;
import java.util.List;
import android.widget.ImageButton;

public class MessageAdapter extends RecyclerView.Adapter<MessageAdapter.MessageViewHolder> {
    
    private List<Message> messages = new ArrayList<>();
    private Context context;
    private ChatFragment chatFragment; // Reference to the fragment

    public MessageAdapter(Context context, List<Message> messages, ChatFragment fragment) {
        this.context = context;
        this.messages = messages;
        this.chatFragment = fragment;
    }
    
    public MessageAdapter(Context context, ChatFragment fragment) {
        this.context = context;
        this.chatFragment = fragment;
    }
    
    @NonNull
    @Override
    public MessageViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(context).inflate(R.layout.item_message, parent, false);
        return new MessageViewHolder(view);
    }
    
    @Override
    public void onBindViewHolder(@NonNull MessageViewHolder holder, int position) {
        Message message = messages.get(position);
        String display = message.getSender() + ": " + message.getContent();
        holder.messageText.setText(display);
        holder.timeText.setText(message.getTimestamp());
        
        // 根据消息类型设置不同的样式和功能
        switch (message.getType()) {
            case Message.TYPE_SENT:
                holder.messageText.setBackgroundColor(context.getResources().getColor(android.R.color.holo_blue_light));
                holder.speakButton.setVisibility(View.GONE);
                break;
            case Message.TYPE_RECEIVED:
                holder.messageText.setBackgroundColor(context.getResources().getColor(android.R.color.holo_green_light));
                holder.speakButton.setVisibility(View.VISIBLE);
                holder.speakButton.setOnClickListener(v -> {
                    if (chatFragment != null) {
                        chatFragment.speak(message.getContent());
                    }
                });
                break;
            case Message.TYPE_SYSTEM:
                holder.messageText.setBackgroundColor(context.getResources().getColor(android.R.color.darker_gray));
                holder.speakButton.setVisibility(View.GONE);
                break;
        }
    }
    
    @Override
    public int getItemCount() {
        return messages.size();
    }
    
    public void addMessage(Message message) {
        messages.add(message);
        notifyItemInserted(messages.size() - 1);
    }
    
    public void clearMessages() {
        messages.clear();
        notifyDataSetChanged();
    }

    public void setMessages(List<Message> newMessages) {
        messages.clear();
        if (newMessages != null) {
            messages.addAll(newMessages);
        }
        notifyDataSetChanged();
    }

    public List<Message> getMessages() {
        return new ArrayList<>(messages);
    }
    
    static class MessageViewHolder extends RecyclerView.ViewHolder {
        TextView messageText;
        TextView timeText;
        ImageButton speakButton;
        
        public MessageViewHolder(@NonNull View itemView) {
            super(itemView);
            messageText = itemView.findViewById(R.id.messageText);
            timeText = itemView.findViewById(R.id.timeText);
            speakButton = itemView.findViewById(R.id.speakButton);
        }
    }
}