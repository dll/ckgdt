#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
视频生成脚本：把 data/CKGDT/视频/*.md 转成 .mp4 视频文件。

依赖：moviepy, edge-tts, Pillow

用法：
    python tools/generate_ckgdt_videos.py            # 生成所有视频
    python tools/generate_ckgdt_videos.py 第一章      # 只生成某章视频
    python tools/generate_ckgdt_videos.py --list      # 列出所有视频脚本
"""

import asyncio
import os
import re
import sys
from pathlib import Path

# Windows 终端 UTF-8
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "data" / "CKGDT" / "视频"
OUT_DIR = ROOT / "data" / "CKGDT" / "输出" / "视频"

# TTS 配置
TTS_VOICE = "zh-CN-XiaoyiNeural"  # 女声，清晰专业
TTS_RATE = "+0%"

# 视频配置
VIDEO_WIDTH = 1920
VIDEO_HEIGHT = 1080
FPS = 24
FONT_SIZE_TITLE = 72
FONT_SIZE_NARRATION = 36
FONT_SIZE_SCENE = 48
BG_COLOR = (15, 23, 42)  # 深蓝背景 #0f172a
TEXT_COLOR = (255, 255, 255)
ACCENT_COLOR = (102, 126, 234)  # 主题色 #667eea


def parse_script(md_path: Path) -> dict:
    """解析视频脚本 Markdown 文件。"""
    content = md_path.read_text(encoding="utf-8")
    
    # 提取元数据
    meta = {}
    meta_match = re.search(r"## 视频元数据\n\n\| 项目 \| 内容 \|\n\|------\|------\|\n((?:\| .+ \|\n)+)", content)
    if meta_match:
        for line in meta_match.group(1).strip().split("\n"):
            parts = [p.strip() for p in line.split("|") if p.strip()]
            if len(parts) >= 2:
                meta[parts[0]] = parts[1]
    
    # 提取场景
    scenes = []
    scene_pattern = r"## (场景 \d+|[^\n]+)（[^）]*）\n\n\*\*画面描述\*\*：\n([^\n]+(?:\n[^\n]+)*?)\n\n\*\*旁白文字\*\*：\n> ([^\n]+(?:\n[^\n]+)*?)\n\n\*\*时长\*\*：([^\n]+)\n\*\*转场\*\*：([^\n]+)"
    
    for match in re.finditer(scene_pattern, content):
        scenes.append({
            "title": match.group(1).strip(),
            "visual": match.group(2).strip(),
            "narration": match.group(3).strip(),
            "duration": match.group(4).strip(),
            "transition": match.group(5).strip(),
        })
    
    # 提取片头和片尾
    intro_match = re.search(r"## 片头（[^）]*）\n\n\*\*画面\*\*：([^\n]+)\n\n\*\*BGM\*\*：([^\n]+)", content)
    outro_match = re.search(r"## 片尾（[^）]*）\n\n\*\*画面\*\*：([^\n]+)\n\n\*\*BGM\*\*：([^\n]+)", content)
    
    return {
        "meta": meta,
        "title": md_path.stem.replace("-视频脚本", ""),
        "scenes": scenes,
        "intro": {
            "visual": intro_match.group(1).strip() if intro_match else "",
            "bgm": intro_match.group(2).strip() if intro_match else "",
        } if intro_match else None,
        "outro": {
            "visual": outro_match.group(1).strip() if outro_match else "",
            "bgm": outro_match.group(2).strip() if outro_match else "",
        } if outro_match else None,
    }


async def generate_tts(text: str, output_path: Path, voice: str = TTS_VOICE):
    """使用 edge-tts 生成语音。"""
    import edge_tts
    communicate = edge_tts.Communicate(text, voice, rate=TTS_RATE)
    await communicate.save(str(output_path))


def create_text_clip(text: str, duration: float, font_size: int = FONT_SIZE_NARRATION,
                     color: tuple = TEXT_COLOR, bg_color: tuple = BG_COLOR,
                     width: int = VIDEO_WIDTH, height: int = VIDEO_HEIGHT):
    """创建文字画面。"""
    from moviepy.editor import TextClip
    
    # 自动换行
    max_chars_per_line = width // (font_size // 2)
    lines = []
    for paragraph in text.split("\n"):
        while len(paragraph) > max_chars_per_line:
            # 找最后一个标点或空格
            break_point = max_chars_per_line
            for i in range(min(max_chars_per_line, len(paragraph) - 1), 0, -1):
                if paragraph[i] in "，。、；：！？ ":
                    break_point = i + 1
                    break
            lines.append(paragraph[:break_point])
            paragraph = paragraph[break_point:]
        lines.append(paragraph)
    
    wrapped_text = "\n".join(lines)
    
    txt_clip = TextClip(
        wrapped_text,
        fontsize=font_size,
        color=f"rgb({color[0]},{color[1]},{color[2]})",
        font="Microsoft-YaHei",  # Windows 微软雅黑
        size=(width - 200, None),
        method="caption",
        align="center",
    )
    
    # 添加深色背景
    from moviepy.editor import ColorClip, CompositeVideoClip
    bg_clip = ColorClip(size=(width, height), color=bg_color)
    
    # 居中文字
    txt_clip = txt_clip.set_position("center").set_duration(duration)
    bg_clip = bg_clip.set_duration(duration)
    
    return CompositeVideoClip([bg_clip, txt_clip])


def generate_video(script: dict, output_dir: Path):
    """根据脚本生成视频。"""
    from moviepy.editor import (
        CompositeVideoClip, concatenate_videoclips, 
        ColorClip, TextClip, AudioFileClip
    )
    
    title = script["title"]
    scenes = script["scenes"]
    
    if not scenes:
        print(f"  [SKIP] {title}: 无场景定义")
        return None
    
    print(f"  生成 {len(scenes)} 个场景...")
    
    clips = []
    temp_dir = output_dir / "temp"
    temp_dir.mkdir(parents=True, exist_ok=True)
    
    # 片头（3秒）
    intro_text = f"{script['meta'].get('章节', title)}\n\n课程知识图谱与数字孪生平台"
    intro_clip = create_text_clip(intro_text, 3.0, FONT_SIZE_TITLE, ACCENT_COLOR)
    clips.append(intro_clip)
    
    # 各场景
    for i, scene in enumerate(scenes):
        print(f"    场景 {i+1}/{len(scenes)}: {scene['title']}")
        
        # 解析时长（从 "约 X 分钟" 提取）
        duration_match = re.search(r"(\d+(?:\.\d+)?)\s*分钟", scene["duration"])
        duration = float(duration_match.group(1)) * 60 if duration_match else 60.0
        
        # 生成语音
        audio_path = temp_dir / f"scene_{i+1}.mp3"
        try:
            asyncio.run(generate_tts(scene["narration"], audio_path))
            audio_clip = AudioFileClip(str(audio_path))
            # 使用语音时长
            duration = audio_clip.duration
        except Exception as e:
            print(f"      [WARN] TTS 失败: {e}")
            audio_clip = None
        
        # 创建画面
        scene_text = f"{scene['title']}\n\n{scene['narration'][:200]}..."
        video_clip = create_text_clip(scene_text, duration)
        
        # 添加音频
        if audio_clip:
            video_clip = video_clip.set_audio(audio_clip)
        
        clips.append(video_clip)
    
    # 片尾（3秒）
    outro_text = "感谢观看\n\n课程知识图谱与数字孪生平台"
    outro_clip = create_text_clip(outro_text, 3.0, FONT_SIZE_TITLE, ACCENT_COLOR)
    clips.append(outro_clip)
    
    # 合并所有片段
    print("  合并视频片段...")
    final_video = concatenate_videoclips(clips, method="compose")
    
    # 输出
    output_path = output_dir / f"{title}.mp4"
    final_video.write_videofile(
        str(output_path),
        fps=FPS,
        codec="libx264",
        audio_codec="aac",
        threads=4,
        logger=None,
    )
    
    # 清理临时文件
    for f in temp_dir.glob("*"):
        f.unlink()
    temp_dir.rmdir()
    
    print(f"  [OK] {output_path.name}")
    return output_path


def list_scripts():
    """列出所有视频脚本。"""
    scripts = sorted(SRC_DIR.glob("*.md"))
    print(f"\n共 {len(scripts)} 个视频脚本：")
    for s in scripts:
        print(f"  - {s.name}")


def main():
    if "--list" in sys.argv:
        list_scripts()
        return
    
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # 确定要生成的脚本
    if len(sys.argv) > 1 and sys.argv[1] != "--list":
        keyword = sys.argv[1]
        scripts = [s for s in SRC_DIR.glob("*.md") if keyword in s.name]
        if not scripts:
            print(f"[ERROR] 未找到包含 '{keyword}' 的脚本")
            return
    else:
        scripts = sorted(SRC_DIR.glob("*.md"))
    
    print(f"\n=== CKGDT 视频生成 ===")
    print(f"脚本目录: {SRC_DIR}")
    print(f"输出目录: {OUT_DIR}")
    print(f"待处理: {len(scripts)} 个\n")
    
    success = 0
    for script_path in scripts:
        print(f"[{script_path.name}]")
        try:
            script = parse_script(script_path)
            result = generate_video(script, OUT_DIR)
            if result:
                success += 1
        except Exception as e:
            print(f"  [ERROR] {e}")
    
    print(f"\n完成: {success}/{len(scripts)} 个视频")


if __name__ == "__main__":
    main()
