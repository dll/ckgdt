package com.example.helloworld;

import androidx.annotation.NonNull;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentActivity;
import androidx.viewpager2.adapter.FragmentStateAdapter;

/**
 * A [FragmentPagerAdapter] that returns a fragment corresponding to
 * one of the sections/tabs/pages.
 */
public class SectionsPagerAdapter extends FragmentStateAdapter {

    public SectionsPagerAdapter(FragmentActivity fa) {
        super(fa);
    }

    @NonNull
    @Override
    public Fragment createFragment(int position) {
        // 根据位置返回不同的Fragment
        switch (position) {
            case 0:
                return new ChatFragment();
            case 1:
                return new VoiceFragment();
            case 2:
                return new PumlFragment();
            default:
                return new ChatFragment();
        }
    }

    @Override
    public int getItemCount() {
        // 返回3个页面
        return 3;
    }
}