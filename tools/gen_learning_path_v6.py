#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_learning_path_v6.py
学习路径功能教学视频 v6

输出：
  video_output/学习路径功能教程_v6.mp4
  video_output/学习路径功能教程_v6.pptx
  docs/video/feat_learning_path/script.md
  docs/video/feat_learning_path/subtitles.srt
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from video_common_v6 import *  # noqa: F401,F403

# ─── 路径常量 ───────────────────────────────────────────────────────────────
FEAT_DIR = ROOT / "docs" / "video" / "feat_learning_path"
VIDEO_PATH = OUT_DIR / "学习路径功能教程_v6.mp4"
PPTX_PATH = OUT_DIR / "学习路径功能教程_v6.pptx"
SRT_PATH = FEAT_DIR / "subtitles.srt"
SCRIPT_PATH = FEAT_DIR / "script.md"
CROPS_DIR = FEAT_DIR / "crops"


# ═══════════════════════════════════════════════════════════════════════════
# MOCK SCREENSHOTS
# ═══════════════════════════════════════════════════════════════════════════
def build_feature_shots(crops_dir: Path) -> dict[str, Path]:
    """生成学习路径功能特有的 Mock 截图。"""
    shots: dict[str, Path] = {}

    # ── 1. 计划列表主页 ──────────────────────────────────────────────────
    shots["plan_list"] = mock_page(
        "LearningPlanPage  学习计划",
        "ListView.builder · FloatingActionButton · 硬编码 _plans 数据",
        ["计划列表", "进度追踪", "章节管理"],
        [
            (
                "Flutter入门计划",
                "7天学会Flutter基础开发 · 已完成 4/7天 · 进度 60%",
                PRIMARY,
            ),
            (
                "Android开发进阶",
                "14天掌握Android高级特性 · 已完成 4/14天 · 进度 30%",
                GREEN,
            ),
            (
                "跨平台开发实战",
                "30天完成一个完整项目 · 已完成 3/30天 · 进度 10%",
                ORANGE,
            ),
        ],
        crops_dir / "mock_plan_list.png",
    )

    # ── 2. 总体进度卡片 ──────────────────────────────────────────────────
    shots["header_card"] = mock_page(
        "_buildHeader()  总体进度卡片",
        "所有计划平均进度 · LinearProgressIndicator · 计划数量统计",
        ["总体进度", "平均计算", "进度条"],
        [
            ("总体进度", "三个计划平均进度 = (60+30+10)/3 = 33%", ACCENT),
            (
                "进度条样式",
                "LinearProgressIndicator · minHeight:10 · 圆角裁剪",
                PRIMARY,
            ),
            ("参与计划数", "正在参与 3 个学习计划 · 动态跟随 _plans.length", GREEN),
        ],
        crops_dir / "mock_header_card.png",
    )

    # ── 3. 计划卡片组件 ──────────────────────────────────────────────────
    shots["plan_card"] = mock_page(
        "_buildPlanCard()  计划卡片",
        "图标 + 标题 + 进度条 + 天数 + 章节数 + 弹出菜单",
        ["卡片布局", "进度显示", "操作菜单"],
        [
            (
                "标题行",
                "Icon(calendar_today) + 计划标题 + 描述 + PopupMenuButton",
                PRIMARY,
            ),
            (
                "进度行",
                "LinearProgressIndicator + 百分比文字，颜色随计划 color 变化",
                GREEN,
            ),
            ("底部统计", "已完成 N/M 天 · X 个章节  (从 _plans 数据读取)", ORANGE),
        ],
        crops_dir / "mock_plan_card.png",
    )

    # ── 4. 章节详情底部弹窗 ──────────────────────────────────────────────
    shots["plan_detail"] = mock_page(
        "_showPlanDetail()  章节完成情况",
        "showModalBottomSheet · DraggableScrollableSheet · 逐章 CheckList",
        ["底部弹窗", "章节列表", "完成状态"],
        [
            ("Flutter概述", "✅ 已完成 · CircleAvatar(green) + check 图标", GREEN),
            ("Dart语言基础", "✅ 已完成 · 标题加删除线 · 文字置灰", GREEN),
            ("Widget介绍", "✅ 已完成 · index < completedDays → 标记完成", GREEN),
            ("状态管理", "⭕ 未完成 · radio_button_unchecked 图标 · 正常色", ORANGE),
        ],
        crops_dir / "mock_plan_detail.png",
    )

    # ── 5. 创建计划对话框 ────────────────────────────────────────────────
    shots["plan_create"] = mock_page(
        "_showCreatePlanDialog()  创建学习计划",
        "AlertDialog · TextField(名称) + TextField(描述) · 创建/取消",
        ["对话框", "表单输入", "创建操作"],
        [
            (
                "计划名称输入框",
                "TextField · labelText:'计划名称' · 输入学习计划名称",
                PRIMARY,
            ),
            ("计划描述输入框", "TextField · maxLines:2 · labelText:'计划描述'", GREEN),
            ("操作按钮", "TextButton(取消) + ElevatedButton(创建) · 响应提交", ACCENT),
        ],
        crops_dir / "mock_plan_create.png",
    )

    # ── 6. 删除操作流程 ──────────────────────────────────────────────────
    shots["plan_delete"] = mock_page(
        "_deletePlan()  删除计划",
        "PopupMenuButton → onSelected → setState(_plans.remove) → SnackBar",
        ["菜单触发", "状态更新", "反馈提示"],
        [
            ("PopupMenuButton", "卡片右上角三点菜单 · 点击弹出选项列表", ORANGE),
            ("value:'delete'", "onSelected 回调 → 调用 _deletePlan(plan)", RED_C),
            ("setState", "_plans.remove(plan) · UI 自动重建 · ListView 缩短", PRIMARY),
            ("SnackBar", "底部提示：已删除 'Flutter入门计划' · 2秒自动消失", GREEN),
        ],
        crops_dir / "mock_plan_delete.png",
    )

    return shots


# ═══════════════════════════════════════════════════════════════════════════
# SLIDES DEFINITION  (15 slides)
# ═══════════════════════════════════════════════════════════════════════════
def build_slides(
    crops: dict[str, Path],
    shots: dict[str, Path],
) -> list[SlideSpec]:  # type: ignore[name-defined]
    return [
        # ── 01. 课程导入 ──────────────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="课程导入",
            subtitle="学习路径功能 — 帮助用户规划和追踪学习进度",
            bullets=[
                "功能定位：个人学习计划管理中心",
                "核心能力：创建 / 查看 / 删除学习计划",
                "进度追踪：章节完成情况可视化",
                "交互设计：底部弹窗 + 对话框 + 弹出菜单",
                "技术实现：StatefulWidget + ListView.builder",
            ],
            narration=(
                "欢迎进入学习路径功能教学视频。"
                "学习路径页面是知识图谱 App 的学习管理中心，"
                "帮助用户创建个人学习计划，追踪每个计划的完成进度，"
                "并以章节列表的形式展示具体学习内容。"
                "本视频将带你深入了解页面架构、数据模型、核心组件和交互流程。"
            ),
            image_path=crops.get("framework_full"),
            image_caption="知识图谱 App · 整体架构",
        ),
        # ── 02. 功能模块总览 ──────────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="功能模块总览",
            subtitle="LearningPlanPage 的六大核心模块",
            bullets=[
                "① 总体进度卡片 — 所有计划的平均完成度",
                "② 计划卡片列表 — ListView.builder 渲染",
                "③ 章节详情弹窗 — DraggableScrollableSheet",
                "④ 创建计划对话框 — AlertDialog + TextField",
                "⑤ 删除计划操作 — PopupMenuButton + setState",
                "⑥ 状态管理 — _LearningPlanPageState 单一数据源",
            ],
            narration=(
                "学习路径页面包含六个核心模块。"
                "第一是顶部的总体进度卡片，汇总显示所有计划的平均完成百分比。"
                "第二是使用 ListView.builder 渲染的计划卡片列表，每张卡片展示一个计划的进度信息。"
                "第三是点击卡片后弹出的章节详情底部面板，采用 DraggableScrollableSheet 实现可拖拽效果。"
                "第四是通过右上角悬浮按钮触发的创建计划对话框。"
                "第五是通过卡片右侧弹出菜单触发的删除操作。"
                "第六是贯穿全页的 State 状态管理，_plans 列表是唯一数据源。"
            ),
            image_path=shots.get("plan_list"),
            image_caption="LearningPlanPage — 主页全貌",
        ),
        # ── 03. 项目中的位置与导航 ────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="页面在项目中的位置",
            subtitle="lib/presentation/pages/learning/learning_plan_page.dart",
            bullets=[
                "层级：presentation → pages → learning",
                "继承：StatefulWidget → _LearningPlanPageState",
                "依赖：AuthService（预留用户身份关联）",
                "路由：从底部导航栏或侧边栏跳转",
                "脚手架：Scaffold + AppBar + FloatingActionButton",
            ],
            narration=(
                "在项目目录中，LearningPlanPage 位于 lib/presentation/pages/learning/ 目录下，"
                "属于表现层的页面模块。"
                "它继承自 StatefulWidget，配合私有的 State 类管理页面内部状态。"
                "页面导入了 AuthService，为后续关联用户身份预留接口。"
                "整体脚手架由 Scaffold 构成，顶部有渐变色 AppBar，"
                "右下角有一个悬浮的添加按钮，底部内容区域由 ListView 填充。"
            ),
            image_path=crops.get("framework_ui"),
            image_caption="presentation 层架构示意",
            code_title="文件路径",
            code_text=(
                "lib/\n"
                "└── presentation/\n"
                "    └── pages/\n"
                "        └── learning/\n"
                "            └── learning_plan_page.dart\n"
                "                ├── LearningPlanPage (StatefulWidget)\n"
                "                └── _LearningPlanPageState (State)"
            ),
        ),
        # ── 04. 数据模型 ──────────────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="数据模型",
            subtitle="_plans — 硬编码在 State 内的学习计划列表",
            bullets=[
                "类型：List<Map<String, dynamic>>",
                "title：计划名称（String）",
                "description：目标描述（String）",
                "progress：完成百分比 0-100（int）",
                "days：总天数（int）",
                "completedDays：已完成天数（int）",
                "chapters：章节名称列表（List<String>）",
                "color：卡片主题色（Color）",
            ],
            narration=(
                "当前版本的数据模型采用 List<Map<String, dynamic>> 格式，"
                "直接硬编码在 _LearningPlanPageState 中。"
                "每个计划包含八个字段：title 是计划名称，description 是目标描述，"
                "progress 是当前完成百分比，days 是计划总天数，"
                "completedDays 是已完成的天数，chapters 是章节名称列表，"
                "color 决定卡片的主题颜色。"
                "三个示例计划分别是 Flutter 入门、Android 进阶和跨平台实战，"
                "进度分别为 60%、30% 和 10%。"
            ),
            image_path=shots.get("plan_list"),
            image_caption="三个硬编码示例计划",
            code_title="数据结构示例",
            code_text=(
                "final List<Map<String,dynamic>> _plans = [\n"
                "  {\n"
                "    'title':        'Flutter入门计划',\n"
                "    'description':  '7天学会Flutter基础开发',\n"
                "    'progress':     60,\n"
                "    'days':         7,\n"
                "    'completedDays':4,\n"
                "    'chapters':     ['Flutter概述','Dart基础',...],\n"
                "    'color':        Colors.blue,\n"
                "  }, ...\n"
                "];"
            ),
        ),
        # ── 05. 页面骨架 Scaffold ────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="页面骨架",
            subtitle="Scaffold + AppBar + ListView.builder + FloatingActionButton",
            bullets=[
                "AppBar：backgroundColor #667eea · 白色前景色",
                "body：ListView.builder · padding: all(16)",
                "itemCount：_plans.length + 1（+1 为 Header）",
                "itemBuilder：index==0 → Header，其余 → PlanCard",
                "FloatingActionButton：蓝紫色 · 图标 Icons.add",
                "onPressed：触发 _showCreatePlanDialog(context)",
            ],
            narration=(
                "页面骨架由 Scaffold 搭建。"
                "AppBar 使用 #667eea 蓝紫渐变色作为背景，前景文字和图标为白色。"
                "body 是一个 ListView.builder，padding 为 16 像素，"
                "itemCount 设置为 _plans.length + 1，其中索引 0 渲染总体进度卡片，"
                "后续索引依次渲染各个计划卡片。"
                "右下角的 FloatingActionButton 采用同款蓝紫色，"
                "点击后触发创建计划对话框。"
            ),
            image_path=crops.get("class_ui"),
            image_caption="Widget 树结构示意",
            code_title="build() 骨架",
            code_text=(
                "Scaffold(\n"
                "  appBar: AppBar(title: Text('学习计划'),\n"
                "    backgroundColor: Color(0xFF667eea)),\n"
                "  body: ListView.builder(\n"
                "    itemCount: _plans.length + 1,\n"
                "    itemBuilder: (ctx, i) {\n"
                "      if (i == 0) return _buildHeader();\n"
                "      return _buildPlanCard(_plans[i-1]);\n"
                "    }),\n"
                "  floatingActionButton: FloatingActionButton(\n"
                "    onPressed: () => _showCreatePlanDialog(ctx)),\n"
                ")"
            ),
        ),
        # ── 06. 总体进度卡片 _buildHeader ────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="总体进度卡片",
            subtitle="_buildHeader() — 所有计划的平均进度汇总",
            bullets=[
                "Card + Padding(all:16) 包裹布局",
                "totalProgress = Σprogress / plans.length",
                "LinearProgressIndicator(value: total/100)",
                "minHeight:10 + ClipRRect(radius:8) 圆角进度条",
                "百分比文字 Color(0xFF667eea) 加粗显示",
                "底部说明：正在参与 N 个学习计划",
            ],
            narration=(
                "总体进度卡片由 _buildHeader 方法构建，作为 ListView 的第 0 项渲染。"
                "totalProgress 通过 map 取出所有计划的 progress 字段后求和再除以计划数量，"
                "得到一个浮点数平均值。"
                "LinearProgressIndicator 的 value 参数接收 totalProgress 除以 100 的小数形式。"
                "外层用 ClipRRect 裁剪成圆角，minHeight 设为 10 像素使进度条更粗。"
                "右侧显示取整后的百分比数字，底部一行文字动态显示当前参与的计划数量。"
            ),
            image_path=shots.get("header_card"),
            image_caption="_buildHeader() 总体进度卡片",
            code_title="进度计算逻辑",
            code_text=(
                "final totalProgress = _plans.isEmpty\n"
                "  ? 0.0\n"
                "  : _plans\n"
                "      .map((p) => p['progress'] as int)\n"
                "      .reduce((a, b) => a + b)\n"
                "    / _plans.length;\n"
                "\n"
                "LinearProgressIndicator(\n"
                "  value: totalProgress / 100,\n"
                "  minHeight: 10,\n"
                "  valueColor: AlwaysStoppedAnimation(\n"
                "    Color(0xFF667eea)),\n"
                ")"
            ),
        ),
        # ── 07. 计划卡片组件 _buildPlanCard ──────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="计划卡片组件",
            subtitle="_buildPlanCard() — 单个计划的完整信息展示",
            bullets=[
                "Card + InkWell(onTap → _showPlanDetail) 可点击",
                "顶部行：图标容器 + 标题列 + PopupMenuButton",
                "图标容器：color.withValues(alpha:0.1) 浅色背景",
                "Icon(calendar_today) 颜色跟随计划 color 字段",
                "中部：LinearProgressIndicator + 百分比",
                "底部行：已完成 N/M 天 · X 个章节",
            ],
            narration=(
                "每个计划对应一个 _buildPlanCard 卡片。"
                "Card 内部包裹 InkWell，点击整张卡片触发章节详情弹窗。"
                "顶部一行分为三个部分：左侧是带背景色的图标容器，"
                "颜色取自计划的 color 字段并调低透明度；"
                "中间是标题和描述的列；右侧是带有删除选项的三点弹出菜单。"
                "中部是与计划 color 一致的彩色进度条，右侧显示当前百分比。"
                "底部两端分别显示已完成天数和章节总数，文字颜色置灰处理。"
            ),
            image_path=shots.get("plan_card"),
            image_caption="_buildPlanCard() 卡片结构",
            code_title="卡片顶部行",
            code_text=(
                "Row(children: [\n"
                "  Container(\n"
                "    decoration: BoxDecoration(\n"
                "      color: plan['color'].withValues(alpha:0.1),\n"
                "      borderRadius: BorderRadius.circular(8)),\n"
                "    child: Icon(Icons.calendar_today,\n"
                "      color: plan['color'])),\n"
                "  Expanded(child: Column(\n"
                "    children: [Text(plan['title']),\n"
                "               Text(plan['description'])])),\n"
                "  PopupMenuButton(...),\n"
                "])"
            ),
        ),
        # ── 08. 进度追踪逻辑 ──────────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="进度追踪逻辑",
            subtitle="LinearProgressIndicator 双层应用 — 全局 + 单计划",
            bullets=[
                "全局进度：Σprogress / plans.length → Header 卡片",
                "单计划进度：plan['progress'] / 100 → 卡片内",
                "progress 字段当前为静态 int，未来可实时计算",
                "completedDays / days × 100 = 动态进度公式",
                "颜色编码：蓝=Flutter · 绿=Android · 橙=跨平台",
                "进度条高度：Header 10px · 计划卡片 8px",
            ],
            narration=(
                "进度追踪在两个层面同时进行。"
                "全局层面，_buildHeader 对所有计划的 progress 字段求平均值，"
                "渲染在顶部汇总进度条中。"
                "单计划层面，_buildPlanCard 直接读取当前计划的 progress 整数，"
                "除以 100 后传入 LinearProgressIndicator 的 value 参数。"
                "目前 progress 是硬编码的静态值，未来可以根据 completedDays 除以 days 动态计算。"
                "三个示例计划使用不同颜色——蓝色代表 Flutter 入门，绿色代表 Android 进阶，橙色代表跨平台实战——"
                "通过颜色编码帮助用户快速区分。"
            ),
            image_path=shots.get("header_card"),
            image_caption="双层进度可视化",
            code_title="动态进度计算（可扩展）",
            code_text=(
                "// 当前：静态字段\n"
                "value: plan['progress'] / 100\n"
                "\n"
                "// 可扩展为动态计算：\n"
                "final dynamicPct =\n"
                "  plan['completedDays'] / plan['days'];\n"
                "value: dynamicPct   // 0.0 ~ 1.0\n"
                "\n"
                "// 显示文字\n"
                "'${(dynamicPct*100).toInt()}%'"
            ),
        ),
        # ── 09. 章节详情底部弹窗 ──────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="章节详情底部弹窗",
            subtitle="_showPlanDetail() — showModalBottomSheet + DraggableScrollableSheet",
            bullets=[
                "showModalBottomSheet(isScrollControlled:true)",
                "圆角顶部：RoundedRectangleBorder(top 20px)",
                "DraggableScrollableSheet：initial 0.6 · min 0.4 · max 0.9",
                "顶部拖动指示条 + 计划标题 + 关闭按钮",
                "Divider 分隔线后接章节 ListView",
                "章节列表：itemCount = chapters.length",
            ],
            narration=(
                "点击任意计划卡片触发 _showPlanDetail 方法，"
                "调用 showModalBottomSheet 弹出底部面板。"
                "isScrollControlled 设为 true 允许面板占据更大屏幕空间。"
                "面板顶部使用 RoundedRectangleBorder 裁出 20 像素圆角。"
                "内部是一个 DraggableScrollableSheet，初始高度为屏幕的 60%，"
                "最小可收缩到 40%，最大可展开到 90%，支持手势拖拽。"
                "面板顶部有一条灰色拖动指示条，下方是计划标题和关闭图标，"
                "分隔线以下是章节条目的 ListView。"
            ),
            image_path=shots.get("plan_detail"),
            image_caption="章节列表底部弹窗",
            code_title="弹窗关键参数",
            code_text=(
                "showModalBottomSheet(\n"
                "  context: context,\n"
                "  isScrollControlled: true,\n"
                "  shape: RoundedRectangleBorder(\n"
                "    borderRadius: BorderRadius.vertical(\n"
                "      top: Radius.circular(20))),\n"
                "  builder: (_) => DraggableScrollableSheet(\n"
                "    initialChildSize: 0.6,\n"
                "    minChildSize:     0.4,\n"
                "    maxChildSize:     0.9,\n"
                "    expand: false, ...),\n"
                ");"
            ),
        ),
        # ── 10. 章节完成状态渲染 ──────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="章节完成状态渲染",
            subtitle="isCompleted = index < completedDays — 双态 UI 设计",
            bullets=[
                "isCompleted：index < plan['completedDays'] → bool",
                "已完成：CircleAvatar(green) + check 图标",
                "未完成：CircleAvatar(grey300) + 序号文字",
                "已完成标题：decoration=lineThrough · color=grey",
                "trailing：check_circle(绿) vs radio_button_unchecked(灰)",
                "ListView.builder 按 chapters 列表顺序渲染",
            ],
            narration=(
                "章节列表的每个条目根据 isCompleted 布尔值呈现两种不同状态。"
                "判断逻辑简洁直接：若章节索引小于 completedDays，则视为已完成。"
                "已完成章节：左侧头像背景为绿色并显示对勾图标，"
                "标题文字加上删除线并置灰，右侧尾部图标为绿色实心圆形对勾。"
                "未完成章节：左侧头像背景为浅灰并显示序号数字，"
                "标题文字保持正常样式，右侧尾部图标为灰色空心圆形。"
                "这种双态设计让用户一眼便能区分学习进度。"
            ),
            image_path=shots.get("plan_detail"),
            image_caption="双态章节条目对比",
            code_title="条目构建逻辑",
            code_text=(
                "final isCompleted = index < plan['completedDays'];\n"
                "ListTile(\n"
                "  leading: CircleAvatar(\n"
                "    backgroundColor: isCompleted\n"
                "      ? Colors.green : Colors.grey[300],\n"
                "    child: isCompleted\n"
                "      ? Icon(Icons.check, color: Colors.white)\n"
                "      : Text('${index+1}')),\n"
                "  title: Text(chapter,\n"
                "    style: TextStyle(\n"
                "      decoration: isCompleted\n"
                "        ? TextDecoration.lineThrough : null)),\n"
                "  trailing: isCompleted\n"
                "    ? Icon(Icons.check_circle, color:Colors.green)\n"
                "    : Icon(Icons.radio_button_unchecked),\n"
                ")"
            ),
        ),
        # ── 11. 创建计划对话框 ────────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="创建计划对话框",
            subtitle="_showCreatePlanDialog() — AlertDialog + 两个 TextField",
            bullets=[
                "FloatingActionButton.onPressed 触发入口",
                "showDialog(builder → AlertDialog)",
                "TextField①：labelText '计划名称' · hintText 引导输入",
                "TextField②：labelText '计划描述' · maxLines:2",
                "TextButton(取消) → Navigator.pop(context)",
                "ElevatedButton(创建) → 显示 SnackBar 占位提示",
            ],
            narration=(
                "点击右下角悬浮按钮触发 _showCreatePlanDialog 方法。"
                "内部调用 showDialog 弹出 AlertDialog，"
                "标题栏显示「创建学习计划」，内容区包含两个输入框。"
                "第一个 TextField 用于填写计划名称，带有占位提示文字。"
                "第二个 TextField 支持多行输入（maxLines 为 2），用于填写计划描述。"
                "底部操作区有两个按钮：取消按钮关闭对话框，"
                "创建按钮目前仅弹出一条「功能开发中」的 SnackBar 提示，"
                "正式提交逻辑留待后续开发。"
            ),
            image_path=shots.get("plan_create"),
            image_caption="创建计划 AlertDialog",
            code_title="创建按钮回调",
            code_text=(
                "ElevatedButton(\n"
                "  onPressed: () {\n"
                "    Navigator.pop(context);\n"
                "    ScaffoldMessenger.of(context)\n"
                "      .showSnackBar(SnackBar(\n"
                "        content: Text(\n"
                "          '学习计划创建功能开发中')));\n"
                "  },\n"
                "  child: Text('创建'),\n"
                "),"
            ),
        ),
        # ── 12. 删除计划操作 ──────────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="删除计划操作",
            subtitle="PopupMenuButton → _deletePlan() → setState → SnackBar",
            bullets=[
                "PopupMenuButton<String> 位于卡片标题行右侧",
                "itemBuilder 返回单条菜单项：value='delete'",
                "onSelected：value=='delete' → _deletePlan(plan)",
                "_deletePlan：setState(() { _plans.remove(plan); })",
                "remove() 通过对象引用精准定位并移除",
                "SnackBar：已删除 'xxx' · context.mounted 隐患需注意",
            ],
            narration=(
                "删除操作从卡片右侧的 PopupMenuButton 触发。"
                "点击三点图标后弹出包含「删除计划」的下拉菜单。"
                "选择后 onSelected 回调判断 value 为 delete，调用 _deletePlan。"
                "_deletePlan 在 setState 回调中直接调用 _plans.remove 传入计划 Map 对象，"
                "利用对象引用相等性精准定位并移除目标计划。"
                "remove 后 setState 驱动 ListView 重建，列表立即缩短一项。"
                "操作完成后 ScaffoldMessenger 弹出底部提示，告知用户哪个计划被删除。"
                "需要注意的是，showSnackBar 在异步环境下应检查 context.mounted。"
            ),
            image_path=shots.get("plan_delete"),
            image_caption="删除操作完整链路",
            code_title="_deletePlan 实现",
            code_text=(
                "void _deletePlan(Map<String,dynamic> plan) {\n"
                "  setState(() {\n"
                "    _plans.remove(plan);\n"
                "  });\n"
                "  ScaffoldMessenger.of(context)\n"
                "    .showSnackBar(SnackBar(\n"
                "      content: Text(\n"
                "        '已删除 \"${plan['title']}\"')));\n"
                "}"
            ),
        ),
        # ── 13. 状态管理与 setState ───────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="状态管理",
            subtitle="StatefulWidget + _LearningPlanPageState — 单一数据源模式",
            bullets=[
                "State 类持有 _plans 列表 = 唯一数据源",
                "setState() 触发 build() 重新执行",
                "ListView.builder 按新 _plans 重绘所有卡片",
                "Header 进度值随 _plans 变化自动重算",
                "当前无 Provider / Riverpod 等外部状态管理",
                "优点：简洁；缺点：数据不跨页面、无持久化",
            ],
            narration=(
                "当前版本采用最基础的 StatefulWidget 状态管理方案。"
                "_LearningPlanPageState 持有 _plans 列表，"
                "这是整个页面的唯一数据源。"
                "任何对 _plans 的修改都必须包裹在 setState 中，"
                "以通知 Flutter 框架在下一帧重新执行 build 方法。"
                "这种方案的优点是代码简洁、易于理解，适合功能原型开发。"
                "缺点是数据仅存在于内存，页面销毁后丢失，"
                "且无法跨页面共享学习计划数据。"
                "后续可引入 Provider 或 Riverpod 实现全局状态管理。"
            ),
            image_path=crops.get("class_dao"),
            image_caption="State 与数据流向示意",
            code_title="setState 驱动重建",
            code_text=(
                "// 删除后重建\n"
                "setState(() { _plans.remove(plan); });\n"
                "// ↑ 触发 build() → ListView 重绘\n"
                "\n"
                "// build() 每次读取最新 _plans\n"
                "itemCount: _plans.length + 1,\n"
                "itemBuilder: (ctx, i) {\n"
                "  if (i == 0) return _buildHeader();\n"
                "  // Header 自动用新 _plans 重算进度\n"
                "  return _buildPlanCard(_plans[i-1]);\n"
                "}"
            ),
        ),
        # ── 14. 扩展方向 ──────────────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="扩展方向",
            subtitle="从原型到生产级功能的演进路径",
            bullets=[
                "① 数据持久化：SharedPreferences / SQLite / Hive",
                "② 后端同步：REST API + JWT 认证 + 离线缓存",
                "③ 动态进度：completedDays / days 实时计算",
                "④ 章节状态可编辑：点击章节切换完成状态",
                "⑤ 全局状态：Provider / Riverpod 跨页共享",
                "⑥ 推送提醒：本地通知 + 每日学习提醒",
            ],
            narration=(
                "当前实现是功能完整的原型版本，后续可从六个方向进行生产化演进。"
                "第一，数据持久化：使用 SharedPreferences 存储简单数据，"
                "或 SQLite、Hive 处理复杂结构。"
                "第二，后端同步：通过 REST API 与服务器交互，支持多设备同步。"
                "第三，动态进度：将静态 progress 字段改为 completedDays / days 的实时计算。"
                "第四，章节交互：允许用户点击章节条目切换完成状态，同步更新进度。"
                "第五，全局状态管理：引入 Provider 或 Riverpod，"
                "使其他页面也能感知学习计划变化。"
                "第六，推送提醒：结合本地通知插件，每天定时提醒用户继续学习。"
            ),
            image_path=crops.get("process_full"),
            image_caption="功能演进路线图",
        ),
        # ── 15. 功能总结 ──────────────────────────────────────────────
        SlideSpec(  # type: ignore[name-defined]
            title="功能总结",
            subtitle="LearningPlanPage — 完整的学习计划管理闭环",
            bullets=[
                "✅ 计划列表：ListView.builder 高效渲染",
                "✅ 总体进度：动态平均计算 + 进度条可视化",
                "✅ 章节详情：DraggableScrollableSheet 流畅体验",
                "✅ 完成状态：双态 UI 直观展示学习进度",
                "✅ 创建计划：AlertDialog + 表单输入",
                "✅ 删除计划：setState 驱动即时刷新",
            ],
            narration=(
                "本视频完整讲解了 LearningPlanPage 的学习路径功能。"
                "页面通过 ListView.builder 高效渲染计划列表，"
                "顶部进度卡片动态汇总所有计划的平均完成度。"
                "DraggableScrollableSheet 提供流畅的底部章节详情面板，"
                "双态 UI 设计让已完成与未完成章节一目了然。"
                "AlertDialog 实现快速创建计划的入口，"
                "PopupMenuButton 配合 setState 提供简洁的删除体验。"
                "整个功能构成了一个完整的学习计划管理闭环，"
                "为用户提供清晰的学习路径引导和进度追踪能力。"
                "感谢观看，如有问题欢迎留言交流。"
            ),
            image_path=shots.get("plan_list"),
            image_caption="学习路径功能全貌回顾",
        ),
    ]


# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════
def main() -> None:
    FEAT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("  学习路径功能教学视频 v6")
    print("=" * 60)
    print(f"  工作目录：{FEAT_DIR}")
    print(f"  输出视频：{VIDEO_PATH}")
    print(f"  输出PPT：{PPTX_PATH}")
    print()

    # 1. 生成 UML 裁切图（公共架构图复用）
    print("[步骤 1/4] 生成 UML 裁切图...")
    crops = generate_uml_crops(CROPS_DIR)  # type: ignore[name-defined]
    print(f"  → 已生成 {len(crops)} 张裁切图")

    # 2. 生成功能特有 Mock 截图
    print("\n[步骤 2/4] 生成功能 Mock 截图...")
    shots = build_feature_shots(CROPS_DIR)
    print(f"  → 已生成 {len(shots)} 张功能截图")

    # 3. 构建幻灯片列表
    print("\n[步骤 3/4] 构建幻灯片列表...")
    slides = build_slides(crops, shots)
    print(f"  → 共 {len(slides)} 页幻灯片")
    for i, s in enumerate(slides, 1):
        print(f"     [{i:02d}] {s.title} — {s.subtitle[:45]}")

    # 4. 生成视频 / PPT / 脚本
    print("\n[步骤 4/4] 生成视频（edge_tts + moviepy）...")
    base_paths, ok = build_video(slides, FEAT_DIR, VIDEO_PATH, SRT_PATH)  # type: ignore[name-defined]

    build_pptx(slides, base_paths, PPTX_PATH)  # type: ignore[name-defined]
    build_script(slides, SCRIPT_PATH, "学习路径")  # type: ignore[name-defined]

    print()
    print("=" * 60)
    if ok and VIDEO_PATH.exists():
        size_mb = VIDEO_PATH.stat().st_size / 1024 / 1024
        # 估算视频时长：统计音频片段总数 × 平均时长
        audio_dir = FEAT_DIR / "audio"
        audio_files = list(audio_dir.glob("*.mp3")) + list(audio_dir.glob("*.wav"))
        try:
            from moviepy.editor import AudioFileClip as _AFC  # type: ignore[import]

            total_dur = sum(_AFC(str(f)).duration for f in audio_files if f.exists())
        except Exception:
            total_dur = 0.0
        mins = int(total_dur // 60)
        secs = int(total_dur % 60)
        print(f"  ✅ 视频生成成功！")
        print(f"  📹 Video : {VIDEO_PATH}")
        print(f"  📊 PPTX  : {PPTX_PATH}")
        print(f"  📝 Script: {SCRIPT_PATH}")
        print(f"  🔤 SRT   : {SRT_PATH}")
        print(f"  📦 大小  : {size_mb:.1f} MB")
        if total_dur > 0:
            print(f"  ⏱  时长  : {mins}分{secs:02d}秒  ({total_dur:.1f}s)")
        else:
            print(f"  ⏱  时长  : (请用播放器查看)")
    else:
        print("  ❌ 视频生成失败，请检查错误日志。")
        print(f"  📊 PPTX  : {PPTX_PATH}")
        print(f"  📝 Script: {SCRIPT_PATH}")
    print("=" * 60)


if __name__ == "__main__":
    main()
