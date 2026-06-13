# -*- coding: utf-8 -*-
"""男声配音生成: 每页讲稿 -> audio/seg_NN.mp3 (edge-tts)。
运行: python gen_tts.py   导入 slides_data.SLIDES
"""
import os, asyncio, edge_tts
from slides_data import SLIDES

HERE = os.path.dirname(os.path.abspath(__file__))
AUD = os.path.join(HERE, "audio")
os.makedirs(AUD, exist_ok=True)

VOICE = "zh-CN-YunyangNeural"   # 男声·沉稳新闻播报,贴合军事答辩
RATE = "+6%"
PITCH = "-2Hz"

async def one(i, text):
    out = os.path.join(AUD, f"seg_{i:02d}.mp3")
    c = edge_tts.Communicate(text, VOICE, rate=RATE, pitch=PITCH)
    await c.save(out)
    return out

async def main():
    for i, s in enumerate(SLIDES, 1):
        await one(i, s["note"])
        print(f"tts seg_{i:02d} ok ({len(s['note'])} chars)")

if __name__ == "__main__":
    asyncio.run(main())
    print("all TTS done ->", AUD)
