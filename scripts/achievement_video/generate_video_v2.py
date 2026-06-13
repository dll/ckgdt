#!/usr/bin/env python3
"""
课程达成度评价系统操作指南视频生成器 v2
核心改进：语音-字幕严格同步（1段 = 1音频 = 1字幕），字幕在底部
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

FFMPEG = r"D:\development\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
FFPROBE = r"D:\development\ffmpeg-8.0.1-full_build\bin\ffprobe.exe"

VIDEO_W, VIDEO_H = 1920, 1080
FPS = 24

TTS_VOICE = "zh-CN-YunxiNeural"
TTS_RATE = "+0%"

# ============================================================
# 严格按 8 个 Tab 顺序编排的片段
# (截图文件名, 旁白文字, 额外静默秒数)
# ============================================================
SEGMENTS = [
    # ── 开场 ──
    (
        "01达成度概览.png",
        "课程达成度评价系统操作指南。本视频将按八个功能模块，依次演示完整操作流程。",
        1.0,
    ),

    # ── Tab 1: 达成度概览 ──
    (
        "01达成度概览.png",
        "首先，进入第一个模块，达成度概览。页面上方显示所有已创建的评价批次，包含课程名称、班级、学期和学生人数。",
        0.5,
    ),
    (
        "01达成度概览-上传大纲.png",
        "首次使用，需要上传课程大纲。点击右下角加号按钮，选择上传课程大纲。系统通过人工智能自动解析大纲内容，提取课程目标、权重和毕业要求指标点。大纲数据按课程名存储，不同课程的大纲互相独立。",
        1.0,
    ),
    (
        "01达成度概览.png",
        "同样在概览页面，点击加号按钮，选择新建批次。填写批次名称、课程名称、班级和学期信息，即可创建新的评价批次。",
        0.5,
    ),

    # ── Tab 2: 成绩管理 ──
    (
        "02成绩管理.png",
        "接下来，进入第二个模块，成绩管理。这里支持三种成绩录入方式：下载模板、导入成绩Excel、手动添加成绩。",
        0.5,
    ),
    (
        "02成绩管理-导下载模板.png",
        "推荐方式是先下载模板。系统自动生成包含目标拆分表头的Excel模板，模板分为三个工作表：平时成绩、实验成绩和期末成绩。",
        0.5,
    ),
    (
        "02成绩管理-导入成绩.png",
        "在Excel中填写学生成绩后，回到系统点击导入成绩Excel。系统自动校验数据，检查异常分值、重复学号和缺失学生。确认无误后点击确认导入。成绩导入后系统自动计算并合成达成度。",
        1.0,
    ),

    # ── Tab 3: 计算过程 ──
    (
        "03计算过程.png",
        "第三个模块，计算过程。页面展示大纲课程目标和考核方式。平时成绩占百分之二十，实验成绩占百分之三十，期末成绩占百分之五十。",
        0.5,
    ),
    (
        "03计算过程-计算达成度.png",
        "点击计算达成度按钮，系统自动完成所有计算。结果以可视化图表展示，包括四个目标的达成度柱状图。总体达成度为百分之七十七点四，达成等级为良好。下方还展示每位学生的个体达成度明细。",
        1.0,
    ),

    # ── Tab 4: 平时达成 ──
    (
        "04平时达成.png",
        "第四个模块，平时达成。页面左侧展示平时成绩评价结构：课堂表现对应目标一，期间测验对应目标二，课外学习对应目标四。右侧展示班级平均指标点达成度雷达图，下方是每位学生的平时成绩明细。",
        0.5,
    ),

    # ── Tab 5: 实验达成 ──
    (
        "05实验达成.png",
        "第五个模块，实验达成。实验一和实验二对应目标一，实验三和实验四对应目标二，实验五和实验六对应目标三，实验七对应目标四。系统自动计算每位学生的实验达成度。",
        0.5,
    ),

    # ── Tab 6: 考核达成 ──
    (
        "06考核达成.png",
        "第六个模块，考核达成。期末考核包含四个部分：项目对应目标一，小组对应目标二，个人对应目标三，答辩对应目标四。每个环节都提供班级平均指标点达成度雷达图，方便对比分析。",
        0.5,
    ),

    # ── Tab 7: 持续改进 ──
    (
        "07持续改进.png",
        "第七个模块，持续改进。系统自动分析达成度数据，生成改进建议。页面展示上轮教学改进措施的执行情况，以及针对每个未达标目标的具体改进建议。",
        0.5,
    ),

    # ── Tab 8: 报告生成 ──
    (
        "08生成报告.png",
        "最后一个模块，报告生成。系统支持三种导出格式：Markdown预览、Word导出和Excel导出。",
        0.5,
    ),
    (
        "08生成报告-md格式预览.png",
        "Markdown格式支持在线预览完整报告内容，方便教师快速查看。",
        0.5,
    ),
    (
        "08生成报告-word格式导出.png",
        "Word导出生成符合学校规范格式的评价报告，包含基本信息、考核标准、达成度计算和结果分析四个部分。",
        0.5,
    ),
    (
        "08生成报告-excel格式导出.png",
        "Excel导出包含五个工作表，涵盖平时、实验、期末成绩和达成度汇总，支持图表展示。导出的文件可通过提示直接打开查看。",
        1.0,
    ),

    # ── 结尾 ──
    (
        "08生成报告.png",
        "课程达成度评价系统，让教学评价更加科学、高效、便捷。感谢观看。",
        0.0,
    ),
]


# ============================================================
# 工具函数
# ============================================================

def get_audio_duration(audio_path: str) -> float:
    """用 ffprobe 获取音频时长"""
    cmd = [
        FFPROBE, "-v", "quiet",
        "-print_format", "json",
        "-show_format", str(audio_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    info = json.loads(result.stdout)
    return float(info["format"]["duration"])


async def generate_tts(segments: list, output_dir: Path):
    """逐段生成 TTS 音频"""
    import edge_tts

    audio_files = []
    for i, (_, text, _) in enumerate(segments):
        out_file = output_dir / f"tts_{i:03d}.mp3"
        communicate = edge_tts.Communicate(text, TTS_VOICE, rate=TTS_RATE)
        await communicate.save(str(out_file))
        audio_files.append(out_file)
        print(f"  TTS {i+1}/{len(segments)}: {out_file.name}")
    return audio_files


def format_srt_time(seconds: float) -> str:
    """秒数 -> SRT 时间戳  00:01:23,456"""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int((seconds % 1) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def build_srt(segments, audio_durations, output_path):
    """
    严格同步字幕：
    - 每段字幕的起止时间 = 该段音频的实际起止时间
    - 字幕文本 = 该段旁白原文（完整，不拆分）
    """
    lines = []
    current = 0.0
    for i, (_, text, extra) in enumerate(segments):
        dur = audio_durations[i] + extra
        start = format_srt_time(current)
        end = format_srt_time(current + dur)
        lines.append(f"{i + 1}")
        lines.append(f"{start} --> {end}")
        lines.append(text)
        lines.append("")
        current += dur

    Path(output_path).write_text("\n".join(lines), encoding="utf-8")
    return output_path


def make_clips(segments, audio_files, audio_durations, temp_dir):
    """为每段生成带 Ken Burns 效果的视频片段"""
    clip_files = []
    for i, (img_name, _, extra) in enumerate(segments):
        img_path = SCREENSHOT_DIR / img_name
        audio_path = audio_files[i]
        dur = audio_durations[i] + extra
        clip_path = temp_dir / f"clip_{i:03d}.mp4"
        clip_files.append(clip_path)

        total_frames = int(dur * FPS)
        # Ken Burns：从 1.0 缓慢缩放到 1.06，画面中心
        cmd = [
            FFMPEG, "-y",
            "-loop", "1", "-i", str(img_path),
            "-i", str(audio_path),
            "-filter_complex",
            (
                f"[0:v]scale={VIDEO_W}:{VIDEO_H}:force_original_aspect_ratio=decrease,"
                f"pad={VIDEO_W}:{VIDEO_H}:(ow-iw)/2:(oh-ih)/2:color=black,"
                f"zoompan=z='min(zoom+0.00025,1.06)'"
                f":x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
                f":d={total_frames}:s={VIDEO_W}x{VIDEO_H}:fps={FPS}[v]"
            ),
            "-map", "[v]", "-map", "1:a",
            "-c:v", "libx264", "-preset", "fast", "-crf", "23",
            "-c:a", "aac", "-b:a", "128k",
            "-t", str(dur),
            "-pix_fmt", "yuv420p",
            str(clip_path),
        ]
        print(f"  Clip {i+1}/{len(segments)}: {img_name} ({dur:.1f}s)")
        subprocess.run(cmd, capture_output=True, text=True, check=True)

    return clip_files


def concat_clips(clip_files, temp_dir):
    """拼接所有片段"""
    concat_list = temp_dir / "concat.txt"
    concat_list.write_text(
        "\n".join(f"file '{c}'" for c in clip_files), encoding="utf-8"
    )
    concat_out = temp_dir / "concat_raw.mp4"
    cmd = [
        FFMPEG, "-y",
        "-f", "concat", "-safe", "0",
        "-i", str(concat_list),
        "-c:v", "libx264", "-preset", "fast", "-crf", "23",
        "-c:a", "aac", "-b:a", "128k",
        "-pix_fmt", "yuv420p",
        str(concat_out),
    ]
    print("  Concatenating clips...")
    subprocess.run(cmd, capture_output=True, text=True, check=True)
    return concat_out


def burn_subtitles(concat_path, srt_path, output_path):
    """
    烧录字幕到视频底部
    MarginV 控制距底部的距离
    """
    srt_escaped = str(srt_path).replace("\\", "/").replace(":", "\\:")

    # 字幕样式：底部居中、白色、黑色描边、SimHei 字体
    style = (
        "FontName=SimHei,"
        "FontSize=20,"
        "PrimaryColour=&H00FFFFFF,"    # 白色
        "OutlineColour=&H00000000,"    # 黑色描边
        "BackColour=&H80000000,"       # 半透明黑底
        "Bold=1,"
        "Outline=2,"
        "Shadow=1,"
        "MarginV=30,"                  # 距底部 30px
        "Alignment=2"                  # 底部居中
    )

    cmd = [
        FFMPEG, "-y",
        "-i", str(concat_path),
        "-vf", f"subtitles='{srt_escaped}':force_style='{style}'",
        "-c:v", "libx264", "-preset", "fast", "-crf", "23",
        "-c:a", "copy",
        "-pix_fmt", "yuv420p",
        str(output_path),
    ]
    print("  Burning subtitles...")
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        print(f"  Subtitle burn failed, using raw video. Error: {result.stderr[-300:]}")
        shutil.copy2(str(concat_path), str(output_path))

    return output_path


# ============================================================
# 主流程
# ============================================================

async def main():
    print("=" * 60)
    print("课程达成度评价系统 — 操作指南视频生成器 v2")
    print("  语音-字幕严格同步 | 字幕底部 | 8 Tab 顺序")
    print("=" * 60)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    tts_dir = TEMP_DIR / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)
    clips_dir = TEMP_DIR / "clips"
    clips_dir.mkdir(parents=True, exist_ok=True)

    # 1) 生成 TTS
    print(f"\n[1/5] 生成语音 ({len(SEGMENTS)} 段)...")
    audio_files = await generate_tts(SEGMENTS, tts_dir)

    # 2) 获取时长
    print("\n[2/5] 获取音频时长...")
    durations = []
    for af in audio_files:
        d = get_audio_duration(af)
        durations.append(d)
    total = sum(d + s[2] for d, s in zip(durations, SEGMENTS))
    print(f"  Total: {total:.1f}s ({total/60:.1f} min)")

    # 3) 生成字幕
    print("\n[3/5] 生成同步字幕...")
    srt_path = OUTPUT_DIR / "subtitles.srt"
    build_srt(SEGMENTS, durations, srt_path)
    print(f"  SRT: {srt_path}")

    # 4) 合成片段 + 拼接
    print("\n[4/5] 合成视频片段...")
    clips = make_clips(SEGMENTS, audio_files, durations, clips_dir)
    concat = concat_clips(clips, clips_dir)

    # 5) 烧录字幕
    print("\n[5/5] 烧录底部字幕...")
    final = OUTPUT_DIR / "achievement_guide_v2.mp4"
    burn_subtitles(concat, srt_path, final)

    print("\n" + "=" * 60)
    print(f"完成！输出: {final}")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
