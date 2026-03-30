#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_document_v6.py — 课程资料功能教学视频生成脚本

输出：
  video_output/课程资料功能教程_v6.mp4
  video_output/课程资料功能教程_v6.pptx

功能覆盖：
  DocumentListPage · PDF / PPT Tab · resource_files SQLite 表
  章节组织 · DatabaseHelper · 文件打开机制 · refresh 刷新
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from video_common_v6 import *  # noqa: F401, F403

# ═══════════════════════════════════════════════════════════════════════════
# PATHS
# ═══════════════════════════════════════════════════════════════════════════
FEAT_DIR = ROOT / "docs" / "video" / "feat_document"
VIDEO_PATH = OUT_DIR / "课程资料功能教程_v6.mp4"
PPTX_PATH = OUT_DIR / "课程资料功能教程_v6.pptx"
SRT_PATH = FEAT_DIR / "subtitles.srt"
SCRIPT_PATH = FEAT_DIR / "script.md"
CROPS_DIR = FEAT_DIR / "crops"


# ═══════════════════════════════════════════════════════════════════════════
# MOCK FEATURE SCREENSHOTS
# ═══════════════════════════════════════════════════════════════════════════
def build_feature_shots(crops_dir: Path) -> dict[str, Path]:
    """生成课程资料功能的 Mock 运行截图。"""
    shots: dict[str, Path] = {}

    # ── PDF 文档列表页 ──────────────────────────────────────────────────
    shots["doc_list"] = mock_page(
        "DocumentListPage  课程资料",
        "PDF文档 & PPT课件 · Tab切换 · 章节组织",
        ["PDF文档", "PPT课件", "章节列表"],
        [
            (
                "第一章 移动应用开发技术体系1.pdf",
                "PDF课件 · assets/课件/清言智谱/第一章移动应用开发技术体系1.pdf",
                PRIMARY,
            ),
            (
                "第二章 原生开发基础1.pdf",
                "PDF课件 · assets/课件/清言智谱/第二章原生开发基础1.pdf",
                GREEN,
            ),
            (
                "第三章 混合开发技术1.pdf",
                "PDF课件 · assets/课件/清言智谱/第三章混合开发技术1.pdf",
                ORANGE,
            ),
            (
                "第四章 小程序开发1.pdf",
                "PDF课件 · assets/课件/清言智谱/第四章小程序开发1.pdf",
                PURPLE,
            ),
        ],
        crops_dir / "mock_doc_list.png",
    )

    # ── PPT 课件列表页 ──────────────────────────────────────────────────
    shots["ppt_list"] = mock_page(
        "PPT课件列表",
        "PPT课件 · 秒出PPT生成 · 章节对应",
        ["PPT课件", "章节匹配", "一键查看"],
        [
            (
                "第一章 移动应用开发技术体系1.pptx",
                "PPT课件 · assets/课件/秒出PPT/第一章移动应用开发技术体系1.pptx",
                PRIMARY,
            ),
            (
                "第二章 原生开发基础1.pptx",
                "PPT课件 · assets/课件/秒出PPT/第二章原生开发基础1.pptx",
                GREEN,
            ),
            (
                "第三章 混合开发技术1.pptx",
                "PPT课件 · assets/课件/秒出PPT/第三章混合开发技术1.pptx",
                ORANGE,
            ),
            (
                "第四章 小程序开发1.pptx",
                "PPT课件 · assets/课件/秒出PPT/第四章小程序开发1.pptx",
                PURPLE,
            ),
        ],
        crops_dir / "mock_ppt_list.png",
    )

    # ── resource_files 数据表结构 ────────────────────────────────────────
    shots["db_resource"] = mock_page(
        "resource_files  数据表",
        "SQLite 资源表 · 统一存储 PDF 和 PPT 记录",
        ["SQLite", "resource_files", "统一管理"],
        [
            ("file_name", "文件名：如 第一章移动应用开发技术体系1.pdf", PRIMARY),
            (
                "file_path",
                "文件路径：assets/课件/清言智谱/xxx.pdf  或  assets/课件/秒出PPT/xxx.pptx",
                GREEN,
            ),
            (
                "file_type",
                "类型标识：'pdf' → PDF文档列表 | 'ppt' → PPT课件列表",
                ORANGE,
            ),
            (
                "chapter / description",
                "chapter：章节名称用于分组显示 · description：课件摘要说明",
                PURPLE,
            ),
        ],
        crops_dir / "mock_db_resource.png",
    )

    # ── 章节组织方式 ─────────────────────────────────────────────────────
    shots["chapters"] = mock_page(
        "六章课程资料  章节组织",
        "6章 · 每章多节 · PDF+PPT 双份资料",
        ["第一章", "第二章", "第三章", "第四章", "第五章", "第六章"],
        [
            (
                "第一章 移动应用开发技术体系",
                "总览移动开发全景：原生 / 混合 / 小程序 / 跨平台技术对比",
                PRIMARY,
            ),
            (
                "第二章 原生开发基础  &  第三章 混合开发技术",
                "Android/iOS 原生基础 → Flutter/RN/Weex 混合方案对比",
                GREEN,
            ),
            (
                "第四章 小程序开发  &  第五章 华为多端应用开发",
                "微信小程序开发流程 → 华为 HarmonyOS 多端方案",
                ORANGE,
            ),
            (
                "第六章 综合开发实践",
                "跨平台综合项目实战，知识图谱系统完整构建过程",
                PURPLE,
            ),
        ],
        crops_dir / "mock_chapters.png",
    )

    # ── 文件打开机制 ─────────────────────────────────────────────────────
    shots["open_doc"] = mock_page(
        "_openDocument()  文件打开机制",
        "点击课件 → SnackBar 显示路径 → 平台处理打开",
        ["SnackBar提示", "路径展示", "平台打开"],
        [
            (
                "点击 ListTile",
                "用户点击任意 PDF / PPT 列表项，触发 _openDocument(file) 方法",
                PRIMARY,
            ),
            (
                "SnackBar 显示",
                "ScaffoldMessenger.showSnackBar 展示文件路径，反馈用户操作",
                GREEN,
            ),
            (
                "平台文件处理",
                "实际文件打开由操作系统平台处理，支持 Android / iOS / Windows",
                ORANGE,
            ),
        ],
        crops_dir / "mock_open_doc.png",
    )

    # ── DatabaseHelper 作用 ──────────────────────────────────────────────
    shots["db_helper"] = mock_page(
        "DatabaseHelper  单例模式",
        "统一管理 SQLite 连接 · 初始化数据 · 提供查询接口",
        ["单例", "SQLite", "初始化"],
        [
            (
                "DatabaseHelper.instance",
                "全局单例，整个 App 共享一个 SQLite 连接，避免重复打开数据库",
                PRIMARY,
            ),
            (
                "_initDatabase() / _onCreate()",
                "首次运行建表并插入预置数据，后续直接复用已有数据库",
                GREEN,
            ),
            (
                "getResourceFiles(type)",
                "按 file_type 查询 resource_files 表，返回 PDF 或 PPT 列表给页面",
                ORANGE,
            ),
        ],
        crops_dir / "mock_db_helper.png",
    )

    # ── refresh 按钮 ─────────────────────────────────────────────────────
    shots["refresh"] = mock_page(
        "AppBar  refresh 刷新按钮",
        "重新从数据库加载资源列表，确保数据最新",
        ["AppBar", "IconButton", "重新加载"],
        [
            (
                "IconButton(icon: Icon(Icons.refresh))",
                "AppBar 右侧刷新按钮，点击后重新执行 _loadResources()",
                PRIMARY,
            ),
            (
                "_loadResources()",
                "调用 DatabaseHelper.instance.getResourceFiles() 重新查询 SQLite",
                GREEN,
            ),
            (
                "setState()",
                "查询结果通过 setState 刷新 _pdfList / _pptList，页面立即更新",
                ORANGE,
            ),
        ],
        crops_dir / "mock_refresh.png",
    )

    return shots


# ═══════════════════════════════════════════════════════════════════════════
# SLIDES DEFINITION  (14 slides)
# ═══════════════════════════════════════════════════════════════════════════
def build_slides(
    crops: dict[str, Path],
    shots: dict[str, Path],
) -> list[SlideSpec]:
    return [
        # 01 ── 课程导入 ─────────────────────────────────────────────────
        SlideSpec(
            title="课程导入",
            subtitle="课程资料功能 — PDF 与 PPT 课件统一管理与浏览",
            bullets=[
                "PDF 文档管理",
                "PPT 课件管理",
                "章节组织",
                "SQLite 存储",
                "文件打开机制",
            ],
            narration=(
                "欢迎进入课程资料功能教学视频。"
                "课程资料功能为用户提供 PDF 文档和 PPT 课件的统一管理与浏览入口。"
                "所有课件资源按章节组织，存储在本地 SQLite 数据库中，通过 Tab 切换轻松在 PDF 和 PPT 之间导航。"
                "本视频将依次介绍 Tab 设计、数据库表结构、章节组织方式、数据初始化流程以及文件打开机制。"
            ),
            voice_segments=[
                "欢迎进入课程资料功能教学视频。",
                "课程资料功能为用户提供 PDF 文档和 PPT 课件的统一管理与浏览入口。",
                "所有课件资源按章节组织，存储在本地 SQLite 数据库中，",
                "通过 Tab 切换可以轻松在 PDF 和 PPT 之间导航。",
                "本视频将依次介绍 Tab 设计、数据库表结构、章节组织方式、数据初始化流程以及文件打开机制。",
            ],
            image_path=crops.get("framework_full"),
        ),
        # 02 ── 功能架构总览 ─────────────────────────────────────────────
        SlideSpec(
            title="功能架构总览",
            subtitle="DocumentListPage 在整体系统中的位置与职责",
            bullets=[
                "DocumentListPage 课程资料页",
                "TabBar 双 Tab 切换",
                "数据层：SQLite resource_files 表",
                "DatabaseHelper 统一管理",
                "属于学习资料子系统",
            ],
            narration=(
                "在整个知识图谱系统中，课程资料功能由 DocumentListPage 承载。"
                "它通过 TabBar 将 PDF 文档与 PPT 课件分开展示，背后的数据来自 SQLite 的 resource_files 表。"
                "DatabaseHelper 单例负责统一管理数据库连接和数据查询。"
                "从架构角度看，DocumentListPage 属于学习资料子系统，与视频、测验等页面共同构成完整的学习资源中心。"
            ),
            voice_segments=[
                "在整个知识图谱系统中，课程资料功能由 DocumentListPage 承载。",
                "它通过 TabBar 将 PDF 文档与 PPT 课件分开展示，",
                "背后的数据来自 SQLite 的 resource_files 表。",
                "DatabaseHelper 单例负责统一管理数据库连接和数据查询。",
                "从架构角度看，DocumentListPage 属于学习资料子系统，",
                "与视频、测验等页面共同构成完整的学习资源中心。",
            ],
            image_path=crops.get("framework_full"),
        ),
        # 03 ── Tab 设计 ─────────────────────────────────────────────────
        SlideSpec(
            title="Tab 设计",
            subtitle="PDF文档 / PPT课件 双 Tab · DefaultTabController · TabBarView",
            bullets=[
                "DefaultTabController(length: 2)",
                "TabBar：PDF文档 | PPT课件",
                "TabBarView 对应两个列表",
                "_pdfList / _pptList 分别维护",
                "切换 Tab 无需重新查询数据库",
            ],
            narration=(
                "DocumentListPage 使用 Flutter 的 DefaultTabController 实现双 Tab 切换。"
                "AppBar 底部放置 TabBar，包含『PDF文档』和『PPT课件』两个 Tab。"
                "页面初始化时同时加载两份数据，分别存入 _pdfList 和 _pptList。"
                "TabBarView 负责在两个 Tab 之间切换内容区域，用户切换 Tab 时无需再次查询数据库，体验流畅。"
            ),
            voice_segments=[
                "DocumentListPage 使用 Flutter 的 DefaultTabController 实现双 Tab 切换。",
                "AppBar 底部放置 TabBar，包含 PDF文档 和 PPT课件 两个 Tab。",
                "页面初始化时同时加载两份数据，分别存入 _pdfList 和 _pptList。",
                "TabBarView 负责在两个 Tab 之间切换内容区域，",
                "用户切换 Tab 时无需再次查询数据库，体验流畅。",
            ],
            image_path=shots.get("doc_list"),
            code_title="Tab 结构代码",
            code_text="""\
DefaultTabController(
  length: 2,
  child: Scaffold(
    appBar: AppBar(
      title: Text('课程资料'),
      bottom: TabBar(tabs: [
        Tab(text: 'PDF文档'),
        Tab(text: 'PPT课件'),
      ]),
    ),
    body: TabBarView(children: [
      _buildList(_pdfList),
      _buildList(_pptList),
    ]),
  ),
)""",
        ),
        # 04 ── SQLite resource_files 表结构 ────────────────────────────
        SlideSpec(
            title="resource_files 数据表结构",
            subtitle="SQLite 本地表 · 统一存储 PDF 与 PPT 资源记录",
            bullets=[
                "表名：resource_files",
                "file_name — 文件显示名称",
                "file_path — assets 相对路径",
                "file_type — 'pdf' 或 'ppt'",
                "chapter — 所属章节名称",
                "description — 课件摘要说明",
            ],
            narration=(
                "课程资料的核心数据存储在 SQLite 的 resource_files 表中。"
                "该表包含六个关键字段：file_name 存储文件的显示名称，file_path 存储 assets 目录下的完整相对路径，"
                "file_type 用字符串 'pdf' 或 'ppt' 区分资源类型，chapter 存储所属章节名称用于分组，"
                "description 存储课件的摘要说明。"
                "页面通过 file_type 字段过滤，分别查询 PDF 列表和 PPT 列表。"
            ),
            voice_segments=[
                "课程资料的核心数据存储在 SQLite 的 resource_files 表中。",
                "该表包含六个关键字段：",
                "file_name 存储文件的显示名称，",
                "file_path 存储 assets 目录下的完整相对路径，",
                "file_type 用字符串 'pdf' 或 'ppt' 区分资源类型，",
                "chapter 存储所属章节名称用于分组，",
                "description 存储课件的摘要说明。",
                "页面通过 file_type 字段过滤，分别查询 PDF 列表和 PPT 列表。",
            ],
            image_path=shots.get("db_resource"),
            code_title="建表 SQL",
            code_text="""\
CREATE TABLE resource_files (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  file_name   TEXT NOT NULL,
  file_path   TEXT NOT NULL,
  file_type   TEXT NOT NULL,  -- 'pdf' | 'ppt'
  chapter     TEXT,
  description TEXT
);""",
        ),
        # 05 ── PDF 文档列表 ──────────────────────────────────────────────
        SlideSpec(
            title="PDF 文档列表",
            subtitle="清言智谱生成 · file_type='pdf' · 每章对应多节 PDF",
            bullets=[
                "数据源：file_type = 'pdf'",
                "资源路径：assets/课件/清言智谱/",
                "共约 15 个 PDF 文件",
                "涵盖 6 章全部内容",
                "ListView 展示，点击触发打开",
            ],
            narration=(
                "PDF 文档列表展示所有 file_type 为 'pdf' 的资源记录。"
                "这些课件由清言智谱 AI 生成，存放在 assets 目录下的『清言智谱』子文件夹中。"
                "文件命名遵循『第X章课件名称.pdf』的格式，共约 15 个 PDF 文件，覆盖全部六章内容。"
                "列表使用 ListView 展示，每一项显示文件名和章节信息，用户点击即可触发打开操作。"
            ),
            voice_segments=[
                "PDF 文档列表展示所有 file_type 为 'pdf' 的资源记录。",
                "这些课件由清言智谱 AI 生成，",
                "存放在 assets 目录下的『清言智谱』子文件夹中。",
                "文件命名遵循『第X章课件名称.pdf』的格式，",
                "共约 15 个 PDF 文件，覆盖全部六章内容。",
                "列表使用 ListView 展示，每一项显示文件名和章节信息，",
                "用户点击即可触发打开操作。",
            ],
            image_path=shots.get("doc_list"),
            code_title="查询 PDF 列表",
            code_text="""\
// DatabaseHelper 查询
final List<Map> rows = await db.query(
  'resource_files',
  where: 'file_type = ?',
  whereArgs: ['pdf'],
  orderBy: 'chapter ASC',
);
setState(() {
  _pdfList = rows.map((r) => ResourceFile.fromMap(r)).toList();
});""",
        ),
        # 06 ── PPT 课件列表 ──────────────────────────────────────────────
        SlideSpec(
            title="PPT 课件列表",
            subtitle="秒出PPT生成 · file_type='ppt' · 与 PDF 章节一一对应",
            bullets=[
                "数据源：file_type = 'ppt'",
                "资源路径：assets/课件/秒出PPT/",
                "共约 15 个 .pptx 文件",
                "每章 PDF 对应一套 PPT",
                "Tab 切换即时呈现",
            ],
            narration=(
                "PPT 课件列表展示所有 file_type 为 'ppt' 的资源记录。"
                "这些课件由秒出 PPT 工具生成，存放在 assets 目录下的『秒出PPT』子文件夹中，格式为 pptx。"
                "每章的 PDF 课件都对应一套 PPT 课件，形成一一对应的双线资料体系。"
                "用户在 PDF 文档 Tab 中浏览后，切换到 PPT 课件 Tab 即可查看对应的演示文稿。"
            ),
            voice_segments=[
                "PPT 课件列表展示所有 file_type 为 'ppt' 的资源记录。",
                "这些课件由秒出 PPT 工具生成，",
                "存放在 assets 目录下的『秒出PPT』子文件夹中，格式为 pptx。",
                "每章的 PDF 课件都对应一套 PPT 课件，",
                "形成一一对应的双线资料体系。",
                "用户在 PDF 文档 Tab 中浏览后，",
                "切换到 PPT 课件 Tab 即可查看对应的演示文稿。",
            ],
            image_path=shots.get("ppt_list"),
            code_title="资源路径规范",
            code_text="""\
// PDF 路径
assets/课件/清言智谱/第一章移动应用开发技术体系1.pdf

// PPT 路径
assets/课件/秒出PPT/第一章移动应用开发技术体系1.pptx

// pubspec.yaml 声明
assets:
  - assets/课件/清言智谱/
  - assets/课件/秒出PPT/""",
        ),
        # 07 ── 章节组织方式 ──────────────────────────────────────────────
        SlideSpec(
            title="章节组织方式",
            subtitle="六章课程 · 每章多节 · chapter 字段分组显示",
            bullets=[
                "第一章 移动应用开发技术体系",
                "第二章 原生开发基础",
                "第三章 混合开发技术",
                "第四章 小程序开发",
                "第五章 华为多端应用开发",
                "第六章 综合开发实践",
            ],
            narration=(
                "课程资料按照六章内容组织。"
                "第一章介绍移动应用开发技术体系全景；第二章讲解 Android 与 iOS 原生开发基础；"
                "第三章对比 Flutter、React Native 等混合开发技术；"
                "第四章深入微信小程序开发流程；第五章聚焦华为 HarmonyOS 多端应用开发；"
                "第六章通过综合开发实践将前五章知识融会贯通。"
                "resource_files 表的 chapter 字段记录每个文件所属章节，供页面分组显示使用。"
            ),
            voice_segments=[
                "课程资料按照六章内容组织。",
                "第一章介绍移动应用开发技术体系全景；",
                "第二章讲解 Android 与 iOS 原生开发基础；",
                "第三章对比 Flutter、React Native 等混合开发技术；",
                "第四章深入微信小程序开发流程；",
                "第五章聚焦华为 HarmonyOS 多端应用开发；",
                "第六章通过综合开发实践将前五章知识融会贯通。",
                "resource_files 表的 chapter 字段记录每个文件所属章节，供页面分组显示使用。",
            ],
            image_path=shots.get("chapters"),
        ),
        # 08 ── 数据初始化流程 ────────────────────────────────────────────
        SlideSpec(
            title="数据初始化流程",
            subtitle="App 首次启动 · _onCreate 建表 · 预置数据插入",
            bullets=[
                "App 启动 → openDatabase()",
                "_onCreate 回调建表",
                "循环插入预置资源记录",
                "PDF 约 15 条 · PPT 约 15 条",
                "后续直接复用，无需重复初始化",
            ],
            narration=(
                "App 首次安装运行时，DatabaseHelper 调用 openDatabase 打开 SQLite 数据库。"
                "数据库不存在时触发 _onCreate 回调，在此处创建 resource_files 表并插入预置的课件数据。"
                "预置数据包含约 15 条 PDF 记录和 15 条 PPT 记录，对应六章所有课件。"
                "之后每次启动 App，数据库已存在，直接复用数据，不会重复插入，保证数据一致性。"
            ),
            voice_segments=[
                "App 首次安装运行时，DatabaseHelper 调用 openDatabase 打开 SQLite 数据库。",
                "数据库不存在时触发 _onCreate 回调，",
                "在此处创建 resource_files 表并插入预置的课件数据。",
                "预置数据包含约 15 条 PDF 记录和 15 条 PPT 记录，对应六章所有课件。",
                "之后每次启动 App，数据库已存在，直接复用数据，",
                "不会重复插入，保证数据一致性。",
            ],
            image_path=shots.get("db_helper"),
            code_title="初始化流程",
            code_text="""\
Future<Database> _initDatabase() async {
  final dbPath = await getDatabasesPath();
  return openDatabase(
    join(dbPath, 'knowledge_graph.db'),
    onCreate: (db, version) async {
      await db.execute(_createResourceTable);
      for (final row in _seedResources) {
        await db.insert('resource_files', row);
      }
    },
    version: 1,
  );
}""",
        ),
        # 09 ── DatabaseHelper 单例 ───────────────────────────────────────
        SlideSpec(
            title="DatabaseHelper 单例模式",
            subtitle="全局唯一数据库连接 · instance 静态访问 · 懒初始化",
            bullets=[
                "DatabaseHelper._internal() 私有构造",
                "static final instance 单例",
                "get database 懒初始化",
                "getResourceFiles(type) 按类型查询",
                "所有页面共享同一连接",
            ],
            narration=(
                "DatabaseHelper 采用 Dart 单例模式，确保整个 App 只有一个 SQLite 数据库连接。"
                "通过私有构造函数 _internal 和静态 instance 字段实现单例访问。"
                "database getter 采用懒初始化策略，第一次访问时才真正打开数据库。"
                "对外暴露的 getResourceFiles 方法接收 type 参数，按 file_type 字段查询并返回对应列表。"
                "DocumentListPage 和其他所有页面都通过 DatabaseHelper.instance 统一访问数据层。"
            ),
            voice_segments=[
                "DatabaseHelper 采用 Dart 单例模式，",
                "确保整个 App 只有一个 SQLite 数据库连接。",
                "通过私有构造函数 _internal 和静态 instance 字段实现单例访问。",
                "database getter 采用懒初始化策略，第一次访问时才真正打开数据库。",
                "对外暴露的 getResourceFiles 方法接收 type 参数，",
                "按 file_type 字段查询并返回对应列表。",
                "DocumentListPage 和其他所有页面都通过 DatabaseHelper.instance 统一访问数据层。",
            ],
            image_path=shots.get("db_helper"),
            code_title="单例实现",
            code_text="""\
class DatabaseHelper {
  static final DatabaseHelper instance =
      DatabaseHelper._internal();
  DatabaseHelper._internal();

  Database? _db;
  Future<Database> get database async =>
      _db ??= await _initDatabase();

  Future<List<Map>> getResourceFiles(String type) async {
    final db = await database;
    return db.query('resource_files',
        where: 'file_type = ?', whereArgs: [type]);
  }
}""",
        ),
        # 10 ── 文件打开机制 ──────────────────────────────────────────────
        SlideSpec(
            title="文件打开机制",
            subtitle="_openDocument() · SnackBar 路径提示 · 平台文件处理",
            bullets=[
                "点击 ListTile → _openDocument(file)",
                "ScaffoldMessenger.showSnackBar",
                "SnackBar 显示完整 file_path",
                "实际打开由平台处理",
                "支持 Android / iOS / Windows",
            ],
            narration=(
                "当用户点击课件列表中的任意一项时，页面调用 _openDocument 方法。"
                "该方法首先通过 ScaffoldMessenger 弹出 SnackBar，将文件的完整 assets 路径显示给用户，作为即时反馈。"
                "实际的文件打开操作由底层平台处理，可以调用 open_file 等插件将文件交给系统默认程序打开。"
                "这种设计将 UI 反馈与平台能力解耦，便于后续扩展真实的文件打开逻辑。"
            ),
            voice_segments=[
                "当用户点击课件列表中的任意一项时，页面调用 _openDocument 方法。",
                "该方法首先通过 ScaffoldMessenger 弹出 SnackBar，",
                "将文件的完整 assets 路径显示给用户，作为即时反馈。",
                "实际的文件打开操作由底层平台处理，",
                "可以调用 open_file 等插件将文件交给系统默认程序打开。",
                "这种设计将 UI 反馈与平台能力解耦，便于后续扩展真实的文件打开逻辑。",
            ],
            image_path=shots.get("open_doc"),
            code_title="_openDocument 实现",
            code_text=r"""
void _openDocument(ResourceFile file) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('打开文件: ${file.filePath}'),
      duration: Duration(seconds: 2),
    ),
  );
  // 实际文件打开由平台处理
  // OpenFile.open(file.filePath);
}""",
        ),
        # 11 ── AppBar refresh 按钮 ───────────────────────────────────────
        SlideSpec(
            title="AppBar Refresh 刷新按钮",
            subtitle="重新从 SQLite 加载 · setState 驱动视图更新",
            bullets=[
                "AppBar actions: [IconButton(refresh)]",
                "点击 → _loadResources() 重新查询",
                "setState 更新 _pdfList / _pptList",
                "适用场景：数据变更后手动刷新",
                "与初始化逻辑复用同一查询方法",
            ],
            narration=(
                "AppBar 右侧提供一个刷新图标按钮，让用户可以手动重新加载课件数据。"
                "点击刷新按钮会再次调用 _loadResources 方法，重新向 DatabaseHelper 发起查询。"
                "查询完成后通过 setState 更新 _pdfList 和 _pptList，Flutter 框架自动触发页面重建，列表即时刷新。"
                "刷新功能与页面初始化复用同一套查询逻辑，代码简洁且易于维护。"
            ),
            voice_segments=[
                "AppBar 右侧提供一个刷新图标按钮，让用户可以手动重新加载课件数据。",
                "点击刷新按钮会再次调用 _loadResources 方法，",
                "重新向 DatabaseHelper 发起查询。",
                "查询完成后通过 setState 更新 _pdfList 和 _pptList，",
                "Flutter 框架自动触发页面重建，列表即时刷新。",
                "刷新功能与页面初始化复用同一套查询逻辑，代码简洁且易于维护。",
            ],
            image_path=shots.get("refresh"),
            code_title="refresh 按钮实现",
            code_text="""\
AppBar(
  title: Text('课程资料'),
  actions: [
    IconButton(
      icon: Icon(Icons.refresh),
      onPressed: _loadResources,
      tooltip: '刷新列表',
    ),
  ],
  bottom: TabBar(...),
)

Future<void> _loadResources() async {
  final db = DatabaseHelper.instance;
  final pdf = await db.getResourceFiles('pdf');
  final ppt = await db.getResourceFiles('ppt');
  setState(() {
    _pdfList = pdf.map(ResourceFile.fromMap).toList();
    _pptList = ppt.map(ResourceFile.fromMap).toList();
  });
}""",
        ),
        # 12 ── 完整数据流 ────────────────────────────────────────────────
        SlideSpec(
            title="完整数据流总览",
            subtitle="从 initState 到 ListView 渲染的全链路",
            bullets=[
                "initState() → _loadResources()",
                "DatabaseHelper.instance.getResourceFiles()",
                "SQLite 查询 resource_files 表",
                "setState 更新列表状态",
                "TabBarView → ListView → ListTile",
            ],
            narration=(
                "整个课程资料功能的数据流可以分为五个环节。"
                "第一步，页面初始化时 initState 调用 _loadResources；"
                "第二步，_loadResources 通过 DatabaseHelper.instance 发起数据库查询；"
                "第三步，SQLite 按 file_type 过滤 resource_files 表并返回结果；"
                "第四步，查询结果通过 setState 写入 _pdfList 和 _pptList；"
                "第五步，Flutter 重建 TabBarView 下的 ListView，每条记录渲染为一个 ListTile。"
                "整条链路清晰简洁，各层职责边界分明。"
            ),
            voice_segments=[
                "整个课程资料功能的数据流可以分为五个环节。",
                "第一步，页面初始化时 initState 调用 _loadResources；",
                "第二步，_loadResources 通过 DatabaseHelper.instance 发起数据库查询；",
                "第三步，SQLite 按 file_type 过滤 resource_files 表并返回结果；",
                "第四步，查询结果通过 setState 写入 _pdfList 和 _pptList；",
                "第五步，Flutter 重建 TabBarView 下的 ListView，每条记录渲染为一个 ListTile。",
                "整条链路清晰简洁，各层职责边界分明。",
            ],
            image_path=crops.get("framework_dao"),
            code_title="数据流核心链路",
            code_text="""\
// 1. initState
void initState() {
  super.initState();
  _loadResources();      // 触发查询

// 2. 查询
final pdf = await db.getResourceFiles('pdf');

// 3. SQLite
SELECT * FROM resource_files WHERE file_type='pdf'

// 4. 更新状态
setState(() { _pdfList = ...; });

// 5. 渲染
ListView.builder(itemBuilder: (_, i) =>
  ListTile(title: Text(_pdfList[i].fileName)))""",
        ),
        # 13 ── 功能测试要点 ──────────────────────────────────────────────
        SlideSpec(
            title="功能测试要点",
            subtitle="Tab 切换 · 数据加载 · SnackBar 验证 · refresh 验证",
            bullets=[
                "PDF Tab 列表条数验证",
                "PPT Tab 列表条数验证",
                "Tab 切换无数据丢失",
                "点击文件 → SnackBar 路径正确",
                "refresh 按钮重新加载正常",
            ],
            narration=(
                "对课程资料功能进行测试时，需要关注以下几个核心场景。"
                "首先验证 PDF Tab 能正确显示约 15 条 PDF 记录，PPT Tab 能正确显示约 15 条 PPT 记录。"
                "其次测试 Tab 切换时两份数据均保持完整，不发生混淆或丢失。"
                "然后点击任意文件，确认 SnackBar 弹出并显示正确的 assets 路径。"
                "最后验证 AppBar 的 refresh 按钮点击后能正确触发重新加载，数据不重复不丢失。"
            ),
            voice_segments=[
                "对课程资料功能进行测试时，需要关注以下几个核心场景。",
                "首先验证 PDF Tab 能正确显示约 15 条 PDF 记录，",
                "PPT Tab 能正确显示约 15 条 PPT 记录。",
                "其次测试 Tab 切换时两份数据均保持完整，不发生混淆或丢失。",
                "然后点击任意文件，确认 SnackBar 弹出并显示正确的 assets 路径。",
                "最后验证 AppBar 的 refresh 按钮点击后能正确触发重新加载，",
                "数据不重复不丢失。",
            ],
            image_path=crops.get("sequence_full"),
        ),
        # 14 ── 总结与回顾 ────────────────────────────────────────────────
        SlideSpec(
            title="总结与回顾",
            subtitle="课程资料功能设计要点 · 最佳实践 · 后续扩展方向",
            bullets=[
                "TabBar 实现 PDF / PPT 双入口",
                "resource_files 表统一存储资源",
                "DatabaseHelper 单例管理连接",
                "file_type 字段实现资源分类",
                "章节组织提升浏览体验",
                "后续可扩展真实文件打开能力",
            ],
            narration=(
                "本视频完整介绍了课程资料功能的实现原理。"
                "设计亮点在于用 TabBar 清晰分离 PDF 和 PPT 两类资源，用 resource_files 表统一管理所有课件记录。"
                "DatabaseHelper 单例保证数据库访问的唯一性和一致性，file_type 字段让页面查询和渲染逻辑极为简洁。"
                "chapter 字段为未来按章节分组显示留下了扩展空间。"
                "后续可以进一步集成 open_file 插件，实现真实的文件打开能力。"
                "感谢收看，欢迎继续学习其他功能模块。"
            ),
            voice_segments=[
                "本视频完整介绍了课程资料功能的实现原理。",
                "设计亮点在于用 TabBar 清晰分离 PDF 和 PPT 两类资源，",
                "用 resource_files 表统一管理所有课件记录。",
                "DatabaseHelper 单例保证数据库访问的唯一性和一致性，",
                "file_type 字段让页面查询和渲染逻辑极为简洁。",
                "chapter 字段为未来按章节分组显示留下了扩展空间。",
                "后续可以进一步集成 open_file 插件，实现真实的文件打开能力。",
                "感谢收看，欢迎继续学习其他功能模块。",
            ],
            image_path=crops.get("framework_full"),
        ),
    ]


# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════
def main() -> None:
    print("=" * 62)
    print("  课程资料功能教学视频生成器  v6")
    print("=" * 62)

    # 确保工作目录存在
    FEAT_DIR.mkdir(parents=True, exist_ok=True)
    CROPS_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"\n[1/4] 生成 UML 裁切图  →  {CROPS_DIR}")
    crops = generate_uml_crops(CROPS_DIR)

    print(f"\n[2/4] 生成 Mock 运行截图  →  {CROPS_DIR}")
    shots = build_feature_shots(CROPS_DIR)

    print(f"\n[3/4] 构建 Slides 规格  (目标 14 slides)")
    slides = build_slides(crops, shots)
    print(f"      共 {len(slides)} slides")

    print(f"\n[4/4] 视频生成流水线  →  {VIDEO_PATH}")
    base_paths, ok = build_video(slides, FEAT_DIR, VIDEO_PATH, SRT_PATH)

    # PPTX
    build_pptx(slides, base_paths, PPTX_PATH)

    # 讲解脚本
    build_script(slides, SCRIPT_PATH, "课程资料")

    # 计算视频时长
    duration_str = "unknown"
    if ok and VIDEO_PATH.exists():
        try:
            from moviepy.editor import VideoFileClip  # noqa: PLC0415

            vc = VideoFileClip(str(VIDEO_PATH))
            total_sec = vc.duration
            vc.close()
            m = int(total_sec // 60)
            s = int(total_sec % 60)
            duration_str = f"{m}分{s:02d}秒 ({total_sec:.1f}s)"
        except Exception:
            size_mb = VIDEO_PATH.stat().st_size / 1_048_576
            duration_str = f"文件大小 {size_mb:.1f} MB（时长读取失败）"

    print("\n" + "=" * 62)
    print("  生成完成" if ok else "  生成失败（见上方错误信息）")
    print("=" * 62)
    print(f"  Video  : {VIDEO_PATH}")
    print(f"  PPTX   : {PPTX_PATH}")
    print(f"  SRT    : {SRT_PATH}")
    print(f"  Script : {SCRIPT_PATH}")
    print(f"  时长   : {duration_str}")
    print(f"  Slides : {len(slides)} 页")
    print("=" * 62)


if __name__ == "__main__":
    main()
