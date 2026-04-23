"""
Export student group data from Excel to JSON.

Source: data/项目/软件23选88实验分组-20260403.xlsx
Output: assets/student_group_data.json
"""

import json
import openpyxl
from pathlib import Path

# Paths
EXCEL_PATH = Path(r"D:\FlutterProjects\knowledge_graph_app\data\项目\软件23选88实验分组-20260403.xlsx")
JSON_PATH = Path(r"D:\FlutterProjects\knowledge_graph_app\assets\student_group_data.json")


def cell_str(cell_value) -> str:
    """Convert a cell value to a stripped string; None becomes empty string."""
    if cell_value is None:
        return ""
    return str(cell_value).strip()


def main():
    wb = openpyxl.load_workbook(EXCEL_PATH, read_only=True, data_only=True)
    ws = wb.active

    records = []
    for row in ws.iter_rows(min_row=2, max_row=87, max_col=12):
        user_id         = cell_str(row[0].value)   # A: 学号
        name            = cell_str(row[1].value)   # B: 姓名
        repo            = cell_str(row[2].value)   # C: 仓库名称
        # D (signature) — skipped in output
        class_group     = cell_str(row[4].value)   # E: 分组 → classGroup
        project         = cell_str(row[5].value)   # F: 实验项目
        role            = cell_str(row[6].value)   # G: 角色
        tech_stack      = cell_str(row[7].value)   # H: 技术栈
        # I: 核心职责 — skipped in output
        features        = cell_str(row[9].value)   # J: 特色功能
        feature_details = cell_str(row[10].value)  # K: 特色功能详细解释
        # L (remark) — skipped in output

        # Skip entirely empty rows
        if not user_id and not name:
            continue

        records.append({
            "userId":         user_id,
            "name":           name,
            "repo":           repo,
            "classGroup":     class_group,
            "project":        project,
            "role":           role,
            "techStack":      tech_stack,
            "features":       features,
            "featureDetails": feature_details,
        })

    wb.close()

    # Write JSON (UTF-8, no ASCII escaping, pretty-printed)
    JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, indent=2)

    # Summary
    print(f"Exported {len(records)} records to {JSON_PATH}")
    print()

    # Show first 3 samples
    for i, rec in enumerate(records[:3]):
        print(f"--- Sample {i+1} ---")
        for k, v in rec.items():
            print(f"  {k}: {v}")
        print()

    # Show classGroup distribution
    groups = {}
    for rec in records:
        g = rec["classGroup"] or "(empty)"
        groups[g] = groups.get(g, 0) + 1
    print("classGroup distribution:")
    for g in sorted(groups):
        print(f"  {g}: {groups[g]}")


if __name__ == "__main__":
    main()
