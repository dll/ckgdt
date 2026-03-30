#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_video_player_v6.py — VideoListPage 视频播放功能教学视频生成器

功能说明
--------
VideoListPage 真实实现：
  - 从 SQLite resource_files 表加载 file_type='video' 的记录
  - 数据库为空时自动插入 15 条视频资源（6 章）
  - ListView 红色圆形图标 + 章节名 + 点击播放
  - 点击 → _playVideo() → SnackBar 显示文件路径
  - AppBar refresh 按钮重新加载
  - DatabaseHelper.instance 统一管理 SQLite

输出
----
  video_output/视频播放功能教程_v6.mp4
  video_output/视频播放功能教程_v6.pptx
  docs/video/feat_video_player/script.md
  docs/video/feat_video_player/subtitles.srt
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from video_common_v6 import *

# ── 路径常量 ──────────────────────────────────────────────────────────────
FEAT_DIR = ROOT / "docs" / "video" / "feat_video_player"
VIDEO_PATH = OUT_DIR / "视频播放功能教程_v6.mp4"
PPTX_PATH = OUT_DIR / "视频播放功能教程_v6.pptx"
SRT_PATH = FEAT_DIR / "subtitles.srt"
SCRIPT_PATH = FEAT_DIR / "script.md"
CROPS_DIR = FEAT_DIR / "crops"


# ═══════════════════════════════════════════════════════════════════════════
# MOCK FEATURE SCREENSHOTS
# ═══════════════════════════════════════════════════════════════════════════
def build_feature_shots(crops_dir: Path) -> dict[str, Path]:
    shots: dict[str, Path] = {}

    # ── Mock 1: VideoListPage 主界面 ──────────────────────────────────────
    shots["video_list"] = mock_page(
        "VideoListPage  视频播放",
        "课程视频教程列表 · 章节组织 · 一键播放",
        ["视频教程", "章节列表", "播放"],
        [
            (
                "第一章 移动应用开发技术体系1",
                "点击播放 · assets/第一章移动应用开发技术体系1.mp4",
                RED_C,
            ),
            (
                "第二章 原生开发基础1",
                "点击播放 · assets/第二章原生开发基础1.mp4",
                RED_C,
            ),
            (
                "第三章 混合开发技术1",
                "点击播放 · assets/第三章混合开发技术1.mp4",
                RED_C,
            ),
            (
                "第四章 小程序开发1",
                "点击播放 · assets/第四章小程序开发1.mp4",
                RED_C,
            ),
        ],
        crops_dir / "mock_video_list.png",
    )

    # ── Mock 2: 课程章节总览 ──────────────────────────────────────────────
    shots["video_chapters"] = mock_page(
        "课程章节视频资源",
        "6 章共 15 个视频 · 按章节有序组织",
        ["第一章", "第二章", "第三章", "第四章", "第五章", "第六章"],
        [
            ("第一章 移动应用开发技术体系", "2 个视频：技术体系1 / 技术体系2", PRIMARY),
            ("第三章 混合开发技术", "3 个视频：混合开发技术1/2/3", GREEN),
            ("第五章 华为多端应用开发", "3 个视频：华为多端应用开发1/2/3", ORANGE),
            ("第六章 综合开发实践", "3 个视频：综合开发实践1/2/3", PURPLE),
        ],
        crops_dir / "mock_video_chapters.png",
    )

    # ── Mock 3: SQLite resource_files 表结构 ──────────────────────────────
    shots["db_video"] = mock_page(
        "resource_files 视频记录",
        "SQLite 存储视频元数据 · 首次启动自动初始化",
        ["SQLite", "自动初始化", "资源管理"],
        [
            ("file_type = 'video'", "标识该条记录为视频资源，与文档资源区分", PRIMARY),
            ("chapter", "章节名称，用于 ListView 标题显示", GREEN),
            ("file_path", "资产路径 assets/xxx.mp4，传给平台播放器", ORANGE),
            ("title", "视频标题，显示在列表项主文字区域", PURPLE),
        ],
        crops_dir / "mock_db_video.png",
    )

    # ── Mock 4: 自动初始化流程 ────────────────────────────────────────────
    shots["auto_init"] = mock_page(
        "自动初始化视频数据",
        "数据库为空时自动插入 15 条视频记录",
        ["空库检测", "自动插入", "15条记录"],
        [
            (
                "① 查询 resource_files WHERE file_type='video'",
                "count=0 → 触发自动初始化",
                PRIMARY,
            ),
            (
                "② _initVideoData() 构建 List<Map> 共 15 条",
                "按章节分组批量 insert",
                GREEN,
            ),
            (
                "③ DatabaseHelper.instance.insert('resource_files', map)",
                "通过单例 helper 顺序写入 SQLite",
                ORANGE,
            ),
            (
                "④ setState() 重新加载列表",
                "加载完成后刷新 ListView 显示",
                RED_C,
            ),
        ],
        crops_dir / "mock_auto_init.png",
    )

    # ── Mock 5: 播放交互 ──────────────────────────────────────────────────
    shots["play_interact"] = mock_page(
        "视频播放交互",
        "点击列表项 → _playVideo() → SnackBar 提示路径",
        ["点击播放", "SnackBar", "平台播放器"],
        [
            ("ListTile.onTap", "用户点击任意视频条目触发 onTap 回调", PRIMARY),
            ("_playVideo(filePath)", "传入 file_path 字段，由平台决定播放方式", GREEN),
            ("ScaffoldMessenger", 'SnackBar 显示："正在播放: assets/xxx.mp4"', ORANGE),
            ("平台扩展点", "实际播放可接入 video_player / 原生 Intent", RED_C),
        ],
        crops_dir / "mock_play_interact.png",
    )

    # ── Mock 6: AppBar + DatabaseHelper ──────────────────────────────────
    shots["appbar_db"] = mock_page(
        "AppBar 与 DatabaseHelper",
        "刷新按钮重新加载 · 单例统一管理 SQLite",
        ["刷新", "DatabaseHelper", "单例"],
        [
            ("AppBar refresh icon", "点击刷新 → 重新执行 _loadVideos()", PRIMARY),
            ("DatabaseHelper.instance", "全局单例，避免多次打开数据库连接", GREEN),
            ("_loadVideos() async", "await db.query() → setState 更新列表", ORANGE),
            (
                "resource_files 表统一管理",
                "文档/视频/测验等所有资源共用同一张表",
                PURPLE,
            ),
        ],
        crops_dir / "mock_appbar_db.png",
    )

    # ── Mock 7: 与课程进度联动 ────────────────────────────────────────────
    shots["progress_link"] = mock_page(
        "与课程进度的联动",
        "视频观看行为可写入 learning_records · 推动进度",
        ["学习记录", "进度联动", "chapter"],
        [
            (
                "resource_files.chapter",
                "章节字段与 learning_records 对应，便于统计进度",
                PRIMARY,
            ),
            (
                "VideoListPage → 播放",
                "播放动作可触发 LearningRecordDao.insert()",
                GREEN,
            ),
            (
                "ProgressPage 读取记录",
                "查询 learning_records 展示已学章节进度",
                ORANGE,
            ),
            (
                "数据一致性",
                "同一个 DatabaseHelper.instance 保证事务一致",
                RED_C,
            ),
        ],
        crops_dir / "mock_progress_link.png",
    )

    return shots


# ═══════════════════════════════════════════════════════════════════════════
# SLIDE DEFINITIONS  (15 slides)
# ═══════════════════════════════════════════════════════════════════════════
def build_slides(
    crops: dict[str, Path],
    shots: dict[str, Path],
) -> list[SlideSpec]:
    return [
        # ── 01  课程导入 ──────────────────────────────────────────────────
        SlideSpec(
            title="课程导入",
            subtitle="视频播放功能 — 按章节组织的课程视频资源管理",
            bullets=[
                "视频资源管理",
                "6 章 15 个视频",
                "SQLite 持久化存储",
                "点击播放交互",
                "DatabaseHelper 单例",
            ],
            narration=(
                "欢迎进入视频播放功能教学视频。"
                "本节围绕 VideoListPage 的实现展开，讲解系统如何管理按章节组织的课程视频资源。"
                "共 6 章 15 个视频，数据存储在 SQLite 数据库的 resource_files 表中。"
                "支持首次启动自动初始化和点击播放交互，由 DatabaseHelper 单例统一管理数据库连接。"
            ),
            voice_segments=[
                "欢迎进入视频播放功能教学视频。",
                "本节围绕 VideoListPage 的实现展开，",
                "讲解系统如何管理按章节组织的课程视频资源。",
                "共 6 章 15 个视频，数据存储在 SQLite 数据库的 resource_files 表中。",
                "支持首次启动自动初始化和点击播放交互，",
                "由 DatabaseHelper 单例统一管理数据库连接。",
            ],
            image_path=crops.get("framework_full"),
        ),
        # ── 02  VideoListPage 页面结构 ────────────────────────────────────
        SlideSpec(
            title="VideoListPage 页面结构",
            subtitle="AppBar + ListView.builder + refresh 按钮构成完整视频列表页",
            bullets=[
                "Scaffold — 基础页面框架",
                "AppBar — 标题 + refresh 按钮",
                "ListView.builder — 动态渲染列表",
                "ListTile — 红色图标 + 章节标题",
                "setState 驱动异步刷新",
            ],
            narration=(
                "VideoListPage 由三个核心部分构成。"
                "顶部 AppBar 承载页面标题与刷新按钮，点击刷新会重新从数据库加载视频列表。"
                "中间主体是 ListView.builder，根据视频列表动态生成每一条 ListTile。"
                "每条 ListTile 左侧有一个红色圆形图标，右侧显示章节名称，点击可触发播放操作。"
                "页面状态的刷新通过 setState 驱动，保证数据库读取完成后界面立即更新。"
            ),
            voice_segments=[
                "VideoListPage 由三个核心部分构成。",
                "顶部 AppBar 承载页面标题与刷新按钮，点击刷新会重新从数据库加载视频列表。",
                "中间主体是 ListView.builder，根据视频列表动态生成每一条 ListTile。",
                "每条 ListTile 左侧有一个红色圆形图标，右侧显示章节名称，点击可触发播放操作。",
                "页面状态的刷新通过 setState 驱动，保证数据库读取完成后界面立即更新。",
            ],
            image_path=shots.get("video_list"),
        ),
        # ── 03  视频资源列表展示 ──────────────────────────────────────────
        SlideSpec(
            title="视频资源列表展示",
            subtitle="ListView 逐条渲染 · 红色圆形图标标识视频类型",
            bullets=[
                "红色 CircleAvatar 作为视频图标",
                "主标题：chapter 字段内容",
                "副标题：file_path 资产路径",
                "onTap → 调用 _playVideo(filePath)",
                "空列表时显示「暂无视频资源」提示",
            ],
            narration=(
                "列表的视觉设计非常简洁。"
                "每条视频记录用一个红色圆形图标标识视频类型，主标题显示章节名称，副标题显示资产路径。"
                "用户点击任意一条，页面就调用 _playVideo 方法，并通过 SnackBar 显示当前视频的文件路径。"
                "当数据库记录为空时，ListView 区域会显示暂无视频资源的提示文字，告知用户当前状态。"
            ),
            voice_segments=[
                "列表的视觉设计非常简洁。",
                "每条视频记录用一个红色圆形图标标识视频类型，",
                "主标题显示章节名称，副标题显示资产路径。",
                "用户点击任意一条，页面就调用 _playVideo 方法，",
                "并通过 SnackBar 显示当前视频的文件路径。",
                "当数据库记录为空时，会显示暂无视频资源的提示文字。",
            ],
            image_path=shots.get("video_list"),
            image_caption="ListView.builder 渲染视频列表 — 红色圆形图标 + 章节名 + 路径",
        ),
        # ── 04  课程章节组织总览 ──────────────────────────────────────────
        SlideSpec(
            title="课程章节组织总览",
            subtitle="6 章 15 个视频 · 章节粒度对应 resource_files 记录",
            bullets=[
                "第一章 移动应用开发技术体系 × 2",
                "第二章 原生开发基础 × 2",
                "第三章 混合开发技术 × 3",
                "第四章 小程序开发 × 2",
                "第五章 华为多端应用开发 × 3",
                "第六章 综合开发实践 × 3",
            ],
            narration=(
                "课程视频按照六章组织，总计十五个视频资源。"
                "第一章移动应用开发技术体系有两个视频，第二章原生开发基础有两个视频。"
                "第三章混合开发技术有三个视频，第四章小程序开发有两个视频。"
                "第五章华为多端应用开发和第六章综合开发实践各有三个视频。"
                "每个视频对应 resource_files 表中的一条记录，file_type 字段值为 video。"
            ),
            voice_segments=[
                "课程视频按照六章组织，总计十五个视频资源。",
                "第一章移动应用开发技术体系有两个视频，第二章原生开发基础有两个视频。",
                "第三章混合开发技术有三个视频，第四章小程序开发有两个视频。",
                "第五章华为多端应用开发和第六章综合开发实践各有三个视频。",
                "每个视频对应 resource_files 表中的一条记录，file_type 字段值为 video。",
            ],
            image_path=shots.get("video_chapters"),
        ),
        # ── 05  第一至三章视频资源详情 ───────────────────────────────────
        SlideSpec(
            title="第一至三章视频资源详情",
            subtitle="移动应用开发技术体系 · 原生开发基础 · 混合开发技术",
            bullets=[
                "第一章技术体系1 → assets/第一章移动应用开发技术体系1.mp4",
                "第一章技术体系2 → assets/第一章移动应用开发技术体系2.mp4",
                "第二章原生基础1 → assets/第二章原生开发基础1.mp4",
                "第二章原生基础2 → assets/第二章原生开发基础2.mp4",
                "第三章混合技术1/2/3 → assets/第三章混合开发技术N.mp4",
            ],
            narration=(
                "前三章共七个视频资源，路径都以 assets 开头。"
                "第一章移动应用开发技术体系对应两个 MP4 文件，分别是技术体系1和技术体系2。"
                "第二章原生开发基础同样包含两个视频，分别是原生开发基础1和原生开发基础2。"
                "第三章混合开发技术包含三个视频，文件名后缀数字依次为1、2、3。"
                "这些路径字段存储在 resource_files 的 file_path 列中，作为平台播放器的输入参数。"
            ),
            voice_segments=[
                "前三章共七个视频资源，路径都以 assets 开头。",
                "第一章移动应用开发技术体系对应两个 MP4 文件，",
                "分别是技术体系1和技术体系2。",
                "第二章原生开发基础同样包含两个视频，分别是原生开发基础1和原生开发基础2。",
                "第三章混合开发技术包含三个视频，文件名后缀数字依次为1、2、3。",
                "这些路径字段存储在 resource_files 的 file_path 列中，",
                "作为平台播放器的输入参数。",
            ],
            image_path=shots.get("video_chapters"),
            code_title="第一至三章路径示例",
            code_text=(
                "assets/第一章移动应用开发技术体系1.mp4\n"
                "assets/第一章移动应用开发技术体系2.mp4\n"
                "assets/第二章原生开发基础1.mp4\n"
                "assets/第二章原生开发基础2.mp4\n"
                "assets/第三章混合开发技术1.mp4\n"
                "assets/第三章混合开发技术2.mp4\n"
                "assets/第三章混合开发技术3.mp4"
            ),
        ),
        # ── 06  第四至六章视频资源详情 ───────────────────────────────────
        SlideSpec(
            title="第四至六章视频资源详情",
            subtitle="小程序开发 · 华为多端应用开发 · 综合开发实践",
            bullets=[
                "第四章小程序1/2 → assets/第四章小程序开发N.mp4",
                "第五章华为多端1/2/3 → assets/第五章华为多端应用开发N.mp4",
                "第六章综合实践1/2/3 → assets/第六章综合开发实践N.mp4",
                "后三章合计 8 个视频",
                "全部 15 条记录覆盖完整课程",
            ],
            narration=(
                "后三章共八个视频资源。"
                "第四章小程序开发有两个视频，第五章华为多端应用开发有三个视频，第六章综合开发实践有三个视频。"
                "加上前三章的七个视频，总计恰好十五条 resource_files 记录。"
                "这十五条记录在数据库为空时会被 _initVideoData 方法一次性批量写入，"
                "保证应用第一次启动就有完整的视频列表可以显示。"
            ),
            voice_segments=[
                "后三章共八个视频资源。",
                "第四章小程序开发有两个视频，",
                "第五章华为多端应用开发有三个视频，第六章综合开发实践有三个视频。",
                "加上前三章的七个视频，总计恰好十五条 resource_files 记录。",
                "这十五条记录在数据库为空时会被 _initVideoData 方法一次性批量写入，",
                "保证应用第一次启动就有完整的视频列表可以显示。",
            ],
            image_path=shots.get("video_chapters"),
            code_title="第四至六章路径示例",
            code_text=(
                "assets/第四章小程序开发1.mp4\n"
                "assets/第四章小程序开发2.mp4\n"
                "assets/第五章华为多端应用开发1.mp4\n"
                "assets/第五章华为多端应用开发2.mp4\n"
                "assets/第五章华为多端应用开发3.mp4\n"
                "assets/第六章综合开发实践1.mp4\n"
                "assets/第六章综合开发实践2.mp4\n"
                "assets/第六章综合开发实践3.mp4"
            ),
        ),
        # ── 07  resource_files 表结构 ────────────────────────────────────
        SlideSpec(
            title="SQLite resource_files 表结构",
            subtitle="视频与文档资源共用同一张表 · file_type 字段区分类型",
            bullets=[
                "id — INTEGER PRIMARY KEY AUTOINCREMENT",
                "file_type — 'video' | 'document' 等",
                "chapter — 章节名，ListTile 主标题来源",
                "file_path — assets/... 路径，传给播放器",
                "title — 辅助标题（可选字段）",
            ],
            narration=(
                "resource_files 表是视频与文档资源的统一存储位置。"
                "表结构包含 id 主键、file_type 类型字段、chapter 章节名、file_path 文件路径以及 title 标题。"
                "VideoListPage 在查询时只获取 file_type 等于 video 的记录，从而将视频资源与文档资源分离。"
                "chapter 字段的值直接作为列表每一项的主标题展示，"
                "file_path 字段的值作为播放器输入传入 _playVideo 方法。"
            ),
            voice_segments=[
                "resource_files 表是视频与文档资源的统一存储位置。",
                "表结构包含 id 主键、file_type 类型字段、",
                "chapter 章节名、file_path 文件路径以及 title 标题。",
                "VideoListPage 在查询时只获取 file_type 等于 video 的记录，",
                "从而将视频资源与文档资源分离。",
                "chapter 字段的值直接作为列表每一项的主标题展示，",
                "file_path 字段的值作为播放器输入传入 _playVideo 方法。",
            ],
            image_path=shots.get("db_video"),
            code_title="resource_files 表 DDL",
            code_text=(
                "CREATE TABLE resource_files (\n"
                "  id        INTEGER PRIMARY KEY AUTOINCREMENT,\n"
                "  file_type TEXT NOT NULL,  -- 'video' | 'document'\n"
                "  chapter   TEXT,           -- 章节名\n"
                "  file_path TEXT NOT NULL,  -- assets/xxx.mp4\n"
                "  title     TEXT            -- 可选标题\n"
                ");"
            ),
        ),
        # ── 08  首次启动自动初始化流程 ───────────────────────────────────
        SlideSpec(
            title="首次启动自动初始化流程",
            subtitle="数据库为空时自动写入 15 条视频记录 · 用户无感知",
            bullets=[
                "① initState() → _loadVideos()",
                "② query WHERE file_type='video'",
                "③ count == 0 → 调用 _initVideoData()",
                "④ 批量 insert 15 条记录",
                "⑤ setState() 刷新 ListView",
            ],
            narration=(
                "VideoListPage 的初始化流程设计得非常健壮。"
                "页面挂载时 initState 调用 _loadVideos 异步方法。"
                "方法内先查询 resource_files 表中 file_type 为 video 的记录数量。"
                "如果数量为零，说明是首次启动，立即调用 _initVideoData 批量插入十五条记录。"
                "插入完成后再次查询，把结果存入状态变量，最后通过 setState 触发 ListView 重新渲染。"
                "整个过程对用户完全透明，首次启动即可看到完整的视频列表。"
            ),
            voice_segments=[
                "VideoListPage 的初始化流程设计得非常健壮。",
                "页面挂载时 initState 调用 _loadVideos 异步方法。",
                "方法内先查询 resource_files 表中 file_type 为 video 的记录数量。",
                "如果数量为零，说明是首次启动，立即调用 _initVideoData 批量插入十五条记录。",
                "插入完成后再次查询，把结果存入状态变量，",
                "最后通过 setState 触发 ListView 重新渲染。",
                "整个过程对用户完全透明，首次启动即可看到完整的视频列表。",
            ],
            image_path=shots.get("auto_init"),
        ),
        # ── 09  视频资源自动插入逻辑 ─────────────────────────────────────
        SlideSpec(
            title="视频资源自动插入逻辑",
            subtitle="_initVideoData() 构建 Map 列表 · 逐条 insert 写入 SQLite",
            bullets=[
                "构建 List<Map<String,dynamic>> videos",
                "每条 Map 含 file_type / chapter / file_path",
                "for (var v in videos) await db.insert()",
                "DatabaseHelper.instance 单例写入",
                "insert 完成后立即可查询",
            ],
            narration=(
                "_initVideoData 方法的职责非常单一：构造数据并写入数据库。"
                "方法内部先定义一个包含十五个 Map 的列表，每个 Map 包含 file_type、chapter 和 file_path 字段。"
                "然后通过 for 循环，每次调用 DatabaseHelper.instance 的 insert 方法将一条记录写入 resource_files 表。"
                "因为使用了 await，每次 insert 都是顺序执行的，不会出现并发冲突。"
                "插入完成后，_loadVideos 的后续查询可以立刻获取到这十五条记录。"
            ),
            voice_segments=[
                "_initVideoData 方法的职责非常单一：构造数据并写入数据库。",
                "方法内部先定义一个包含十五个 Map 的列表，",
                "每个 Map 包含 file_type、chapter 和 file_path 字段。",
                "然后通过 for 循环，每次调用 DatabaseHelper.instance 的 insert 方法，",
                "将一条记录写入 resource_files 表。",
                "因为使用了 await，每次 insert 都是顺序执行的，不会出现并发冲突。",
                "插入完成后，_loadVideos 的后续查询可以立刻获取到这十五条记录。",
            ],
            image_path=shots.get("auto_init"),
            code_title="_initVideoData 逻辑摘要",
            code_text=(
                "Future<void> _initVideoData() async {\n"
                "  final db = DatabaseHelper.instance;\n"
                "  final videos = [\n"
                "    {'file_type':'video',\n"
                "     'chapter':'第一章移动应用开发技术体系1',\n"
                "     'file_path':'assets/第一章...1.mp4'},\n"
                "    // ... 共 15 条记录\n"
                "  ];\n"
                "  for (var v in videos) {\n"
                "    await db.insert('resource_files', v);\n"
                "  }\n"
                "}"
            ),
        ),
        # ── 10  视频播放交互 ──────────────────────────────────────────────
        SlideSpec(
            title="视频播放交互",
            subtitle="点击 ListTile → _playVideo(filePath) → SnackBar 提示",
            bullets=[
                "ListTile.onTap 触发播放",
                "_playVideo(String filePath) 接收路径",
                "ScaffoldMessenger.showSnackBar()",
                "SnackBar 显示：'正在播放: {filePath}'",
                "实际播放由平台层扩展实现",
            ],
            narration=(
                "视频播放的交互流程分为三个层次。"
                "第一层是用户层：用户在 ListView 中点击某条视频，触发 ListTile 的 onTap 回调。"
                "第二层是 Flutter 层：onTap 调用 _playVideo 方法，传入该条记录的 file_path 字符串。"
                "_playVideo 方法通过 ScaffoldMessenger 显示一个 SnackBar，内容为正在播放加上文件路径。"
                "第三层是平台扩展层：实际的视频播放可以通过 video_player 插件或原生 Intent 来实现，"
                "当前版本以 SnackBar 作为占位反馈。"
            ),
            voice_segments=[
                "视频播放的交互流程分为三个层次。",
                "第一层是用户层：用户在 ListView 中点击某条视频，触发 ListTile 的 onTap 回调。",
                "第二层是 Flutter 层：onTap 调用 _playVideo 方法，",
                "传入该条记录的 file_path 字符串。",
                "_playVideo 方法通过 ScaffoldMessenger 显示一个 SnackBar，",
                "内容为正在播放加上文件路径。",
                "第三层是平台扩展层：",
                "实际的视频播放可以通过 video_player 插件或原生 Intent 来实现，",
                "当前版本以 SnackBar 作为占位反馈。",
            ],
            image_path=shots.get("play_interact"),
        ),
        # ── 11  _playVideo 方法实现 ───────────────────────────────────────
        SlideSpec(
            title="_playVideo() 方法实现",
            subtitle="极简实现 · SnackBar 反馈 · 便于后续扩展平台播放器",
            bullets=[
                "接收 String filePath 参数",
                "hideCurrentSnackBar() 防叠加",
                "showSnackBar(SnackBar(content: Text(...)))",
                "低耦合设计，易于扩展",
                "可替换为 Navigator.push(VideoPlayerPage)",
            ],
            narration=(
                "_playVideo 方法的实现非常简洁，只有几行代码。"
                "方法接收一个字符串类型的文件路径参数。"
                "首先调用 ScaffoldMessenger 的 hideCurrentSnackBar 方法，防止多次点击时 SnackBar 叠加显示。"
                "然后调用 showSnackBar，显示包含文件路径的提示文字。"
                "这种低耦合设计的好处是：当需要接入真实播放器时，"
                "只需把 SnackBar 替换成 Navigator.push 或插件调用，其他代码无需修改。"
            ),
            voice_segments=[
                "_playVideo 方法的实现非常简洁，只有几行代码。",
                "方法接收一个字符串类型的文件路径参数。",
                "首先调用 ScaffoldMessenger 的 hideCurrentSnackBar 方法，",
                "防止多次点击时 SnackBar 叠加显示。",
                "然后调用 showSnackBar，显示包含文件路径的提示文字。",
                "这种低耦合设计的好处是：",
                "当需要接入真实播放器时，只需把 SnackBar 替换成 Navigator.push 或插件调用，",
                "其他代码无需修改。",
            ],
            image_path=shots.get("play_interact"),
            code_title="_playVideo 实现摘要",
            code_text=(
                "void _playVideo(String filePath) {\n"
                "  ScaffoldMessenger.of(context)\n"
                "    ..hideCurrentSnackBar()\n"
                "    ..showSnackBar(\n"
                "      SnackBar(\n"
                "        content: Text('正在播放: $filePath'),\n"
                "      ),\n"
                "    );\n"
                "  // 扩展: Navigator.push(VideoPlayerPage)\n"
                "}"
            ),
        ),
        # ── 12  AppBar 刷新按钮 ───────────────────────────────────────────
        SlideSpec(
            title="AppBar 刷新按钮功能",
            subtitle="IconButton(Icons.refresh) → 重新执行 _loadVideos()",
            bullets=[
                "AppBar.actions 放置 IconButton",
                "Icons.refresh 图标",
                "onPressed → _loadVideos()",
                "适用场景：外部导入视频后刷新",
                "与 setState 配合实现响应式更新",
            ],
            narration=(
                "AppBar 右侧的刷新按钮是一个实用的辅助功能。"
                "按钮通过 AppBar 的 actions 属性添加，使用 Icons.refresh 图标。"
                "点击后直接调用 _loadVideos 方法，重新从数据库读取视频列表并更新界面。"
                "这个设计在实际使用中非常有价值："
                "当用户通过其他途径导入了新的视频资源，或者数据库内容发生变化时，"
                "可以立刻手动刷新，而不需要退出重进页面。"
            ),
            voice_segments=[
                "AppBar 右侧的刷新按钮是一个实用的辅助功能。",
                "按钮通过 AppBar 的 actions 属性添加，使用 Icons.refresh 图标。",
                "点击后直接调用 _loadVideos 方法，重新从数据库读取视频列表并更新界面。",
                "这个设计在实际使用中非常有价值：",
                "当用户通过其他途径导入了新的视频资源，或者数据库内容发生变化时，",
                "可以立刻手动刷新，而不需要退出重进页面。",
            ],
            image_path=shots.get("appbar_db"),
            code_title="AppBar refresh 代码",
            code_text=(
                "AppBar(\n"
                "  title: const Text('视频播放'),\n"
                "  actions: [\n"
                "    IconButton(\n"
                "      icon: const Icon(Icons.refresh),\n"
                "      onPressed: _loadVideos,\n"
                "    ),\n"
                "  ],\n"
                "),"
            ),
        ),
        # ── 13  DatabaseHelper 统一管理 ───────────────────────────────────
        SlideSpec(
            title="DatabaseHelper 统一管理",
            subtitle="单例模式 · 全局共享数据库连接 · 避免重复打开",
            bullets=[
                "DatabaseHelper.instance 全局单例",
                "懒初始化 — 首次访问时初始化",
                "统一管理 resource_files / learning_records",
                "所有页面共用同一连接",
                "保证数据一致性与并发安全",
            ],
            narration=(
                "DatabaseHelper 是整个应用的数据库访问核心。"
                "它采用单例模式，通过 DatabaseHelper.instance 提供全局唯一的数据库连接对象。"
                "这意味着无论 VideoListPage、DocumentPage 还是 ProgressPage，"
                "都通过同一个 DatabaseHelper 实例访问数据库。"
                "单例懒初始化的设计保证了数据库只被打开一次，"
                "避免了多次打开带来的性能开销和潜在的并发冲突。"
                "resource_files、learning_records 等多张表都由 DatabaseHelper 统一创建和管理。"
            ),
            voice_segments=[
                "DatabaseHelper 是整个应用的数据库访问核心。",
                "它采用单例模式，通过 DatabaseHelper.instance 提供全局唯一的数据库连接对象。",
                "这意味着无论 VideoListPage、DocumentPage 还是 ProgressPage，",
                "都通过同一个 DatabaseHelper 实例访问数据库。",
                "单例懒初始化的设计保证了数据库只被打开一次，",
                "避免了多次打开带来的性能开销和潜在的并发冲突。",
                "resource_files、learning_records 等多张表都由 DatabaseHelper 统一创建和管理。",
            ],
            image_path=shots.get("appbar_db"),
            code_title="DatabaseHelper 单例访问模式",
            code_text=(
                "class DatabaseHelper {\n"
                "  static final DatabaseHelper instance =\n"
                "      DatabaseHelper._internal();\n"
                "  DatabaseHelper._internal();\n"
                "\n"
                "  // VideoListPage 查询示例:\n"
                "  final db = DatabaseHelper.instance;\n"
                "  final rows = await db.query(\n"
                "    'resource_files',\n"
                "    where: \"file_type = 'video'\",\n"
                "  );\n"
                "}"
            ),
        ),
        # ── 14  与课程进度联动 ────────────────────────────────────────────
        SlideSpec(
            title="视频播放与课程进度联动",
            subtitle="chapter 字段桥接视频资源与学习记录 · 推动进度更新",
            bullets=[
                "resource_files.chapter → 视频章节标识",
                "播放行为 → 可写入 learning_records",
                "LearningRecordDao.insert() 记录行为",
                "ProgressPage 查询已学章节统计进度",
                "DatabaseHelper 保证数据一致性",
            ],
            narration=(
                "视频播放功能不是一个孤立的模块，它通过 chapter 字段与课程进度产生联动。"
                "resource_files 表中的 chapter 字段与 learning_records 表使用相同的章节标识。"
                "当用户播放视频时，可以在 _playVideo 方法中同时调用 LearningRecordDao.insert，"
                "把播放行为记录到 learning_records 表中。"
                "ProgressPage 再通过查询 learning_records，统计各章节的学习进度并展示进度条。"
                "这样一来，视频播放与知识图谱学习等多种行为都能共同推动课程进度，形成完整的学习闭环。"
            ),
            voice_segments=[
                "视频播放功能不是一个孤立的模块，",
                "它通过 chapter 字段与课程进度产生联动。",
                "resource_files 表中的 chapter 字段与 learning_records 表使用相同的章节标识。",
                "当用户播放视频时，可以在 _playVideo 方法中同时调用 LearningRecordDao.insert，",
                "把播放行为记录到 learning_records 表中。",
                "ProgressPage 再通过查询 learning_records，统计各章节的学习进度并展示进度条。",
                "这样一来，视频播放与知识图谱学习等多种行为都能共同推动课程进度，",
                "形成完整的学习闭环。",
            ],
            image_path=shots.get("progress_link"),
        ),
        # ── 15  功能总结 ──────────────────────────────────────────────────
        SlideSpec(
            title="功能总结",
            subtitle="VideoListPage 核心要点回顾 · 下一步学习方向",
            bullets=[
                "resource_files 表统一管理视频元数据",
                "首次启动自动写入 15 条记录，用户无感知",
                "ListView 红色图标 + 章节名 + 点击播放",
                "_playVideo → SnackBar 提示，可扩展平台播放",
                "DatabaseHelper 单例 + chapter 联动进度",
            ],
            narration=(
                "本节内容到这里结束，我们来回顾一下视频播放功能的核心要点。"
                "视频元数据存储在 SQLite 的 resource_files 表中，file_type 字段值为 video。"
                "首次启动时，系统自动插入六章共十五条记录，保证列表立刻可用。"
                "ListView 通过红色圆形图标和章节名称清晰展示视频资源，点击触发 _playVideo 方法。"
                "_playVideo 以 SnackBar 作为当前反馈，后续可替换为真实的平台播放器。"
                "DatabaseHelper 单例确保数据一致性，chapter 字段将视频播放与课程进度联动，"
                "形成完整的学习体验。"
            ),
            voice_segments=[
                "本节内容到这里结束，我们来回顾一下视频播放功能的核心要点。",
                "视频元数据存储在 SQLite 的 resource_files 表中，file_type 字段值为 video。",
                "首次启动时，系统自动插入六章共十五条记录，保证列表立刻可用。",
                "ListView 通过红色圆形图标和章节名称清晰展示视频资源，点击触发 _playVideo 方法。",
                "_playVideo 以 SnackBar 作为当前反馈，后续可替换为真实的平台播放器。",
                "DatabaseHelper 单例确保数据一致性，",
                "chapter 字段将视频播放与课程进度联动，形成完整的学习体验。",
            ],
            image_path=crops.get("framework_full"),
        ),
    ]


# ═══════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════
def main() -> None:
    print("=" * 68)
    print("  gen_video_player_v6  —  视频播放功能教学视频生成器")
    print("=" * 68)

    # ── 创建工作目录 ──────────────────────────────────────────────────────
    FEAT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    CROPS_DIR.mkdir(parents=True, exist_ok=True)

    # ── 生成 UML 裁切图 ───────────────────────────────────────────────────
    print("\n[1/4] 生成 UML 裁切图 ...")
    crops = generate_uml_crops(CROPS_DIR)
    print(f"      {len(crops)} 张裁切图就绪")

    # ── 生成功能 Mock 截图 ────────────────────────────────────────────────
    print("\n[2/4] 生成功能 Mock 截图 ...")
    shots = build_feature_shots(CROPS_DIR)
    print(f"      {len(shots)} 张 Mock 截图就绪")

    # ── 构建 Slide 列表 ───────────────────────────────────────────────────
    print("\n[3/4] 构建幻灯片列表 ...")
    slides = build_slides(crops, shots)
    print(f"      共 {len(slides)} 张幻灯片")
    for i, s in enumerate(slides, 1):
        print(f"      [{i:02d}] {s.title}")

    # ── 生成视频 / SRT ────────────────────────────────────────────────────
    print("\n[4/4] 生成教学视频（edge_tts + moviepy）...")
    base_paths, ok = build_video(slides, FEAT_DIR, VIDEO_PATH, SRT_PATH)

    # ── 生成 PPTX ─────────────────────────────────────────────────────────
    build_pptx(slides, base_paths, PPTX_PATH)

    # ── 生成讲稿 Markdown ─────────────────────────────────────────────────
    build_script(slides, SCRIPT_PATH, "视频播放")

    # ── 最终报告 ──────────────────────────────────────────────────────────
    print("\n" + "=" * 68)
    print("  生成完成！")
    print("=" * 68)

    if VIDEO_PATH.exists():
        size_mb = VIDEO_PATH.stat().st_size / 1024 / 1024
        print(f"  Video : {VIDEO_PATH}")
        print(f"          大小：{size_mb:.1f} MB")
        try:
            from moviepy.editor import VideoFileClip  # type: ignore[import]

            clip = VideoFileClip(str(VIDEO_PATH))
            dur = clip.duration
            clip.close()
            m, s = divmod(int(dur), 60)
            print(f"          时长：{m:02d}:{s:02d}（{dur:.1f} 秒）")
        except Exception:
            pass
    else:
        print("  [警告] 视频文件未生成，请检查上方日志。")

    if PPTX_PATH.exists():
        size_mb = PPTX_PATH.stat().st_size / 1024 / 1024
        print(f"  PPTX  : {PPTX_PATH}  ({size_mb:.1f} MB)")

    if SRT_PATH.exists():
        print(f"  SRT   : {SRT_PATH}")

    if SCRIPT_PATH.exists():
        print(f"  Script: {SCRIPT_PATH}")

    if not ok:
        print("\n  [警告] 视频生成过程中出现错误，请检查上方日志。")

    print("=" * 68)


if __name__ == "__main__":
    main()
