#!/usr/bin/env python3
"""
课程达成度评价系统操作指南视频生成器。

目标：
- 严格按 8 个达成功能菜单讲解，不混淆步骤。
- 使用 assets/help/archievement 中的截图，按文件名含义解释。
- edge-tts 男声旁白，使用 SentenceBoundary 生成逐句同步字幕。
- 字幕烧录到底部，最终 MP4 输出到 data/视频，不打包进 assets。
- 中间文件全部保存在 scripts/achievement_video/work/<timestamp>/。
"""

from __future__ import annotations

import asyncio
import json
import math
import shutil
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

import edge_tts
from PIL import Image, ImageDraw


BASE_DIR = Path(__file__).resolve().parent
REPO_DIR = BASE_DIR.parent.parent
SCREENSHOT_DIR = REPO_DIR / "assets" / "help" / "archievement"
DATA_VIDEO_DIR = REPO_DIR / "data" / "视频"
WORK_ROOT = BASE_DIR / "work"

FFMPEG = Path(r"D:\development\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe")
FFPROBE = Path(r"D:\development\ffmpeg-8.0.1-full_build\bin\ffprobe.exe")

VIDEO_W = 1920
VIDEO_H = 1080
FPS = 24
VOICE = "zh-CN-YunxiNeural"  # 男声
TTS_RATE = "+8%"
FINAL_NAME = "达成度评价系统操作指南.mp4"


@dataclass(frozen=True)
class Segment:
    image: str
    menu: str
    narration: str
    extra_silence: float = 0.25
    highlight: tuple[int, int, int, int] | None = None
    cursor_from: tuple[int, int] = (320, 180)
    cursor_to: tuple[int, int] = (1540, 780)


SEGMENTS: list[Segment] = [
    Segment(
        "01达成度概览.png",
        "01 达成度概览",
        "这是课程达成度评价系统操作指南。请按八个菜单依次完成，先导入大纲，再导入成绩，最后生成达成度评价报告。",
        0.35,
        (26, 92, 290, 56),
        (180, 120),
        (520, 155),
    ),
    Segment(
        "01达成度概览-上传大纲.png",
        "01 达成度概览",
        "第一步，在达成度概览中上传课程大纲。系统解析课程目标、权重和毕业要求指标点，后续所有计算都以这份大纲为准。",
        0.35,
        (1320, 725, 350, 170),
        (1510, 840),
        (1435, 770),
    ),
    Segment(
        "01达成度概览.png",
        "01 达成度概览",
        "大纲确认后，在概览页新建评价批次。填写课程名称、班级和学期，一个批次对应一个班级的一轮达成度评价。",
        0.2,
        (1170, 710, 480, 190),
        (1500, 820),
        (1370, 760),
    ),
    Segment(
        "02成绩管理.png",
        "02 成绩管理",
        "第二个菜单是成绩管理。这里不要直接计算达成度，先选择批次，再准备平时、实验和期末三类成绩。",
        0.2,
        (40, 135, 600, 110),
        (230, 160),
        (500, 190),
    ),
    Segment(
        "02成绩管理-导下载模板.png",
        "02 成绩管理",
        "先点击下载模板。模板会按课程目标生成表头，包含平时成绩、实验成绩和期末成绩三个工作表。",
        0.2,
        (1280, 136, 190, 50),
        (1380, 170),
        (1395, 157),
    ),
    Segment(
        "02成绩管理-导入成绩.png",
        "02 成绩管理",
        "填写模板后，再导入成绩 Excel。系统会校验学号、姓名、分值范围和重复数据，确认后写入当前批次。",
        0.25,
        (1480, 136, 210, 50),
        (1550, 170),
        (1575, 158),
    ),
    Segment(
        "03计算过程.png",
        "03 计算过程",
        "第三个菜单是计算过程。这里核对大纲目标、考核环节和权重关系，确认平时、实验、期末分项没有错位。",
        0.2,
        (30, 170, 560, 210),
        (260, 210),
        (520, 325),
    ),
    Segment(
        "03计算过程-计算达成度.png",
        "03 计算过程",
        "点击计算达成度。系统计算每个课程目标的班级达成度、总体达成度和学生个体明细，并用图表展示结果。",
        0.25,
        (1180, 132, 220, 54),
        (1280, 166),
        (1286, 150),
    ),
    Segment(
        "04平时达成.png",
        "04 平时达成",
        "第四个菜单是平时达成。重点查看课堂表现、期间测验和课外学习对目标一、目标二、目标四的支撑情况。",
        0.2,
        (24, 160, 620, 255),
        (300, 235),
        (500, 340),
    ),
    Segment(
        "05实验达成.png",
        "05 实验达成",
        "第五个菜单是实验达成。系统按实验一到实验七归集目标得分，检查目标三和目标四是否被实验环节充分支撑。",
        0.2,
        (24, 160, 640, 275),
        (300, 240),
        (520, 360),
    ),
    Segment(
        "06考核达成.png",
        "06 考核达成",
        "第六个菜单是考核达成。项目、小组、个人和答辩分别对应不同课程目标，用于核对期末综合考核结果。",
        0.2,
        (24, 160, 630, 255),
        (290, 232),
        (520, 348),
    ),
    Segment(
        "07持续改进.png",
        "07 持续改进",
        "第七个菜单是持续改进。系统根据未达成目标和薄弱环节生成改进建议，用于下一轮教学闭环。",
        0.2,
        (23, 145, 720, 260),
        (280, 220),
        (620, 360),
    ),
    Segment(
        "08生成报告.png",
        "08 报告生成",
        "最后进入报告生成菜单。先选择已完成计算的批次，再生成达成度评价报告，不要跳过前面的数据校验。",
        0.2,
        (28, 135, 610, 120),
        (250, 165),
        (560, 190),
    ),
    Segment(
        "08生成报告-md格式预览.png",
        "08 报告生成",
        "Markdown 预览用于快速检查报告正文。确认基本信息、达成度表格和改进建议无误后，再导出正式文件。",
        0.15,
        (980, 132, 230, 55),
        (1070, 160),
        (1095, 150),
    ),
    Segment(
        "08生成报告-word格式导出.png",
        "08 报告生成",
        "Word 导出生成学校归档用的课程目标达成评价报告，包含基本信息、考核标准、达成度计算和结果分析。",
        0.15,
        (1210, 132, 220, 55),
        (1295, 160),
        (1318, 150),
    ),
    Segment(
        "08生成报告-excel格式导出.png",
        "08 报告生成",
        "Excel 导出生成评价表格和明细数据，便于复核平时、实验、期末成绩与课程目标达成度。",
        0.15,
        (1430, 132, 230, 55),
        (1510, 160),
        (1540, 150),
    ),
    Segment(
        "08生成报告-pdf格式导出.png",
        "08 报告生成",
        "如需直接分发或打印，可以导出 PDF。到这里，完整流程从大纲、成绩、计算到评价报告已经完成。",
        0.3,
        (1660, 132, 210, 55),
        (1730, 160),
        (1760, 150),
    ),
]


def check_environment() -> None:
    missing = []
    for tool in [FFMPEG, FFPROBE]:
        if not tool.exists():
            missing.append(str(tool))
    for segment in SEGMENTS:
        if not (SCREENSHOT_DIR / segment.image).exists():
            missing.append(str(SCREENSHOT_DIR / segment.image))
    if missing:
        raise FileNotFoundError("缺少必要文件:\n" + "\n".join(missing))


def make_cursor(path: Path) -> None:
    img = Image.new("RGBA", (72, 72), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    pts = [(8, 5), (8, 58), (22, 45), (31, 68), (42, 64), (33, 42), (52, 42)]
    draw.polygon(pts, fill=(255, 255, 255, 245), outline=(0, 0, 0, 230))
    draw.line([(22, 45), (33, 42)], fill=(0, 0, 0, 230), width=2)
    draw.ellipse((2, 2, 64, 64), outline=(248, 195, 58, 160), width=4)
    img.save(path)


async def synthesize_segment(text: str, out_file: Path) -> list[dict]:
    boundaries = []
    communicate = edge_tts.Communicate(text, VOICE, rate=TTS_RATE)
    with out_file.open("wb") as f:
        async for chunk in communicate.stream():
            kind = chunk["type"]
            if kind == "audio":
                f.write(chunk["data"])
            elif kind == "SentenceBoundary":
                boundaries.append(
                    {
                        "offset": chunk["offset"] / 10_000_000,
                        "duration": chunk["duration"] / 10_000_000,
                        "text": chunk["text"],
                    }
                )
    return boundaries


def probe_duration(path: Path) -> float:
    result = subprocess.run(
        [
            str(FFPROBE),
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            str(path),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
    )
    return float(json.loads(result.stdout)["format"]["duration"])


def srt_time(seconds: float) -> str:
    if seconds < 0:
        seconds = 0
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - math.floor(seconds)) * 1000))
    if ms == 1000:
        s += 1
        ms = 0
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def wrap_cn(text: str, width: int = 26) -> str:
    text = text.strip()
    if len(text) <= width:
        return text
    lines = []
    while text:
        lines.append(text[:width])
        text = text[width:]
    return "\n".join(lines[:2])


def build_srt(
    segments: list[Segment],
    boundary_map: list[list[dict]],
    audio_durations: list[float],
    out_path: Path,
) -> None:
    lines = []
    index = 1
    cursor = 0.0
    for seg, boundaries, audio_dur in zip(segments, boundary_map, audio_durations):
        if not boundaries:
            # 兜底：无边界时整段字幕覆盖实际音频时长。
            boundaries = [
                {"offset": 0.0, "duration": audio_dur, "text": seg.narration}
            ]
        prev_end = cursor
        for i, item in enumerate(boundaries):
            start = cursor + float(item["offset"])
            start = max(start, prev_end + 0.02)
            end = start + max(float(item["duration"]), 0.8)
            if i + 1 < len(boundaries):
                next_start = cursor + float(boundaries[i + 1]["offset"])
                end = min(end, next_start - 0.03)
            end = min(end, cursor + audio_dur)
            if end <= start:
                continue
            lines.extend(
                [
                    str(index),
                    f"{srt_time(start)} --> {srt_time(end)}",
                    wrap_cn(str(item["text"])),
                    "",
                ]
            )
            index += 1
            prev_end = end
        cursor += audio_dur + seg.extra_silence
    out_path.write_text("\n".join(lines), encoding="utf-8")


def concat_text(paths: Iterable[Path], out_path: Path) -> None:
    out_path.write_text(
        "\n".join(f"file '{p.as_posix()}'" for p in paths), encoding="utf-8"
    )


def make_clip(
    seg: Segment,
    audio: Path,
    audio_duration: float,
    cursor_img: Path,
    out_path: Path,
) -> None:
    duration = audio_duration + seg.extra_silence
    total_frames = max(1, int(duration * FPS))
    hx, hy, hw, hh = seg.highlight or (0, 0, 0, 0)
    sx, sy = seg.cursor_from
    ex, ey = seg.cursor_to
    menu_text = seg.menu.replace("'", "\\'")

    filters = [
        (
            f"[0:v]scale={VIDEO_W}:{VIDEO_H}:force_original_aspect_ratio=decrease,"
            f"pad={VIDEO_W}:{VIDEO_H}:(ow-iw)/2:(oh-ih)/2:color=0x10131a,"
            f"zoompan=z='min(1.035,1+0.00012*on)'"
            f":x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
            f":d={total_frames}:s={VIDEO_W}x{VIDEO_H}:fps={FPS},"
            f"drawbox=x=0:y=0:w=iw:h=58:color=black@0.38:t=fill,"
            f"drawtext=font='Microsoft YaHei':text='{menu_text}':"
            f"x=36:y=16:fontsize=25:fontcolor=white:box=1:"
            f"boxcolor=black@0.35:boxborderw=8,"
            f"drawbox=x={hx}:y={hy + 30}:w={hw}:h={hh}:color=0xF8C33A@0.48:t=6"
            f"[base]"
        ),
        "[2:v]format=rgba,scale=46:46[cursor]",
        (
            f"[base][cursor]overlay="
            f"x='{sx}+({ex - sx})*t/{duration:.3f}':"
            f"y='{sy}+({ey - sy})*t/{duration:.3f}'[v]"
        ),
        f"[1:a]apad=pad_dur={seg.extra_silence:.3f}[a]",
    ]
    cmd = [
        str(FFMPEG),
        "-y",
        "-loop",
        "1",
        "-i",
        str(SCREENSHOT_DIR / seg.image),
        "-i",
        str(audio),
        "-loop",
        "1",
        "-i",
        str(cursor_img),
        "-filter_complex",
        ";".join(filters),
        "-map",
        "[v]",
        "-map",
        "[a]",
        "-t",
        f"{duration:.3f}",
        "-c:v",
        "libx264",
        "-preset",
        "fast",
        "-crf",
        "20",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-pix_fmt",
        "yuv420p",
        str(out_path),
    ]
    subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)


def concat_clips(clips: list[Path], concat_file: Path, out_path: Path) -> None:
    concat_text(clips, concat_file)
    subprocess.run(
        [
            str(FFMPEG),
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_file),
            "-c:v",
            "libx264",
            "-preset",
            "fast",
            "-crf",
            "20",
            "-c:a",
            "aac",
            "-b:a",
            "128k",
            "-pix_fmt",
            "yuv420p",
            str(out_path),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
    )


def burn_subtitles(video: Path, srt: Path, out_path: Path) -> None:
    escaped = srt.as_posix().replace(":", r"\:")
    style = (
        "FontName=Microsoft YaHei,"
        "FontSize=14,"
        "PrimaryColour=&H00FFFFFF,"
        "OutlineColour=&H00000000,"
        "BackColour=&H90000000,"
        "Bold=1,"
        "Outline=1,"
        "Shadow=1,"
        "MarginV=20,"
        "Alignment=2"
    )
    cmd = [
        str(FFMPEG),
        "-y",
        "-i",
        str(video),
        "-vf",
        f"subtitles='{escaped}':force_style='{style}'",
        "-c:v",
        "libx264",
        "-preset",
        "slow",
        "-crf",
        "28",
        "-c:a",
        "copy",
        "-pix_fmt",
        "yuv420p",
        str(out_path),
    ]
    subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)


async def main() -> None:
    check_environment()
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    work_dir = WORK_ROOT / f"achievement_guide_{stamp}"
    tts_dir = work_dir / "tts"
    clips_dir = work_dir / "clips"
    output_dir = work_dir / "output"
    for path in [tts_dir, clips_dir, output_dir, DATA_VIDEO_DIR]:
        path.mkdir(parents=True, exist_ok=True)

    cursor_img = work_dir / "cursor.png"
    make_cursor(cursor_img)

    (work_dir / "segments.json").write_text(
        json.dumps([asdict(s) for s in SEGMENTS], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print("=" * 72)
    print("课程达成度评价系统操作指南 - 高同步视频生成")
    print(f"工作目录: {work_dir}")
    print("=" * 72)

    audio_files: list[Path] = []
    boundary_map: list[list[dict]] = []
    durations: list[float] = []
    for i, seg in enumerate(SEGMENTS):
        audio = tts_dir / f"{i + 1:02d}_{Path(seg.image).stem}.mp3"
        print(f"[TTS {i + 1:02d}/{len(SEGMENTS)}] {seg.menu} - {seg.image}")
        boundaries = await synthesize_segment(seg.narration, audio)
        duration = probe_duration(audio)
        audio_files.append(audio)
        boundary_map.append(boundaries)
        durations.append(duration)

    total = sum(d + s.extra_silence for d, s in zip(durations, SEGMENTS))
    print(f"预计总时长: {total:.1f}s / {total / 60:.2f} min")
    if total > 240:
        print("警告: 视频超过 4 分钟，请缩短旁白文本。")

    srt_path = output_dir / "achievement_guide.srt"
    build_srt(SEGMENTS, boundary_map, durations, srt_path)

    clips: list[Path] = []
    for i, (seg, audio, duration) in enumerate(zip(SEGMENTS, audio_files, durations)):
        clip = clips_dir / f"clip_{i + 1:02d}_{Path(seg.image).stem}.mp4"
        print(f"[CLIP {i + 1:02d}/{len(SEGMENTS)}] {clip.name}")
        make_clip(seg, audio, duration, cursor_img, clip)
        clips.append(clip)

    concat_raw = output_dir / "achievement_guide_raw.mp4"
    concat_list = output_dir / "concat.txt"
    print("[MERGE] 拼接视频片段")
    concat_clips(clips, concat_list, concat_raw)

    final_work = output_dir / FINAL_NAME
    print("[SUBTITLE] 烧录底部同步字幕")
    burn_subtitles(concat_raw, srt_path, final_work)

    final_data = DATA_VIDEO_DIR / FINAL_NAME
    shutil.copy2(final_work, final_data)
    print("=" * 72)
    print(f"完成: {final_data}")
    print(f"中间文件已保存: {work_dir}")
    print("=" * 72)


if __name__ == "__main__":
    asyncio.run(main())
