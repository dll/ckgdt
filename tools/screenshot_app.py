#!/usr/bin/env python3
"""Capture Flutter app window screenshots."""
import os
import subprocess
import time
from pathlib import Path

try:
    import mss
    import mss.tools
except ImportError:
    mss = None

try:
    from PIL import ImageGrab
except ImportError:
    ImageGrab = None

OUT_DIR = Path(__file__).resolve().parent.parent / "docs" / "video" / "demo" / "screenshots"


def capture_fullscreen(name, delay=0.5):
    """Capture full screen and save."""
    time.sleep(delay)
    if mss:
        with mss.mss() as sct:
            monitor = sct.monitors[1]
            sct_img = sct.grab(monitor)
            out = OUT_DIR / name
            mss.tools.to_png(sct_img.rgb, sct_img.size, output=str(out))
            print(f"  Saved: {out}  ({sct_img.size[0]}x{sct_img.size[1]})")
            return out
    elif ImageGrab:
        img = ImageGrab.grab()
        out = OUT_DIR / name
        img.save(out, "PNG")
        print(f"  Saved: {out}  ({img.size[0]}x{img.size[1]})")
        return out
    else:
        print("  No screenshot library available")
        return None


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Wait for app to be ready
    print("Waiting for app...")
    time.sleep(3)

    screenshots = [
        ("01_login.png", "Login page"),
        ("02_home.png", "Home page after login"),
        ("03_graph_list.png", "Knowledge graph list"),
        ("04_graph_detail.png", "Graph detail with nodes"),
        ("05_agent_overlay.png", "Agent chat overlay"),
        ("06_digital_twin.png", "Digital twin student view"),
        ("07_classroom.png", "Teacher classroom dashboard"),
        ("08_obe_achievement.png", "OBE achievement page"),
    ]

    for name, desc in screenshots:
        print(f"\n[{desc}]")
        capture_fullscreen(name, delay=0.5)

    print("\nDone! Screenshots saved to:", OUT_DIR)


if __name__ == "__main__":
    main()
