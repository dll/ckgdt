#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PDF 文档生成脚本：把 data/CKGDT/ 下各目录的 .md 文件转成 .pdf。

支持的源目录：
  - 大纲/     → PDF
  - 进度/     → PDF
  - 理论/     → PDF（教案/作业/测验）
  - 实验/     → PDF（实验教程/报告模板）
  - 考核/     → PDF
  - 达成/     → PDF
  - 归档/     → PDF

依赖：pandoc

用法：
    python tools/generate_ckgdt_pdfs.py            # 生成所有 PDF
    python tools/generate_ckgdt_pdfs.py 大纲        # 只转大纲目录
    python tools/generate_ckgdt_pdfs.py --list      # 列出所有可转文件
"""

import subprocess
import sys
from pathlib import Path

# Windows 终端 UTF-8
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SRC_ROOT = ROOT / "data" / "CKGDT"
OUT_ROOT = ROOT / "data" / "CKGDT" / "输出" / "PDF"

# 要转换的目录
CONVERT_DIRS = [
    "大纲",
    "进度",
    "理论",
    "实验",
    "考核",
    "达成",
    "测验",
]


def md_to_pdf(src: Path, dst: Path) -> bool:
    """pandoc markdown → PDF。"""
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            ["pandoc", str(src),
             "-f", "markdown",
             "-t", "pdf",
             "--pdf-engine=xelatex",
             "-V", "CJKmainfont=Microsoft YaHei",
             "-V", "geometry:margin=2.5cm",
             "-o", str(dst)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=120,
        )
        if result.returncode != 0:
            # 尝试不带 xelatex（回退到 pdflatex，可能不支持中文）
            result2 = subprocess.run(
                ["pandoc", str(src),
                 "-f", "markdown",
                 "-o", str(dst)],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                timeout=120,
            )
            if result2.returncode != 0:
                print(f"  [FAIL] pandoc: {result2.stderr[:200]}")
                return False
        return True
    except Exception as e:
        print(f"  [ERROR] {e}")
        return False


def convert_dir(dir_name: str) -> int:
    """转某目录下所有 .md → .pdf，返回成功数。"""
    src_dir = SRC_ROOT / dir_name
    if not src_dir.exists():
        print(f"[SKIP] {src_dir} 不存在")
        return 0
    
    count = 0
    for md_file in sorted(src_dir.rglob("*.md")):
        # 计算相对路径
        rel_path = md_file.relative_to(src_dir)
        pdf_file = OUT_ROOT / dir_name / rel_path.with_suffix(".pdf")
        
        print(f"  {rel_path} -> {pdf_file.name}", end=" ")
        if md_to_pdf(md_file, pdf_file):
            print("[OK]")
            count += 1
        else:
            print("[FAIL]")
    
    return count


def list_files():
    """列出所有可转换文件。"""
    print("\n可转换的 Markdown 文件：")
    for dir_name in CONVERT_DIRS:
        src_dir = SRC_ROOT / dir_name
        if not src_dir.exists():
            continue
        files = list(src_dir.rglob("*.md"))
        if files:
            print(f"\n  {dir_name}/ ({len(files)} 个)")
            for f in files[:5]:
                print(f"    - {f.relative_to(SRC_ROOT)}")
            if len(files) > 5:
                print(f"    ... 共 {len(files)} 个")


def main():
    if "--list" in sys.argv:
        list_files()
        return
    
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    
    # 确定要转换的目录
    if len(sys.argv) > 1 and sys.argv[1] != "--list":
        dirs = [d for d in CONVERT_DIRS if sys.argv[1] in d]
        if not dirs:
            print(f"[ERROR] 未找到包含 '{sys.argv[1]}' 的目录")
            return
    else:
        dirs = CONVERT_DIRS
    
    print(f"\n=== CKGDT PDF 生成 ===")
    print(f"源目录: {SRC_ROOT}")
    print(f"输出目录: {OUT_ROOT}")
    print(f"待处理目录: {', '.join(dirs)}\n")
    
    total = 0
    for dir_name in dirs:
        print(f"\n=== {dir_name} ===")
        total += convert_dir(dir_name)
    
    print(f"\n共转换 {total} 个文件")


if __name__ == "__main__":
    main()
