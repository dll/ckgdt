#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
归档模板反向转换：把 data/CKGDT/归档/<期>/模板/*.md 转成 .docx
供 pandoc 转 PDF 时作为 reference-doc 继承样式。

用法：
    python tools/convert_ckgdt_templates.py            # 全转
    python tools/convert_ckgdt_templates.py 期初       # 只转某期

依赖：pandoc（项目已装：3.6.3）
"""

import os
import subprocess
import sys
from pathlib import Path

# Windows 终端默认 GBK，把 stdout 强转 UTF-8 防止 emoji 爆码
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SRC_ROOT = ROOT / "data" / "CKGDT" / "归档"

# 期间名 → 英文 key（与 archive_constants.dart 对齐）
PERIOD_MAP = {
    "期初": "beginning",
    "期中": "midterm",
    "期末": "final",
    "结课": "archive",
}


def md_to_docx(src: Path, dst: Path) -> bool:
    """pandoc markdown → docx。失败返回 False。"""
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            ["pandoc", str(src),
             "-f", "markdown",
             "-t", "docx",
             "-o", str(dst)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=60,
        )
        if result.returncode != 0:
            print(f"  [FAIL] pandoc: {result.stderr[:200]}")
            return False
        return True
    except Exception as e:
        print(f"  [ERROR] {e}")
        return False


def convert_period(period: str) -> int:
    """转某期所有模板，返回成功数。"""
    src_dir = SRC_ROOT / period / "模板"
    if not src_dir.exists():
        print(f"[SKIP] {src_dir} 不存在")
        return 0

    count = 0
    for md_file in sorted(src_dir.glob("*.md")):
        docx_file = md_file.with_suffix(".docx")
        print(f"  {md_file.name} -> {docx_file.name}", end=" ")
        if md_to_docx(md_file, docx_file):
            print("[OK]")
            count += 1
        else:
            print("[FAIL]")
    return count


def main():
    periods = sys.argv[1:] if len(sys.argv) > 1 else list(PERIOD_MAP.keys())
    total = 0
    for period in periods:
        if period not in PERIOD_MAP:
            print(f"[WARN] 未知期间: {period}，跳过")
            continue
        print(f"\n=== {period} ===")
        total += convert_period(period)
    print(f"\n共转换 {total} 个模板")


if __name__ == "__main__":
    main()
