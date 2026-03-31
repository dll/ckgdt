#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量修复脚本：
1. withOpacity(x) → withValues(alpha: x)
2. 清理已知无用 import
"""

import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))

# ── 规则 1：withOpacity → withValues ────────────────────────────────────────
OPACITY_RE = re.compile(r"\.withOpacity\(([^)]+)\)")


def fix_with_opacity(content: str) -> str:
    return OPACITY_RE.sub(lambda m: f".withValues(alpha: {m.group(1)})", content)


# ── 规则 2：无用 import 清理 ──────────────────────────────────────────────────
UNUSED_IMPORTS = [
    # (文件相对路径, 要移除的 import 行 子串)
    ("lib/data/local/favorite_dao.dart", "import 'package:sqflite/sqflite.dart';"),
    (
        "lib/data/local/learning_record_dao.dart",
        "import 'package:sqflite/sqflite.dart';",
    ),
    ("lib/data/local/quiz_dao.dart", "import 'dart:developer';"),
    ("lib/data/local/user_dao.dart", "import 'package:sqflite/sqflite.dart';"),
    ("lib/data/local/wrong_answer_dao.dart", "import 'package:sqflite/sqflite.dart';"),
    (
        "lib/presentation/pages/graph/graph_detail_page.dart",
        "import '../../../data/models/graph_model.dart';",
    ),
    (
        "lib/presentation/pages/graph/graph_list_page.dart",
        "import 'package:flutter/foundation.dart';",
    ),
    (
        "lib/presentation/pages/materials/puml_manager_page.dart",
        "import '../../../core/constants/app_theme.dart';",
    ),
    ("lib/services/data_loading_service.dart", "import 'dart:io';"),
    (
        "lib/services/data_loading_service.dart",
        "import 'package:path_provider/path_provider.dart';",
    ),
    ("lib/services/data_migration_service.dart", "import 'dart:io';"),
    (
        "lib/services/data_migration_service.dart",
        "import '../data/models/graph_model.dart';",
    ),
    (
        "lib/services/data_migration_service.dart",
        "import '../data/models/node_model.dart';",
    ),
    (
        "lib/services/data_migration_service.dart",
        "import '../data/models/edge_model.dart';",
    ),
    (
        "lib/services/data_migration_service.dart",
        "import '../data/models/question_model.dart';",
    ),
]


def remove_import_line(content: str, import_str: str) -> str:
    lines = content.splitlines(keepends=True)
    result = []
    for line in lines:
        if line.strip() == import_str.strip():
            continue  # drop this line
        result.append(line)
    return "".join(result)


# ── 主流程 ───────────────────────────────────────────────────────────────────


def process_file_opacity(filepath: str) -> bool:
    """Apply withOpacity fix to a single Dart file. Returns True if changed."""
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            original = f.read()
    except (UnicodeDecodeError, PermissionError):
        return False

    if ".withOpacity(" not in original:
        return False

    fixed = fix_with_opacity(original)
    if fixed == original:
        return False

    with open(filepath, "w", encoding="utf-8", newline="") as f:
        f.write(fixed)
    return True


def main():
    # ── Step 1: withOpacity fix across all Dart files ─────────────────────
    print("=== Step 1: fixing withOpacity → withValues ===")
    changed_opacity = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # skip non-Flutter dirs
        dirnames[:] = [
            d
            for d in dirnames
            if d not in ("build", ".dart_tool", ".idea", "__pycache__", ".git")
            and not d.startswith(".")
        ]
        for fname in filenames:
            if not fname.endswith(".dart"):
                continue
            fpath = os.path.join(dirpath, fname)
            if process_file_opacity(fpath):
                rel = os.path.relpath(fpath, ROOT)
                changed_opacity.append(rel)
                print(f"  [fixed] {rel}")

    print(f"  → {len(changed_opacity)} file(s) updated\n")

    # ── Step 2: remove unused imports ────────────────────────────────────
    print("=== Step 2: removing unused imports ===")
    changed_imports = []
    for rel_path, import_line in UNUSED_IMPORTS:
        abs_path = os.path.join(ROOT, rel_path.replace("/", os.sep))
        if not os.path.isfile(abs_path):
            print(f"  [skip – not found] {rel_path}")
            continue
        try:
            with open(abs_path, "r", encoding="utf-8") as f:
                content = f.read()
        except (UnicodeDecodeError, PermissionError):
            continue

        if import_line not in content:
            continue  # already removed or not present

        new_content = remove_import_line(content, import_line)
        if new_content != content:
            with open(abs_path, "w", encoding="utf-8", newline="") as f:
                f.write(new_content)
            rel = rel_path
            if rel not in changed_imports:
                changed_imports.append(rel)
            print(f"  [removed] {import_line}  ←  {rel_path}")

    print(f"  → {len(set(changed_imports))} file(s) updated\n")

    print("✅  All fixes applied.")


if __name__ == "__main__":
    main()
