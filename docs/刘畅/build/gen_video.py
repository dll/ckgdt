# -*- coding: utf-8 -*-
"""答辩视频合成: slide PNG + 男声配音 + 烧录中文字幕 -> 最终mp4，并导出srt。
运行: python gen_video.py
依赖: ffmpeg/ffprobe (PATH), slides/*.png, audio/*.mp3, slides_data.SLIDES
"""
import os, subprocess, re
from slides_data import SLIDES, TITLE

HERE = os.path.dirname(os.path.abspath(__file__))
SL = os.path.join(HERE, "slides")
AUD = os.path.join(HERE, "audio")
VID = os.path.join(HERE, "video")
os.makedirs(VID, exist_ok=True)

def dur(mp3):
    out = subprocess.check_output([
        "ffprobe","-v","error","-show_entries","format=duration",
        "-of","default=noprint_wrappers=1:nokey=1", mp3]).decode().strip()
    return float(out)

def split_subs(text, dur_s, maxlen=22):
    parts = [p.strip() for p in re.split(r"(?<=[。；！？，])", text) if p.strip()]
    merged=[]; cur=""
    for p in parts:
        if len(cur)+len(p) <= maxlen: cur += p
        else:
            if cur: merged.append(cur)
            cur = p
    if cur: merged.append(cur)
    total = sum(len(x) for x in merged) or 1
    subs=[]; t=0.0
    for m in merged:
        seg = dur_s*len(m)/total
        subs.append((t, t+seg, m.rstrip("，")))
        t += seg
    if subs: subs[-1]=(subs[-1][0], dur_s, subs[-1][2])
    return subs

def fmt_srt(t):
    h=int(t//3600); m=int(t%3600//60); s=int(t%60); ms=int(round((t-int(t))*1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

def fmt_ass(t):
    h=int(t//3600); m=int(t%3600//60); s=int(t%60); cs=int(round((t-int(t))*100))
    return f"{h:d}:{m:02d}:{s:02d}.{cs:02d}"

def ass_escape(s):
    return s.replace("{","(").replace("}",")")

srt_lines=[]; srt_idx=1; t_off=0.0; clip_list=[]
for i, s in enumerate(SLIDES, 1):
    png = os.path.join(SL, f"slide_{i:02d}.png")
    mp3 = os.path.join(AUD, f"seg_{i:02d}.mp3")
    d = dur(mp3)
    subs = split_subs(s["note"], d)
    ass = os.path.join(VID, f"sub_{i:02d}.ass")
    with open(ass,"w",encoding="utf-8") as f:
        f.write("[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\n\n")
        f.write("[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, "
                "OutlineColour, BackColour, Bold, BorderStyle, Outline, Shadow, "
                "Alignment, MarginL, MarginR, MarginV\n")
        f.write("Style: Def,Microsoft YaHei,46,&H00FFFFFF,&H00401B0A,&H96000000,"
                "1,3,3,1,2,170,170,72\n\n")
        f.write("[Events]\nFormat: Layer, Start, End, Style, Text\n")
        for a,b,line in subs:
            f.write(f"Dialogue: 0,{fmt_ass(a)},{fmt_ass(b)},Def,,{ass_escape(line)}\n")
    for a,b,line in subs:
        srt_lines.append(f"{srt_idx}\n{fmt_srt(t_off+a)} --> {fmt_srt(t_off+b)}\n{line}\n")
        srt_idx+=1
    t_off += d
    clip = os.path.join(VID, f"clip_{i:02d}.mp4")
    assfilter = ass.replace("\\","/").replace(":","\\:")
    subprocess.run([
        "ffmpeg","-y","-loop","1","-i",png,"-i",mp3,
        "-vf",f"ass='{assfilter}'",
        "-c:v","libx264","-tune","stillimage","-pix_fmt","yuv420p",
        "-c:a","aac","-b:a","192k","-r","25","-shortest","-t",f"{d:.3f}", clip],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    clip_list.append(clip)
    print(f"clip_{i:02d} ok  dur={d:.1f}s subs={len(subs)}")

concat = os.path.join(VID,"concat.txt")
with open(concat,"w",encoding="utf-8") as f:
    for c in clip_list:
        f.write("file '%s'\n" % c.replace("\\","/"))
out_mp4 = os.path.join(HERE,"..","面向异构飞行器协同作战的编队策略研究_答辩视频.mp4")
subprocess.run(["ffmpeg","-y","-f","concat","-safe","0","-i",concat,"-c","copy",out_mp4],
    check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
srt_out = os.path.join(HERE,"..","面向异构飞行器协同作战的编队策略研究_字幕.srt")
open(srt_out,"w",encoding="utf-8").write("\n".join(srt_lines))
print("VIDEO ->", out_mp4)
print("SRT   ->", srt_out, "total", round(t_off,1),"s")
