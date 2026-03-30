#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_quiz_v6.py — 测验功能教学视频生成器

输出:
  knowledge_graph_app/video_output/测验功能教程_v6.mp4
  knowledge_graph_app/video_output/测验功能教程_v6.pptx
工作目录:
  knowledge_graph_app/docs/video/feat_quiz/
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from video_common_v6 import *

# ═══════════════════════════════════════════════════════════════════════════
# PATHS
# ═══════════════════════════════════════════════════════════════════════════
FEAT_DIR = ROOT / "docs" / "video" / "feat_quiz"
VIDEO_PATH = OUT_DIR / "测验功能教程_v6.mp4"
PPTX_PATH = OUT_DIR / "测验功能教程_v6.pptx"
SRT_PATH = FEAT_DIR / "subtitles.srt"
SCRIPT_PATH = FEAT_DIR / "script.md"
CROPS_DIR = FEAT_DIR / "crops"


# ═══════════════════════════════════════════════════════════════════════════
# MOCK SCREENSHOTS
# ═══════════════════════════════════════════════════════════════════════════
def build_feature_shots(crops_dir: Path) -> dict[str, Path]:
    shots: dict[str, Path] = {}

    # ── 章节选择界面 ────────────────────────────────────────────────────────
    shots["chapter_select"] = mock_page(
        "章节选择",
        "选择测验章节 · 按 source 字段分组 · 错题本入口",
        ["章节选择", "QuizDao", "错题本"],
        [
            (
                "第一章 移动应用开发技术体系",
                "点击进入该章节测验，题目来自 questions WHERE source=?",
                PRIMARY,
            ),
            (
                "第二章 原生开发基础",
                "点击进入该章节测验，_startQuiz(chapter) 异步加载",
                GREEN,
            ),
            ("错题本", "查看和复习历史答错题目，跳转 WrongAnswersPage", RED_C),
        ],
        crops_dir / "mock_chapter_select.png",
    )

    # ── 题目界面 ─────────────────────────────────────────────────────────────
    shots["quiz_question"] = mock_page(
        "题目界面",
        "LinearProgressIndicator · 题目文字 · 4 选项按钮",
        ["进度条", "题目", "选项A/B/C/D", "提交/下一题"],
        [
            (
                "LinearProgressIndicator",
                "value=(currentIndex+1)/total，顶部进度条实时更新",
                PRIMARY,
            ),
            (
                "题目文字",
                "fontSize 18, fontWeight.bold，SingleChildScrollView 支持滚动",
                GREEN,
            ),
            (
                "选项 A / B / C / D",
                "List.generate(4) 动态生成，InkWell 点击选中",
                ORANGE,
            ),
            (
                "底部按钮",
                "未选禁用→提交答案→下一题/完成测验，状态随 _answered 切换",
                PURPLE,
            ),
        ],
        crops_dir / "mock_quiz_question.png",
    )

    # ── 颜色状态反馈 ──────────────────────────────────────────────────────────
    shots["color_feedback"] = mock_page(
        "选项颜色状态反馈",
        "_answered × isSelected × isCorrect 三状态颜色机",
        ["未选择", "已选中", "提交后正确", "提交后选错"],
        [
            ("未选择", "border: Colors.grey[300]，背景透明，width=1", TEXT_MUTE),
            (
                "已选中（未提交）",
                "bgColor: 0xFF667eea+opacity0.3，border 蓝色，圆圈填充+勾",
                PRIMARY,
            ),
            (
                "提交后 — 正确选项",
                "bgColor: Colors.green[100]，border: Colors.green，width=2",
                GREEN,
            ),
            (
                "提交后 — 选错选项",
                "bgColor: Colors.red[100]，border: Colors.red，width=2",
                RED_C,
            ),
        ],
        crops_dir / "mock_color_feedback.png",
    )

    # ── 提交答案流程 ──────────────────────────────────────────────────────────
    shots["submit_flow"] = mock_page(
        "提交答案流程",
        "_submitAnswer() · 判断正误 · 记录错题 · setState",
        ["_submitAnswer", "answerIndex", "_correctCount", "_recordWrongAnswer"],
        [
            (
                "前置检查",
                "_selectedAnswer == null → return，Button disabled 配合",
                PRIMARY,
            ),
            ("判断正误", "isCorrect = _selectedAnswer == question.answerIndex", GREEN),
            (
                "记录错题",
                "if (!isCorrect) _recordWrongAnswer(question)  — 异步不阻塞",
                RED_C,
            ),
            (
                "状态更新",
                "setState: _answered=true，isCorrect → _correctCount++",
                ORANGE,
            ),
        ],
        crops_dir / "mock_submit_flow.png",
    )

    # ── WrongAnswerDao ────────────────────────────────────────────────────────
    shots["wrong_answer_dao"] = mock_page(
        "WrongAnswerDao — 错题记录",
        "先查后判 · INSERT or UPDATE · times 错误计数",
        ["wrong_answers 表", "times", "last_wrong_time", "重复检测"],
        [
            (
                "重复检测",
                "SELECT WHERE user_id=? AND question_id=?，存在则 UPDATE",
                PRIMARY,
            ),
            (
                "UPDATE 路径",
                "times = currentTimes+1，last_wrong_time = DateTime.now()",
                ORANGE,
            ),
            (
                "INSERT 路径",
                "全字段写入：userId/questionId/question/userAnswer/correctAnswer/chapter/times=1",
                GREEN,
            ),
            ("静默异常", "try-catch 捕获错误后忽略，不影响答题主流程", TEXT_MUTE),
        ],
        crops_dir / "mock_wrong_answer_dao.png",
    )

    # ── QuizResultModel ───────────────────────────────────────────────────────
    shots["quiz_result_model"] = mock_page(
        "QuizResultModel 成绩数据模型",
        "userId · score · numCorrect · numTotal · chapter · 时间戳",
        ["QuizResultModel", "quiz_results 表", "toMap", "accuracy"],
        [
            (
                "score",
                "百分制得分 = (numCorrect/numTotal*100).round()，_finishQuiz 中计算",
                PRIMARY,
            ),
            ("numCorrect / numTotal", "答对题数 / 总题数，用于计算正确率", GREEN),
            (
                "chapter / quizTimestamp / completedAt",
                "章节名(可null) / 开始时间 / 完成时间，ISO 8601 字符串",
                ORANGE,
            ),
            (
                "accuracy getter",
                "numTotal > 0 ? (numCorrect/numTotal)*100 : 0，便捷计算",
                PURPLE,
            ),
        ],
        crops_dir / "mock_quiz_result_model.png",
    )

    # ── 测验完成对话框 ────────────────────────────────────────────────────────
    shots["quiz_result"] = mock_page(
        "测验完成对话框",
        "_finishQuiz() · AlertDialog · barrierDismissible=false",
        ["AlertDialog", "得分", "图标判断", "保存结果"],
        [
            (
                "图标判断",
                "correctCount > total/2 → Icons.celebration(绿) else Icons.sentiment_neutral(橙)",
                GREEN,
            ),
            (
                "得分显示",
                "'得分: ${result.score}分'，fontSize 24，fontWeight.bold",
                PRIMARY,
            ),
            ("正确数/总数", "'正确: $_correctCount / ${_questions.length}'", ORANGE),
            (
                "确定按钮",
                "Navigator.pop → setState: _quizStarted=false，返回章节选择",
                TEXT_MUTE,
            ),
        ],
        crops_dir / "mock_quiz_result.png",
    )

    # ── 错题本页面 ────────────────────────────────────────────────────────────
    shots["wrong_answers_page"] = mock_page(
        "错题本 WrongAnswersPage",
        "ExpansionTile · 错误次数 badge · 答案对比 · 移除/清空",
        ["WrongAnswersPage", "ExpansionTile", "times badge", "答案对比"],
        [
            (
                "折叠状态",
                "CircleAvatar(times次数, 红色背景) + 题目摘要 + '错误次数: N'",
                RED_C,
            ),
            ("展开内容", "题目全文 / 你的答案(红色) / 正确答案(绿色) 三行对比", GREEN),
            (
                "移除单条",
                "TextButton '移除' → removeWrongAnswer(id) → _loadData()",
                ORANGE,
            ),
            (
                "清空全部",
                "AppBar IconButton(delete_sweep) → 确认对话框 → clearWrongAnswers",
                PRIMARY,
            ),
        ],
        crops_dir / "mock_wrong_answers_page.png",
    )

    # ── ProgressPage 测验成绩 Tab ─────────────────────────────────────────────
    shots["progress_quiz_tab"] = mock_page(
        "ProgressPage — 测验成绩 Tab",
        "三统计卡片 · fl_chart 折线图 · 历史记录最多10条",
        ["测验次数", "平均分", "正确率", "折线图", "历史记录"],
        [
            (
                "统计卡片（3张）",
                "测验次数(蓝) / 平均分(绿) / 正确率(橙)，来自 getQuizSummary",
                PRIMARY,
            ),
            (
                "成绩趋势折线图",
                "fl_chart LineChart，高度200，isCurved=true，belowBarData填充",
                GREEN,
            ),
            (
                "历史测验记录",
                "_results.take(10)，CircleAvatar显示分数，>=60绿色 else 红色",
                ORANGE,
            ),
            (
                "RefreshIndicator",
                "下拉刷新触发 _loadData()，重新调用全部 DAO 方法",
                PURPLE,
            ),
        ],
        crops_dir / "mock_progress_quiz.png",
    )

    # ── fl_chart ──────────────────────────────────────────────────────────────
    shots["fl_chart"] = mock_page(
        "fl_chart LineChart 成绩趋势",
        "FlSpot 数据点 · isCurved · barWidth · belowBarData",
        ["FlSpot", "LineChartBarData", "BarAreaData", "isCurved"],
        [
            (
                "数据构造",
                "_results.reversed → asMap().entries → FlSpot(index, score)，Y轴 0~100",
                PRIMARY,
            ),
            (
                "折线样式",
                "color=0xFF667eea, barWidth=3, isCurved=true, dotData(show=true)",
                GREEN,
            ),
            (
                "填充区域",
                "BarAreaData(show=true, color=0xFF667eea+alpha0.1) 半透明下方填充",
                ORANGE,
            ),
            (
                "坐标轴",
                "左侧Y轴保留40px；底部/顶部/右侧标签均关闭；borderData: show=false",
                TEXT_MUTE,
            ),
        ],
        crops_dir / "mock_fl_chart.png",
    )

    # ── ProgressPage 学习记录 Tab ─────────────────────────────────────────────
    shots["progress_learning_tab"] = mock_page(
        "ProgressPage — 学习记录 Tab",
        "LearningRecordDao.getStatistics() · 三卡片 · 学习建议",
        ["学习记录", "unique_nodes", "this_week", "学习建议"],
        [
            ("学习记录总数", "COUNT(*) FROM learning_records WHERE user_id=?", PRIMARY),
            ("学习节点数", "COUNT(DISTINCT node_id)，去重统计已覆盖的知识节点", GREEN),
            (
                "本周学习数",
                "completed_at >= date('now','-7 days') 最近7天活跃度",
                ORANGE,
            ),
            (
                "学习建议",
                "每天1-2h / 先学基础图谱 / 测验巩固 / 错题反复练  (4条 _buildTip)",
                PURPLE,
            ),
        ],
        crops_dir / "mock_progress_learning.png",
    )

    # ── 数据流总览 ────────────────────────────────────────────────────────────
    shots["data_flow"] = mock_page(
        "测验功能数据流总览",
        "用户操作 → DAO → SQLite → UI 五环节闭环",
        ["数据流", "SQLite", "DAO 层", "五环节"],
        [
            (
                "章节加载",
                "QuizDao.getChapters() → SELECT DISTINCT source → ListView 章节列表",
                PRIMARY,
            ),
            (
                "题目加载",
                "QuizDao.getQuestionsByChapter() → WHERE source=? → List<QuestionModel>",
                GREEN,
            ),
            (
                "答题记录",
                "WrongAnswerDao.addWrongAnswer() → INSERT/UPDATE wrong_answers",
                RED_C,
            ),
            (
                "成绩保存→统计",
                "saveQuizResult() → quiz_results → getQuizSummary() → ProgressPage",
                ORANGE,
            ),
        ],
        crops_dir / "mock_data_flow.png",
    )

    return shots


# ═══════════════════════════════════════════════════════════════════════════
# SLIDES  (18 slides)
# ═══════════════════════════════════════════════════════════════════════════
def build_slides(
    crops: dict[str, Path],
    shots: dict[str, Path],
) -> list[SlideSpec]:
    return [
        # ── 1 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="功能导入",
            subtitle="测验功能 — 章节测验、错题管理与学习进度统计",
            bullets=[
                "章节选择 → 开始测验",
                "实时颜色反馈 + 错题自动记录",
                "QuizResultModel 保存成绩",
                "ProgressPage 统计可视化",
                "错题本支持针对性复习",
            ],
            narration=(
                "欢迎进入测验功能教学视频。"
                "测验功能是知识图谱 App 的核心学习闭环模块，涵盖章节选择、题目作答、"
                "错题记录、成绩保存和进度统计五个核心环节。"
                "用户通过测验可以巩固所学知识，利用错题本反复练习薄弱点，"
                "并在进度页看到可视化的学习成果。"
                "本视频将带你完整梳理每个环节的实现原理和数据流转。"
            ),
            image_path=crops.get("framework_full"),
            image_caption="测验功能位于 App 学习闭环的核心位置",
        ),
        # ── 2 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="四大功能模块全景",
            subtitle="QuizPage / WrongAnswersPage / ProgressPage / DAO 层",
            bullets=[
                "QuizPage：章节选择 + 题目作答主页面，StatefulWidget",
                "WrongAnswersPage：错题本，ExpansionTile 可折叠展示",
                "ProgressPage：成绩统计 + 学习记录，TabController 双 Tab",
                "QuizDao：章节查询 / 题目加载 / 成绩保存 / 聚合统计",
                "WrongAnswerDao + LearningRecordDao：错题与学习记录持久化",
            ],
            narration=(
                "测验功能由三个页面和三个 DAO 类协同工作。"
                "QuizPage 是核心主页，负责章节选择和题目作答的全部交互逻辑。"
                "WrongAnswersPage 是独立页面，展示用户历史答错的题目并支持移除和清空。"
                "ProgressPage 以 TabView 形式呈现测验成绩和学习记录两组统计数据。"
                "底层由 QuizDao、WrongAnswerDao、LearningRecordDao 三个 DAO 类封装 SQLite 数据库操作，"
                "UI 层通过调用 DAO 方法获取数据，实现了良好的关注点分离。"
            ),
            image_path=crops.get("framework_dao"),
            image_caption="DAO 层架构：三 DAO 类封装 SQLite 操作",
        ),
        # ── 3 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="章节选择界面",
            subtitle="_chapters 列表 · _loadChapters() · _quizStarted 状态控制",
            bullets=[
                "initState() → _loadChapters()，首次进入自动加载章节",
                "_isLoading=true 时显示 CircularProgressIndicator",
                "_chapters 为空 → 显示「暂无测验题目」+ 刷新按钮",
                "每个章节 → Card + ListTile，onTap: _startQuiz(chapter)",
                "末尾固定「错题本」Card，颜色 Colors.red[50]，导航至 WrongAnswersPage",
            ],
            narration=(
                "章节选择界面是 QuizPage 的初始状态，由状态变量 _quizStarted 控制显示，"
                "默认值为 false，因此进入页面首先看到的是章节列表。"
                "页面初始化时 initState 调用 _loadChapters 方法，从 QuizDao 异步获取所有可用章节。"
                "加载期间显示进度圈，加载完成后以 ListView 形式展示各章节，每个章节是一个可点击的 Card。"
                "列表末尾有一个带红色背景的「错题本」Card，点击后导航至 WrongAnswersPage 进行错题复习。"
            ),
            image_path=shots.get("chapter_select"),
            image_caption="章节选择界面：Card 列表 + 错题本入口",
        ),
        # ── 4 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="QuizDao.getChapters()",
            subtitle="SELECT DISTINCT source · WHERE 过滤空值 · ORDER BY 排序",
            bullets=[
                "rawQuery 执行 DISTINCT 去重查询",
                "WHERE source IS NOT NULL AND source != '' 过滤无效记录",
                "ORDER BY source 按字母顺序排列章节",
                "source 字段 = QuestionModel.source，题目导入时按章节分组",
                "异常时 catch 返回空列表，UI 显示「暂无测验题目」",
            ],
            narration=(
                "getChapters 方法通过 rawQuery 执行 SQL 查询，"
                "利用 DISTINCT 关键字对 source 字段去重，确保每个章节只出现一次。"
                "WHERE 子句过滤掉 source 为空或空字符串的题目，避免出现空白章节项。"
                "ORDER BY source 保证章节按字母顺序稳定排列，每次加载结果一致。"
                "source 字段是 questions 表中标识题目所属章节的核心字段，"
                "题目导入时按章节分组填写，getChapters 和 getQuestionsByChapter 都依赖这个字段工作。"
            ),
            image_path=shots.get("chapter_select"),
            image_caption="getChapters → DISTINCT source 去重查询",
            code_title="QuizDao.getChapters()  SQL",
            code_text=(
                "final maps = await db.rawQuery(\n"
                "  'SELECT DISTINCT source FROM questions'\n"
                "  ' WHERE source IS NOT NULL'\n"
                "  '   AND source != \"\"'\n"
                "  ' ORDER BY source',\n"
                ");\n"
                "return maps\n"
                "  .map((m) => m['source'] as String)\n"
                "  .toList();"
            ),
        ),
        # ── 5 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="开始测验 _startQuiz()",
            subtitle="加载题目 · 重置状态机 · _quizStarted=true 切换视图",
            bullets=[
                "设置 _selectedChapter，_isLoading=true 显示加载中",
                "await QuizDao.getQuestionsByChapter(chapter)",
                "SQL: SELECT * FROM questions WHERE source = ?",
                "重置状态：_currentIndex=0，_correctCount=0，_selectedAnswer=null，_answered=false",
                "_quizStarted=true → build() 条件判断切换到 _buildQuizView()",
            ],
            narration=(
                "用户选择章节后，_startQuiz 方法首先将加载状态置为 true，"
                "然后调用 QuizDao 的 getQuestionsByChapter 方法，"
                "通过 source 字段过滤该章节的所有题目并以列表形式返回。"
                "加载成功后，方法在 setState 中集中重置所有状态变量："
                "当前题目索引归零、正确计数归零、选中答案清空、答题标志清空。"
                "最关键的一步是将 _quizStarted 设为 true，"
                "这会触发 build 方法中的条件判断，从章节选择视图切换到题目作答视图。"
            ),
            image_path=shots.get("submit_flow"),
            image_caption="_startQuiz：加载题目 → 重置状态 → 切换视图",
            code_title="_startQuiz() 核心逻辑",
            code_text=(
                "final questions = await _quizDao\n"
                "    .getQuestionsByChapter(chapter);\n"
                "setState(() {\n"
                "  _questions   = questions;\n"
                "  _quizStarted = true;\n"
                "  _currentIndex    = 0;\n"
                "  _correctCount    = 0;\n"
                "  _selectedAnswer  = null;\n"
                "  _answered        = false;\n"
                "  _isLoading       = false;\n"
                "});"
            ),
        ),
        # ── 6 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="题目界面布局",
            subtitle="LinearProgressIndicator · 题目文字 · 4 选项 · 操作按钮",
            bullets=[
                "顶部 LinearProgressIndicator：value=(index+1)/total，实时进度",
                "Expanded + SingleChildScrollView：内容超长时支持滚动",
                "题目文字：fontSize 18，fontWeight.bold，题号灰色显示",
                "List.generate(4) 动态生成 A/B/C/D 选项",
                "底部固定 ElevatedButton，height=48，随状态切换文字和可用性",
            ],
            narration=(
                "题目界面使用 Column 布局，从上到下分为三个区域。"
                "顶部是 LinearProgressIndicator，显示当前题目在整个测验中的进度比例，"
                "value 等于当前索引加一除以总题数，随答题实时更新。"
                "中间是 Expanded 包裹的 SingleChildScrollView，"
                "内含题目文字和四个选项按钮，支持题目内容超长时滚动查看。"
                "底部是固定高度四十八像素的 ElevatedButton，"
                "在未选择时禁用、选择后可提交、提交后切换为下一题或完成测验，"
                "三种状态由 _answered 和 _selectedAnswer 共同驱动。"
            ),
            image_path=shots.get("quiz_question"),
            image_caption="题目界面：进度条 + 题目 + 4选项 + 操作按钮",
        ),
        # ── 7 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="选项颜色状态反馈",
            subtitle="isSelected / isCorrect / _answered — 三状态颜色机",
            bullets=[
                "未选择：border=grey[300]，背景透明，borderWidth=1",
                "已选中（未提交）：蓝紫色边框 + 30% 透明背景",
                "提交后 正确选项：green[100] 背景 + green 边框，width=2",
                "提交后 选错选项：red[100] 背景 + red 边框，width=2",
                "CircleAvatar：选中时填充边框色 + 白色 Icons.check(size 16)",
            ],
            narration=(
                "选项按钮的颜色由三个变量共同决定：isSelected 表示该选项是否被选中，"
                "isCorrect 表示该选项是否是正确答案，_answered 表示是否已提交。"
                "提交前，选中项显示蓝紫色高亮，其余保持灰色边框。"
                "提交后，无论用户选对还是选错，正确选项都会高亮为绿色，"
                "用户答错的选项变为红色，正确答案始终可见，帮助用户即时学习和记忆。"
                "这种设计模式常见于教育类 App，即时反馈显著优于延迟反馈的学习效果。"
            ),
            image_path=shots.get("color_feedback"),
            image_caption="三状态颜色：未选(灰) → 选中(蓝) → 答后正确(绿)/错误(红)",
            code_title="选项颜色逻辑（_answered 驱动）",
            code_text=(
                "if (_answered) {\n"
                "  if (isCorrect) {\n"
                "    bgColor     = Colors.green[100];\n"
                "    borderColor = Colors.green;\n"
                "  } else if (isSelected && !isCorrect) {\n"
                "    bgColor     = Colors.red[100];\n"
                "    borderColor = Colors.red;\n"
                "  }\n"
                "} else if (isSelected) {\n"
                "  bgColor     = Color(0xFF667eea).withOpacity(0.3);\n"
                "  borderColor = Color(0xFF667eea);\n"
                "}"
            ),
        ),
        # ── 8 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="提交答案 _submitAnswer()",
            subtitle="前置检查 · 判断正误 · 错题记录 · setState 触发重建",
            bullets=[
                "前置检查：_selectedAnswer == null → return，保证按钮禁用有效",
                "取当前题：final q = _questions[_currentIndex]",
                "isCorrect = _selectedAnswer == q.answerIndex",
                "答错 → _recordWrongAnswer(q)  异步执行，不阻塞 UI",
                "_answered=true，isCorrect → _correctCount++ → setState 刷新",
            ],
            narration=(
                "_submitAnswer 是提交答案的核心方法。"
                "首先检查是否已选择选项，未选择则直接返回，这与按钮的 onPressed 为 null 的禁用逻辑配合。"
                "然后取出当前题目，将用户选择的索引与题目的 answerIndex 比对，判断是否正确。"
                "如果答错，立即调用 _recordWrongAnswer 方法异步记录错题，"
                "由于错题记录是异步且有 try-catch 保护，不会阻塞或影响当前界面响应。"
                "最后通过 setState 将 _answered 设为 true 并更新正确计数，"
                "触发 UI 重建使颜色反馈立即生效，按钮文字也同步切换为「下一题」。"
            ),
            image_path=shots.get("submit_flow"),
            image_caption="_submitAnswer：判断 → 记录错题 → setState 刷新",
            code_title="_submitAnswer() 完整实现",
            code_text=(
                "void _submitAnswer() {\n"
                "  if (_selectedAnswer == null) return;\n"
                "  final q = _questions[_currentIndex];\n"
                "  final ok = _selectedAnswer == q.answerIndex;\n"
                "  if (!ok) _recordWrongAnswer(q);  // 异步\n"
                "  setState(() {\n"
                "    _answered = true;\n"
                "    if (ok) _correctCount++;\n"
                "  });\n"
                "}"
            ),
        ),
        # ── 9 ──────────────────────────────────────────────────────────────
        SlideSpec(
            title="错题记录 WrongAnswerDao.addWrongAnswer()",
            subtitle="重复检测 · INSERT or UPDATE · times 错误计数累加",
            bullets=[
                "先查：SELECT WHERE user_id=? AND question_id=?",
                "已存在 → UPDATE: times=currentTimes+1，last_wrong_time=now()",
                "不存在 → INSERT: 全字段，times=1，wrong_time=now()",
                "字段：userId / questionId / question / userAnswer / correctAnswer / chapter",
                "try-catch 静默处理异常，错题失败不影响测验主流程",
            ],
            narration=(
                "_recordWrongAnswer 方法调用 WrongAnswerDao 的 addWrongAnswer 方法记录错题。"
                "该方法首先查询 wrong_answers 表，检查该用户对该题目是否已有错误记录。"
                "若已存在，执行 UPDATE 将 times 加一并更新 last_wrong_time；"
                "若不存在，执行 INSERT 写入完整记录，times 初始为一。"
                "这个设计使得错题本能够追踪每道题的错误频率，"
                "错误次数越多，CircleAvatar 中显示的数字越大，帮助用户快速定位高频错题。"
                "整个操作在 try-catch 中执行，任何数据库异常都被静默处理。"
            ),
            image_path=shots.get("wrong_answer_dao"),
            image_caption="WrongAnswerDao：先查后判，INSERT or UPDATE times++",
            code_title="addWrongAnswer() 重复检测与写入",
            code_text=(
                "final existing = await db.query('wrong_answers',\n"
                "  where: 'user_id=? AND question_id=?',\n"
                "  whereArgs: [userId, questionId]);\n"
                "if (existing.isNotEmpty) {\n"
                "  final t = (existing.first['times'] as int?) ?? 1;\n"
                "  await db.update('wrong_answers',\n"
                "    {'times': t+1, 'last_wrong_time': now},\n"
                "    where: 'user_id=? AND question_id=?');\n"
                "} else {\n"
                "  await db.insert('wrong_answers', {full_fields});\n"
                "}"
            ),
        ),
        # ── 10 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="QuestionModel 题目数据模型",
            subtitle="source · optionA~D · answerIndex · options / correctAnswer getter",
            bullets=[
                "source：题目所属章节，对应 questions 表 source 字段",
                "question：题目文字",
                "optionA / B / C / D：四个选项文字，分列存储",
                "answerIndex：正确答案序号 0~3，对应 A~D",
                "get options → [optionA, optionB, optionC, optionD]",
                "get correctAnswer → switch(answerIndex) 转换为文字",
            ],
            narration=(
                "QuestionModel 是题目的数据模型，对应数据库 questions 表的字段结构。"
                "source 字段标识题目所属章节，是章节分组查询的核心依据。"
                "四个选项分别以 optionA 至 optionD 存储，answerIndex 记录正确答案的序号，从零开始。"
                "模型提供两个便捷 getter：options 返回选项字符串列表，"
                "用于 List.generate 中按索引取对应选项文字；"
                "correctAnswer 通过 switch 将 answerIndex 转换为对应的选项文字，"
                "直接用于写入错题记录的 correctAnswer 字段，避免在 UI 层重复转换逻辑。"
            ),
            image_path=shots.get("quiz_result_model"),
            image_caption="QuestionModel：source / options getter / answerIndex",
            code_title="QuestionModel getter 实现",
            code_text=(
                "List<String> get options =>\n"
                "  [optionA, optionB, optionC, optionD];\n\n"
                "String get correctAnswer {\n"
                "  switch (answerIndex) {\n"
                "    case 0: return optionA;\n"
                "    case 1: return optionB;\n"
                "    case 2: return optionC;\n"
                "    case 3: return optionD;\n"
                "    default: return '';\n"
                "  }\n"
                "}"
            ),
        ),
        # ── 11 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="QuizResultModel 成绩数据模型",
            subtitle="userId · score · numCorrect · numTotal · chapter · 双时间戳",
            bullets=[
                "userId：关联当前登录用户 ID（AuthService.currentUser）",
                "score：百分制得分，_finishQuiz 中计算并取整",
                "numCorrect / numTotal：答对题数 / 测验总题数",
                "chapter：章节名（可 null，ProgressPage 显示「综合测验」）",
                "quizTimestamp：开始时间；completedAt：完成时间（ISO 8601）",
                "accuracy getter：numTotal>0 ? numCorrect/numTotal*100 : 0",
            ],
            narration=(
                "QuizResultModel 是保存测验成绩的数据模型，对应 quiz_results 表。"
                "score 字段存储百分制得分，在 _finishQuiz 方法中计算，"
                "公式为答对题数除以总题数乘以一百后取整。"
                "chapter 字段可以为空，为空时 ProgressPage 的历史记录列表显示「综合测验」。"
                "时间戳字段使用 ISO 8601 格式的字符串存储，"
                "quizTimestamp 记录测验开始时间，completedAt 记录完成时间，两者均在 _finishQuiz 中赋值。"
                "accuracy getter 提供一个便捷的正确率计算属性，防止除以零的边界情况。"
            ),
            image_path=shots.get("quiz_result_model"),
            image_caption="QuizResultModel：成绩实体 → quiz_results 表映射",
            code_title="QuizResultModel 构造（_finishQuiz 中）",
            code_text=(
                "final result = QuizResultModel(\n"
                "  userId:         user.userId,\n"
                "  quizTimestamp:  DateTime.now().toIso8601String(),\n"
                "  score: ((_correctCount / _questions.length)\n"
                "          * 100).round(),\n"
                "  numCorrect: _correctCount,\n"
                "  numTotal:   _questions.length,\n"
                "  chapter:    _selectedChapter,\n"
                "  completedAt: DateTime.now().toIso8601String(),\n"
                ");"
            ),
        ),
        # ── 12 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="测验完成 _finishQuiz()",
            subtitle="构造结果 · saveQuizResult · AlertDialog · barrierDismissible=false",
            bullets=[
                "获取当前用户：_authService.currentUser，null 则直接返回",
                "构造 QuizResultModel，score=(correctCount/total*100).round()",
                "await QuizDao.saveQuizResult(result) → INSERT quiz_results",
                "showDialog(barrierDismissible: false) 强制查看结果",
                "图标：>total/2 → celebration 绿色；否则 sentiment_neutral 橙色",
                "「确定」→ Navigator.pop，_quizStarted=false 返回章节选择",
            ],
            narration=(
                "_finishQuiz 在最后一题点击「完成测验」后执行。"
                "首先从 AuthService 获取当前用户，如果未登录则直接返回，避免空指针。"
                "然后构造完整的 QuizResultModel 并调用 saveQuizResult 写入数据库。"
                "成绩保存完毕后，通过 showDialog 弹出结果对话框，"
                "barrierDismissible 设为 false 强制用户主动点击「确定」，而不能通过点击外部关闭。"
                "对话框根据得分显示不同图标和颜色，超过一半题目正确显示庆祝图标和绿色，否则中性橙色。"
                "用户点击「确定」后页面回到章节选择，等待下一次测验。"
            ),
            image_path=shots.get("quiz_result"),
            image_caption="_finishQuiz：保存成绩 → AlertDialog → 返回章节选择",
            code_title="_finishQuiz() 关键步骤",
            code_text=(
                "await _quizDao.saveQuizResult(result);\n"
                "if (mounted) showDialog(\n"
                "  context: context,\n"
                "  barrierDismissible: false,\n"
                "  builder: (_) => AlertDialog(\n"
                "    title: Text('测验完成'),\n"
                "    content: Column(children: [\n"
                "      Icon(ok ? Icons.celebration\n"
                "              : Icons.sentiment_neutral),\n"
                "      Text('得分: ${result.score}分'),\n"
                "      Text('正确: $_correctCount / $total'),\n"
                "    ]),\n"
                "  ));"
            ),
        ),
        # ── 13 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="QuizDao — 保存与查询成绩",
            subtitle="saveQuizResult · getQuizResults · getQuizSummary 聚合",
            bullets=[
                "saveQuizResult → db.insert('quiz_results', result.toMap())",
                "getQuizResults(userId) → ORDER BY quiz_timestamp DESC，按时间倒序",
                "getQuizSummary：COUNT / SUM(num_correct) / SUM(num_total) / AVG(score)",
                "聚合返回：total_count / total_correct / total_questions / avg_score",
                "ProgressPage 直接用 summary Map 渲染三张统计卡片，无需前端计算",
            ],
            narration=(
                "QuizDao 提供三个成绩相关方法，层次清晰。"
                "saveQuizResult 最简单，直接调用 db.insert 将 toMap 的结果写入 quiz_results 表。"
                "getQuizResults 按时间倒序返回用户的历史成绩列表，用于 ProgressPage 的历史记录区域。"
                "最强大的是 getQuizSummary，它执行包含四个聚合函数的 SQL 语句，"
                "一次查询同时返回测验次数、总答对题数、总题数和平均分，"
                "ProgressPage 的三张统计卡片直接使用这个 Map 的值，不需要在 Dart 代码中做额外统计运算。"
            ),
            image_path=shots.get("progress_quiz_tab"),
            image_caption="saveQuizResult → getQuizSummary → ProgressPage 三卡片",
            code_title="getQuizSummary SQL 聚合查询",
            code_text=(
                "SELECT\n"
                "  COUNT(*)          as total_count,\n"
                "  SUM(num_correct)  as total_correct,\n"
                "  SUM(num_total)    as total_questions,\n"
                "  AVG(score)        as avg_score\n"
                "FROM quiz_results\n"
                "WHERE user_id = ?"
            ),
        ),
        # ── 14 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="错题本 WrongAnswersPage",
            subtitle="ExpansionTile 可折叠 · 答案对比 · 移除 / 清空操作",
            bullets=[
                "initState → WrongAnswerDao.getWrongAnswers(userId)，时间倒序",
                "ListView.builder + Card + ExpansionTile 可折叠列表",
                "Avatar 显示 times 字段（错误次数），红色背景红色字",
                "展开内容：题目全文 / 你的答案(红) / 正确答案(绿) 三行对比",
                "移除：removeWrongAnswer(id)；清空：clearWrongAnswers(userId) + 确认对话框",
            ],
            narration=(
                "WrongAnswersPage 通过 WrongAnswerDao 的 getWrongAnswers 方法加载当前用户的所有错题。"
                "列表使用 ExpansionTile 实现可折叠效果，折叠时显示题目摘要和错误次数，展开后显示完整内容。"
                "圆形 Avatar 显示 wrong_answers 表的 times 字段，红色背景直观反映该题的薄弱程度，"
                "数字越大说明这道题错了越多次，需要重点复习。"
                "展开后可以清晰对比你的答案和正确答案，红色和绿色的对比帮助加强记忆。"
                "AppBar 右侧的扫帚图标触发确认对话框，确认后清空当前用户全部错题记录。"
            ),
            image_path=shots.get("wrong_answers_page"),
            image_caption="WrongAnswersPage：ExpansionTile + 答案对比 + 操作按钮",
        ),
        # ── 15 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="ProgressPage — 测验成绩 Tab",
            subtitle="三统计卡片 · fl_chart 折线图 · 历史记录列表",
            bullets=[
                "TabController(length:2)：测验成绩 / 学习记录",
                "_buildStatCard：测验次数(蓝) / 平均分(绿) / 正确率(橙) 三张 Row",
                "if (_results.isNotEmpty) → SizedBox(h:200, _buildChart())",
                "_results.take(10) → 最多显示最近10条历史记录",
                "Avatar 显示 score，>=60 → 绿色，<60 → 红色",
            ],
            narration=(
                "ProgressPage 使用 TabController 管理两个 Tab，两个 Tab 共用同一份 _loadData 加载的数据。"
                "测验成绩 Tab 顶部是三张并排统计卡片，分别显示测验次数、平均分和正确率，"
                "数据来自 getQuizSummary 的聚合查询结果，蓝绿橙三色区分。"
                "若存在历史成绩，卡片下方显示 fl_chart 折线图，高度固定两百像素，展示成绩变化趋势。"
                "最下方历史记录列表最多显示最近十条，每条以圆形 Avatar 展示分数，"
                "六十分及以上为绿色，否则为红色，一眼区分成绩优劣。"
            ),
            image_path=shots.get("progress_quiz_tab"),
            image_caption="ProgressPage 测验成绩Tab：卡片 + 折线图 + 记录列表",
        ),
        # ── 16 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="fl_chart LineChart 成绩趋势",
            subtitle="FlSpot · isCurved · barWidth · belowBarData 半透明填充",
            bullets=[
                "_results.reversed → asMap().entries → FlSpot(index.toDouble(), score.toDouble())",
                "Y轴范围：minY=0, maxY=100，固定百分制刻度",
                "isCurved=true → B 样条曲线，视觉更平滑",
                "color=0xFF667eea, barWidth=3, dotData(show:true) 显示节点圆点",
                "belowBarData: BarAreaData(color=0xFF667eea + alpha=0.1) 半透明填充",
            ],
            narration=(
                "_buildChart 方法构建 fl_chart 的折线图，数据转换是理解这段代码的关键。"
                "首先对历史成绩列表调用 reversed 倒序，使图表从左到右按时间顺序排列，"
                "再用 asMap 获取数值索引，将每条记录的 index 作为 X 轴坐标，score 作为 Y 轴坐标构造 FlSpot。"
                "图表的 Y 轴固定在零到一百，清晰反映百分制得分变化。"
                "折线启用 isCurved 使曲线平滑，配合蓝紫色主题色和 alpha 值仅 0.1 的半透明下方填充，"
                "在保持专业感的同时视觉上突出成绩趋势。"
            ),
            image_path=shots.get("fl_chart"),
            image_caption="fl_chart：FlSpot 数据 → LineChart → 蓝色平滑曲线",
            code_title="_buildChart() FlSpot 数据构造",
            code_text=(
                "final spots = _results.reversed\n"
                "  .toList().asMap().entries\n"
                "  .map((e) => FlSpot(\n"
                "    e.key.toDouble(),\n"
                "    e.value.score.toDouble()))\n"
                "  .toList();\n"
                "// isCurved=true, barWidth=3\n"
                "// belowBarData alpha=0.1 填充"
            ),
        ),
        # ── 17 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="ProgressPage — 学习记录 Tab",
            subtitle="LearningRecordDao.getStatistics() · 三卡片 · 四条学习建议",
            bullets=[
                "getStatistics(userId) 执行三条独立 SQL 查询",
                "total_records：COUNT(*) 全部学习行为总数",
                "unique_nodes：COUNT(DISTINCT node_id) 覆盖知识节点数",
                "this_week：completed_at >= date('now','-7 days') 本周活跃度",
                "学习建议 4条：每天1-2h / 先学基础图谱 / 测验巩固 / 错题反复练",
            ],
            narration=(
                "学习记录 Tab 同样使用三张统计卡片，数据来自 LearningRecordDao 的 getStatistics 方法。"
                "该方法执行三条独立 SQL 查询：总记录数统计用户全部的学习行为，"
                "独立节点数通过 COUNT DISTINCT 去重统计已覆盖的知识节点数量，"
                "反映学习的广度；本周学习数通过日期条件过滤最近七天的活跃度。"
                "卡片下方是学习建议卡片，包含四条具体可操作的建议。"
                "这四条建议呼应了整个 App 的学习闭环设计：学图谱、做测验、查错题、重复练，"
                "形成记忆巩固的正向循环。"
            ),
            image_path=shots.get("progress_learning_tab"),
            image_caption="学习记录Tab：getStatistics 三查询 + 四条学习建议",
            code_title="getStatistics() 三条 SQL 查询",
            code_text=(
                "// 1. 总学习记录数\n"
                "SELECT COUNT(*) FROM learning_records\n"
                "  WHERE user_id = ?\n\n"
                "// 2. 独立节点数\n"
                "SELECT COUNT(DISTINCT node_id) FROM learning_records\n"
                "  WHERE user_id = ?\n\n"
                "// 3. 本周学习数\n"
                "WHERE completed_at >= date('now', '-7 days')"
            ),
        ),
        # ── 18 ─────────────────────────────────────────────────────────────
        SlideSpec(
            title="功能总结与数据流",
            subtitle="五环节闭环 · DAO 层解耦 · 可视化学习成果",
            bullets=[
                "① 章节选择：getChapters() → DISTINCT source → ListView",
                "② 题目加载：getQuestionsByChapter() → WHERE source=? → List",
                "③ 答题反馈：三状态颜色机 + _answered 驱动 setState 重建",
                "④ 错题记录：addWrongAnswer() → INSERT/UPDATE times++ → 错题本",
                "⑤ 成绩保存→统计：saveQuizResult() → getQuizSummary() → fl_chart",
            ],
            narration=(
                "测验功能通过五个环节形成完整的学习闭环。"
                "章节选择利用 SQL DISTINCT 查询，将题库按 source 字段自动分组，无需手动维护章节列表。"
                "题目加载通过 WHERE source 过滤，精准获取当前章节所有题目。"
                "答题过程中三状态颜色机制提供即时反馈，isSelected、isCorrect、_answered 三个变量协同驱动 UI。"
                "答错的题目自动写入错题本并支持重复计次，错误频率可视化帮助用户定位薄弱点。"
                "每次测验完成后成绩以结构化模型写入数据库，ProgressPage 通过 SQL 聚合和 fl_chart 将进度可视化展示。"
                "感谢观看测验功能教学视频！"
            ),
            image_path=shots.get("data_flow"),
            image_caption="五环节闭环：章节选择 → 作答 → 错题 → 保存 → 统计可视化",
        ),
    ]


# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════
def main() -> None:
    print("=" * 64)
    print("  gen_quiz_v6 — 测验功能教学视频生成器")
    print("=" * 64)

    FEAT_DIR.mkdir(parents=True, exist_ok=True)

    print("\n[Step 1/6] 生成 UML 裁切图 …")
    crops = generate_uml_crops(CROPS_DIR)
    print(f"  已生成 {len(crops)} 张 UML 裁切图")

    print("\n[Step 2/6] 生成 Mock 界面截图 …")
    shots = build_feature_shots(CROPS_DIR)
    print(f"  已生成 {len(shots)} 张 Mock 截图")

    print("\n[Step 3/6] 组装 Slides …")
    slides = build_slides(crops, shots)
    print(f"  共 {len(slides)} 页 slides")

    print("\n[Step 4/6] TTS 语音合成 + 视频编码 …")
    base_paths, ok = build_video(slides, FEAT_DIR, VIDEO_PATH, SRT_PATH)

    print("\n[Step 5/6] 输出 PPTX …")
    build_pptx(slides, base_paths, PPTX_PATH)

    print("\n[Step 6/6] 输出讲解脚本 Markdown …")
    build_script(slides, SCRIPT_PATH, "测验")

    # ── 汇总报告 ────────────────────────────────────────────────────────────
    print("\n" + "=" * 64)
    print("  生成完毕！")
    print(f"  Video  → {VIDEO_PATH}")
    print(f"  PPTX   → {PPTX_PATH}")
    print(f"  SRT    → {SRT_PATH}")
    print(f"  Script → {SCRIPT_PATH}")
    if ok and VIDEO_PATH.exists():
        size_mb = VIDEO_PATH.stat().st_size / 1024 / 1024
        print(f"  视频大小: {size_mb:.1f} MB")
        # 估算总时长：sum of all clip durations
        try:
            from moviepy.editor import VideoFileClip

            clip = VideoFileClip(str(VIDEO_PATH))
            dur = clip.duration
            clip.close()
            mins = int(dur // 60)
            secs = dur % 60
            print(f"  视频时长: {mins}分{secs:.1f}秒")
        except Exception:
            pass
    print("=" * 64)


if __name__ == "__main__":
    main()
