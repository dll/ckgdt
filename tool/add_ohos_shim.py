import os, re

files = """lib/core/design/noir_components.dart
lib/core/design/noir_tokens.dart
lib/presentation/pages/achievement/achievement_page.dart
lib/presentation/pages/admin/grade_entry_center_page.dart
lib/presentation/pages/admin/release_center_page.dart
lib/presentation/pages/admin/repo_analytics_page.dart
lib/presentation/pages/analytics/agent_calls_dashboard_page.dart
lib/presentation/pages/analytics/class_token_page.dart
lib/presentation/pages/analytics/request_detail_tab.dart
lib/presentation/pages/analytics/student_token_page.dart
lib/presentation/pages/analytics/token_stats_page.dart
lib/presentation/pages/archive/archive_page.dart
lib/presentation/pages/archive/tabs/archive_content_tab.dart
lib/presentation/pages/archive/tabs/period_tab.dart
lib/presentation/pages/archive/widgets/final_assessment_panel.dart
lib/presentation/pages/archive/widgets/midterm_special_panels.dart
lib/presentation/pages/assessment/assessment_materials_tab.dart
lib/presentation/pages/assessment/audit_print_panel.dart
lib/presentation/pages/class_qa/class_qa_detail_page.dart
lib/presentation/pages/class_qa/class_qa_page.dart
lib/presentation/pages/home/evaluation_hub_page.dart
lib/presentation/pages/home/home_page.dart
lib/presentation/pages/home/teaching_hub_page.dart
lib/presentation/pages/hot/add_video_page.dart
lib/presentation/pages/hot/hot_videos_page.dart
lib/presentation/pages/learning/video_source_selector.dart
lib/presentation/pages/login/knowledge_graph_backdrop.dart
lib/presentation/pages/login/login_page.dart
lib/presentation/pages/privacy/my_data_page.dart
lib/presentation/pages/repo/tabs/gitee_settings_tab.dart
lib/presentation/pages/repo/tabs/repo_list_tab.dart
lib/presentation/pages/repo/tabs/repo_stats_tab.dart
lib/presentation/pages/repo/tabs/student_detail_tab.dart
lib/presentation/pages/repo/tabs/submission_guidelines_tab.dart
lib/presentation/widgets/live_stream_panel.dart
lib/presentation/widgets/noir_page_shell.dart
lib/presentation/widgets/score_history_dialog.dart
lib/services/theme_manager.dart""".strip().split("\n")

SHIM = "lib/core/constants/color_ohos_compat.dart"

def relpath(frm):
    # 相对 import 路径：从 frm 所在目录到 SHIM
    rel = os.path.relpath(SHIM, os.path.dirname(frm)).replace(os.sep, "/")
    return rel

added = 0
skipped = 0
parents_needed = set()
for f in files:
    f = f.strip()
    if not f: continue
    with open(f, encoding="utf-8") as fh:
        content = fh.read()
    if "color_ohos_compat" in content:
        skipped += 1
        continue
    # part of 文件不能有自己的 import —— 记录其父文件，稍后给父文件加
    head = "\n".join(content.split("\n")[:6])
    m = re.search(r"part of ['\"]([^'\"]+)['\"]", head)
    if m:
        parent = os.path.normpath(os.path.join(os.path.dirname(f), m.group(1))).replace(os.sep, "/")
        parents_needed.add(parent)
        skipped += 1
        continue
    rel = relpath(f)
    imp = f"import '{rel}';"
    lines = content.split("\n")
    last_import = -1
    for i, ln in enumerate(lines):
        if re.match(r"^\s*import\s+['\"]", ln) or re.match(r"^\s*export\s+['\"]", ln):
            last_import = i
    if last_import == -1:
        lines.insert(0, imp)
    else:
        lines.insert(last_import + 1, imp)
    with open(f, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    added += 1

# 给 part-of 文件的父文件加 import
for parent in parents_needed:
    with open(parent, encoding="utf-8") as fh:
        content = fh.read()
    if "color_ohos_compat" in content:
        continue
    rel = relpath(parent)
    imp = f"import '{rel}';"
    lines = content.split("\n")
    last_import = -1
    for i, ln in enumerate(lines):
        if re.match(r"^\s*import\s+['\"]", ln) or re.match(r"^\s*export\s+['\"]", ln):
            last_import = i
    lines.insert(last_import + 1 if last_import >= 0 else 0, imp)
    with open(parent, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    added += 1
    print(f"  父文件补 import: {parent}")

print(f"补充 import: {added} 个文件, 跳过(已有/part-of): {skipped} 个")

