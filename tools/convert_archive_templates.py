#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
归档模板预处理：把 data/归档/<期>/模板/*.docx 转成 markdown 放进
assets/archive_templates/<期>/，供运行时 LLM 当 few-shot 参考案例使用。

用法：
    python tools/convert_archive_templates.py            # 全转
    python tools/convert_archive_templates.py 期初       # 只转某期

依赖：pandoc（项目已装：3.6.3）
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Windows 终端默认 GBK，把 stdout 强转 UTF-8 防止 emoji 爆码（脚本里也避免用 emoji）
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SRC_ROOT = ROOT / "data" / "归档"
DST_ROOT = ROOT / "assets" / "archive_templates"

# 期间名 → 英文 key（避免 assets 中文路径在某些平台触发 bug）
PERIOD_MAP = {
    "期初": "start",
    "期中": "mid",
    "期末": "end",
    "归档": "final",
}

# 把同质模板归一化成 docType key（多份历届材料 → 同一 doc 类型 → AI 取最新一份当主参考、其它当副参考）
# **顺序敏感**：必须先匹配具体词（"合理性审核表"）再匹配宽泛词（"教学大纲"），否则
# "课程教学大纲合理性审核表.docx" 会被先归到 syllabus 而不是 syllabus_audit。
DOC_TYPE_PATTERNS = [
    (r"合理性审核表", "syllabus_audit"),
    (r"合理性评价表", "syllabus_review"),
    (r"达成评价报告|达成度评价", "obe_report"),
    (r"教学进度表", "progress_table"),
    (r"考核方案|综合考核", "assessment_plan"),
    (r"教学指导手册", "teaching_handbook"),
    (r"学习指导手册", "learning_handbook"),
    (r"教学大纲", "syllabus"),
]


def classify(filename: str) -> str | None:
    """根据文件名判断 docType，返回 None 表示不识别（不入资源）。"""
    for pattern, doc_type in DOC_TYPE_PATTERNS:
        if re.search(pattern, filename):
            return doc_type
    return None


def docx_to_md(src: Path, dst: Path) -> bool:
    """pandoc docx → 文本。失败返回 False。

    输出格式选 `plain` —— 因为 docx 模板里的复杂嵌套表格转 markdown/gfm 会
    爆出 HTML <table> 或几百字符宽的 pipe table，对 LLM 都是噪音。
    `plain` 把表格降级为简单文字布局，保留信息但去掉语法噪音，正是 LLM 当
    "风格学习材料"最需要的形态。

    输出文件保留 .md 扩展名，方便 Flutter assets 资源加载和 IDE 高亮。
    """
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            ["pandoc", str(src),
             "-f", "docx",
             "-t", "plain",
             "--columns=100",
             "--wrap=auto",
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


def convert_period(period_zh: str) -> int:
    """转一个期间的全部模板，返回成功数。"""
    period_en = PERIOD_MAP.get(period_zh)
    if not period_en:
        print(f"[WARN] unknown period: {period_zh}")
        return 0

    src_dir = SRC_ROOT / period_zh / "模板"
    if not src_dir.exists():
        print(f"[WARN] src dir missing: {src_dir}")
        return 0

    dst_dir = DST_ROOT / period_en
    if dst_dir.exists():
        shutil.rmtree(dst_dir)
    dst_dir.mkdir(parents=True)

    # 同 docType 多份历届材料：按文件名时间戳取最新一份当主，其余落 _ref/
    by_type: dict[str, list[Path]] = {}
    for src in src_dir.iterdir():
        if not src.is_file() or src.suffix.lower() != ".docx":
            continue
        doc_type = classify(src.name)
        if not doc_type:
            print(f"  [SKIP] unclassified: {src.name}")
            continue
        by_type.setdefault(doc_type, []).append(src)

    success = 0
    for doc_type, files in by_type.items():
        # 文件名里带日期 / 学年 / 年份的优先（最新优先）
        files.sort(key=lambda p: p.name, reverse=True)
        primary = files[0]
        primary_dst = dst_dir / f"{doc_type}.md"
        print(f"  [OK]   {doc_type} <- {primary.name}")
        if docx_to_md(primary, primary_dst):
            success += 1

        # 其它历届材料留作副参考（暂不读、备查）
        for extra in files[1:]:
            ref_dir = dst_dir / "_ref" / doc_type
            ref_dst = ref_dir / f"{extra.stem}.md"
            print(f"      [ref] {extra.name}")
            docx_to_md(extra, ref_dst)

    # 兄弟资源（模板上一层目录里的辅助资料）—— 把识别到的也作为副参考转一份
    # 例：data/归档/期初/《移动应用开发》综合考核方案.docx → _ref/assessment_plan/...
    parent_dir = SRC_ROOT / period_zh
    if parent_dir.exists():
        for src in parent_dir.iterdir():
            if not src.is_file() or src.suffix.lower() != ".docx":
                continue
            doc_type = classify(src.name)
            if not doc_type:
                continue
            # 已在主参考里就跳过（避免重复转）
            if doc_type in by_type:
                continue
            ref_dir = dst_dir / "_ref" / doc_type
            ref_dst = ref_dir / f"{src.stem}.md"
            print(f"  [sib]  {doc_type} <- {src.name} (sibling)")
            if docx_to_md(src, ref_dst):
                success += 1

        # 同时把上层 .md 文件原样拷贝（如教学进度表已是 md）
        for src in parent_dir.iterdir():
            if not src.is_file() or src.suffix.lower() != ".md":
                continue
            doc_type = classify(src.name)
            if not doc_type:
                continue
            if doc_type in by_type:
                continue
            ref_dir = dst_dir / "_ref" / doc_type
            ref_dst = ref_dir / src.name
            ref_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, ref_dst)
            print(f"  [sib]  {doc_type} <- {src.name} (sibling md)")
            success += 1

    # 写一份 index.md，列出本期间所有可用 docType + 主参考文件名
    index = dst_dir / "_index.md"
    with index.open("w", encoding="utf-8") as f:
        f.write(f"# {period_zh} 归档模板索引\n\n")
        f.write(f"由 `tools/convert_archive_templates.py` 自动生成。**请勿手改**——重跑脚本即覆盖。\n\n")
        f.write("| docType | 主参考来源（去 .docx 后缀的原文件名） |\n")
        f.write("|---------|----------------------------------|\n")
        for doc_type, files in sorted(by_type.items()):
            f.write(f"| `{doc_type}` | {files[0].stem} |\n")
        f.write(f"\n**期间英文 key**：`{period_en}`（assets/archive_templates/{period_en}/）\n")
        f.write(f"\n副参考（_ref/）：包含历届同类材料 + 上层目录的兄弟资源，AI 在生成时可选择性读取作为事实补充。\n")

    return success


def main():
    args = sys.argv[1:]
    periods = args if args else list(PERIOD_MAP.keys())

    if not shutil.which("pandoc"):
        print("[ERROR] pandoc not found. Install from https://pandoc.org/installing.html")
        sys.exit(1)

    DST_ROOT.mkdir(parents=True, exist_ok=True)
    total = 0
    for p in periods:
        print(f"\n=== {p} ===")
        n = convert_period(p)
        print(f"  done: {n} primary refs")
        total += n

    print(f"\n[ALL DONE] total {total} primary refs -> {DST_ROOT}")


if __name__ == "__main__":
    main()
