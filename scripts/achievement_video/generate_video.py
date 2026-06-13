#!/usr/bin/env python3
"""
课程达成度评价系统操作指南视频生成器
使用 edge-tts (男声) + moviepy 生成带字幕的 MP4 演示视频
"""

import os
import re
import asyncio
import subprocess
import json
import shutil
from pathlib import Path

# ============================================================
# 配置
# ============================================================
BASE_DIR = Path(__file__).resolve().parent
SCREENSHOT_DIR = BASE_DIR.parent.parent / "assets" / "help" / "archievement"
OUTPUT_DIR = BASE_DIR / "output"
TEMP_DIR = BASE_DIR / "temp"

# ffmpeg 路径
FFMPEG = r"D:\development\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
FFPROBE = r"D:\development\ffmpeg-8.0.1-full_build\bin\ffprobe.exe"

# 视频参数
VIDEO_W, VIDEO_H = 1920, 1080
FPS = 24

# edge-tts 配置
TTS_VOICE = "zh-CN-YunxiNeural"  # 男声
TTS_RATE = "+0%"

# 截图 → 旁白映射 (文件名, 旁白文本, 额外时长秒)
SEGMENTS = [
    ("01达成度概览.png", "课程达成度评价系统操作指南。本视频将带您了解课程达成度评价系统的完整操作流程。系统支持为任意课程创建达成度评价批次，不限于特定课程。", 1.0),
    ("01达成度概览.png", "首先，让我们进入达成度概览页面。这里展示了所有已创建的评价批次，每个批次包含课程名称、班级、学期和学生人数等信息。", 0.5),
    ("01达成度概览-上传大纲.png", "第一步，上传课程大纲。首次使用时，需要上传该课程的教学大纲。系统通过人工智能自动解析大纲，提取课程目标、权重和毕业要求指标点。大纲数据按课程名存储，不同课程的大纲互相独立。", 1.0),
    ("02成绩管理.png", "第二步，新建达成度批次。点击右下角加号按钮，选择新建批次。填写批次名称、课程名称、班级和学期信息。每个批次对应一个班级的一个学期。", 0.5),
    ("02成绩管理-导下载模板.png", "第三步，导入成绩数据。进入成绩管理标签页。推荐方式是先下载模板，系统会生成包含目标拆分表头的Excel模板。", 0.5),
    ("02成绩管理-导入成绩.png", "模板包含三个工作表，分别是平时成绩、实验成绩和期末成绩。在Excel中填写学生成绩后，回到系统点击导入成绩Excel。系统会自动校验数据，检查异常分值、重复学号和缺失学生。", 1.0),
    ("03计算过程.png", "第四步，计算达成度。进入计算过程标签页。这里展示了大纲课程目标和考核方式，包括平时成绩占百分之二十、实验成绩占百分之三十、期末成绩占百分之五十的权重分配。", 0.5),
    ("03计算过程-计算达成度.png", "点击计算达成度按钮，系统自动完成所有计算。计算结果以可视化图表展示，包括四个目标的达成度柱状图和班级平均指标点达成度雷达图。总体达成度为百分之七十七点四，达成等级为良好。", 1.0),
    ("04平时达成.png", "第五步，查看各环节达成情况。平时达成页面展示平时成绩的评价结构。课堂表现对应目标一，期间测验对应目标二，课外学习对应目标四。", 0.5),
    ("05实验达成.png", "实验达成页面展示实验成绩的评价结构。实验一到实验七分别对应不同的课程目标，系统自动计算每位学生的实验达成度。", 0.5),
    ("06考核达成.png", "考核达成页面展示期末考核的评价结构。项目、小组、个人和答辩分别对应四个课程目标。每个环节都提供班级平均指标点达成度雷达图，方便教师进行对比分析。", 0.5),
    ("07持续改进.png", "第六步，持续改进。系统自动生成改进建议。上轮教学改进措施执行情况帮助教师跟踪改进效果。针对每个未达标的目标，系统给出具体的改进建议和关联内容。", 0.5),
    ("08生成报告.png", "第七步，生成报告。进入报告生成标签页。支持三种导出格式：Markdown预览、Word导出和Excel导出。", 0.5),
    ("08生成报告-md格式预览.png", "Markdown格式可以在线预览完整报告内容，方便教师快速查看。", 0.5),
    ("08生成报告-word格式导出.png", "Word报告包含基本信息、考核标准、达成度计算和结果分析四个部分，符合学校规范格式。", 0.5),
    ("08生成报告-excel格式导出.png", "Excel报告包含五个工作表，涵盖平时、实验、期末成绩和达成度汇总，支持图表展示。导出的文件保存在输出目录中，可通过提示直接打开查看。", 1.0),
    ("08生成报告.png", "课程达成度评价系统，让教学评价更加科学、高效、便捷。感谢观看，如需帮助请点击页面上的帮助按钮。", 0.0),
]


def parse_srt(srt_path: str) -> list:
    """解析 SRT 字幕文件"""
    with open(srt_path, "r", encoding="utf-8") as f:
        content = f.read()
    blocks = re.split(r"\n\n+", content.strip())
    subs = []
    for block in blocks:
        lines = block.strip().split("\n")
        if len(lines) >= 3:
            time_match = re.match(
                r"(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})",
                lines[1],
            )
            if time_match:
                subs.append(
                    {
                        "start": time_match.group(1),
                        "end": time_match.group(2),
                        "text": " ".join(lines[2:]),
                    }
                )
    return subs


def srt_time_to_seconds(t: str) -> float:
    """SRT 时间格式转秒数"""
    h, m, rest = t.split(":")
    s, ms = rest.split(",")
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


async def generate_tts(segments: list, output_dir: Path):
    """使用 edge-tts 生成各段语音"""
    import edge_tts

    audio_files = []
    for i, (_, text, _) in enumerate(segments):
        out_file = output_dir / f"tts_{i:03d}.mp3"
        communicate = edge_tts.Communicate(text, TTS_VOICE, rate=TTS_RATE)
        await communicate.save(str(out_file))
        audio_files.append(out_file)
        print(f"  TTS {i+1}/{len(segments)}: {out_file.name}")
    return audio_files


def get_audio_duration(audio_path: str) -> float:
    """用 ffprobe 获取音频时长"""
    cmd = [
        FFPROBE,
        "-v",
        "quiet",
        "-print_format",
        "json",
        "-show_format",
        str(audio_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    info = json.loads(result.stdout)
    return float(info["format"]["duration"])


def create_subtitle_srt(segments, audio_durations, output_path):
    """根据各段音频时长生成最终 SRT 字幕"""
    current_time = 0.0
    srt_lines = []
    sub_idx = 1

    for i, (_, text, extra) in enumerate(segments):
        duration = audio_durations[i] + extra
        # 将长文本按标点拆分为短句
        sentences = re.split(r"[。！？，；]", text)
        sentences = [s.strip() for s in sentences if s.strip()]

        if not sentences:
            current_time += duration
            continue

        # 按字数比例分配时间
        total_chars = sum(len(s) for s in sentences)
        for sent in sentences:
            sent_duration = (len(sent) / total_chars) * duration if total_chars > 0 else duration / len(sentences)
            start_ts = format_timestamp(current_time)
            end_ts = format_timestamp(current_time + sent_duration)
            srt_lines.append(f"{sub_idx}")
            srt_lines.append(f"{start_ts} --> {end_ts}")
            srt_lines.append(sent)
            srt_lines.append("")
            sub_idx += 1
            current_time += sent_duration

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(srt_lines))
    return output_path


def format_timestamp(seconds):
    """秒数转 SRT 时间戳"""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int((seconds % 1) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def generate_video_with_ffmpeg(segments, audio_files, audio_durations, srt_path, output_path):
    """使用 ffmpeg 合成最终视频"""
    temp_dir = TEMP_DIR / "clips"
    temp_dir.mkdir(parents=True, exist_ok=True)

    # 1) 为每段截图+语音生成视频片段
    clip_files = []
    for i, (img_name, _, extra) in enumerate(segments):
        img_path = SCREENSHOT_DIR / img_name
        audio_path = audio_files[i]
        duration = audio_durations[i] + extra
        clip_path = temp_dir / f"clip_{i:03d}.mp4"
        clip_files.append(clip_path)

        # Ken Burns 效果：缓慢放大
        # zoompan: z 从 1.0 缓慢到 1.08，持续 duration 秒
        total_frames = int(duration * FPS)
        cmd = [
            FFMPEG, "-y",
            "-loop", "1",
            "-i", str(img_path),
            "-i", str(audio_path),
            "-filter_complex",
            f"[0:v]scale={VIDEO_W}:{VIDEO_H}:force_original_aspect_ratio=decrease,"
            f"pad={VIDEO_W}:{VIDEO_H}:(ow-iw)/2:(oh-ih)/2:color=black,"
            f"zoompan=z='min(zoom+0.0003,1.08)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            f"d={total_frames}:s={VIDEO_W}x{VIDEO_H}:fps={FPS}[v]",
            "-map", "[v]",
            "-map", "1:a",
            "-c:v", "libx264",
            "-preset", "fast",
            "-crf", "23",
            "-c:a", "aac",
            "-b:a", "128k",
            "-t", str(duration),
            "-pix_fmt", "yuv420p",
            str(clip_path),
        ]
        print(f"  Clip {i+1}/{len(segments)}: {img_name} ({duration:.1f}s)")
        subprocess.run(cmd, capture_output=True, text=True, check=True)

    # 2) 生成 concat 列表
    concat_list = temp_dir / "concat.txt"
    with open(concat_list, "w", encoding="utf-8") as f:
        for cf in clip_files:
            f.write(f"file '{cf}'\n")

    # 3) 拼接所有片段
    concat_path = temp_dir / "concat_raw.mp4"
    cmd = [
        FFMPEG, "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", str(concat_list),
        "-c:v", "libx264",
        "-preset", "fast",
        "-crf", "23",
        "-c:a", "aac",
        "-b:a", "128k",
        "-pix_fmt", "yuv420p",
        str(concat_path),
    ]
    print("  Concatenating clips...")
    subprocess.run(cmd, capture_output=True, text=True, check=True)

    # 4) 烧录字幕
    # 使用 subtitles filter 烧录 SRT
    srt_escaped = str(srt_path).replace("\\", "/").replace(":", "\\:")
    cmd = [
        FFMPEG, "-y",
        "-i", str(concat_path),
        "-vf",
        f"subtitles='{srt_escaped}':force_style='FontName=SimHei,FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=2,Shadow=1,MarginV=40'",
        "-c:v", "libx264",
        "-preset", "fast",
        "-crf", "23",
        "-c:a", "copy",
        "-pix_fmt", "yuv420p",
        str(output_path),
    ]
    print("  Burning subtitles...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  Subtitle burn warning: {result.stderr[-500:]}")
        # 如果字幕烧录失败，直接复制无字幕版本
        shutil.copy2(str(concat_path), str(output_path))

    print(f"\n  Video saved: {output_path}")
    return output_path


async def main():
    print("=" * 60)
    print("课程达成度评价系统 — 操作指南视频生成器")
    print("=" * 60)

    # 准备目录
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    tts_dir = TEMP_DIR / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)

    # 1) 生成 TTS 音频
    print("\n[1/4] 生成语音音频 (edge-tts)...")
    audio_files = await generate_tts(SEGMENTS, tts_dir)

    # 2) 获取各段音频时长
    print("\n[2/4] 分析音频时长...")
    audio_durations = []
    for af in audio_files:
        dur = get_audio_duration(af)
        audio_durations.append(dur)
        print(f"  {af.name}: {dur:.2f}s")

    total_duration = sum(d + s[2] for d, s in zip(audio_durations, SEGMENTS))
    print(f"  Total duration: {total_duration:.1f}s ({total_duration/60:.1f}min)")

    # 3) 生成字幕
    print("\n[3/4] 生成字幕文件...")
    final_srt = OUTPUT_DIR / "subtitles.srt"
    create_subtitle_srt(SEGMENTS, audio_durations, final_srt)
    print(f"  Subtitles: {final_srt}")

    # 4) 合成视频
    print("\n[4/4] 合成视频 (ffmpeg)...")
    output_mp4 = OUTPUT_DIR / "achievement_guide.mp4"
    generate_video_with_ffmpeg(SEGMENTS, audio_files, audio_durations, final_srt, output_mp4)

    print("\n" + "=" * 60)
    print(f"Done! Output: {output_mp4}")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
