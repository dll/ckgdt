import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/role_guard.dart';
import '../core/init_logger.dart';

import '../presentation/pages/quiz/quiz_page.dart';
import '../presentation/pages/archive/archive_page.dart';
import '../presentation/pages/quiz/wrong_answers_page.dart';
import '../presentation/pages/class_qa/class_qa_page.dart';
import '../presentation/pages/learning/learning_hub_page.dart';
import '../presentation/pages/learning/video_page.dart';
import '../presentation/pages/learning/document_page.dart';
import '../presentation/pages/learning/progress_page.dart';
import '../presentation/pages/learning/learning_plan_page.dart';
import '../presentation/pages/learning/weakness_diagnosis_page.dart';
import '../presentation/pages/materials/ai_settings_page.dart';
import '../presentation/pages/materials/courseware_workshop_page.dart';
import '../presentation/pages/home/settings_page.dart';
import '../presentation/pages/home/search_page.dart';
import '../presentation/pages/graph/favorites_page.dart';
import '../presentation/pages/practice/deep_practice_page.dart';
import '../presentation/pages/practice/growth_curve_page.dart';
import '../presentation/pages/notification/notification_list_page.dart';
import '../presentation/pages/sync/data_sync_page.dart';
import '../presentation/pages/cross_platform/cross_platform_hub_page.dart';
import '../presentation/pages/help/handbook_page.dart';
import '../presentation/pages/profile/student_center_page.dart';
import '../presentation/pages/profile/teacher_workspace_page.dart';
import '../presentation/pages/profile/chat_history_page.dart';
import '../presentation/pages/skill/ai_skill_page.dart';
import '../presentation/pages/feedback/feedback_manage_page.dart';
import '../presentation/pages/settings/voice_settings_page.dart';
import '../presentation/pages/settings/course_manage_page.dart';
import '../presentation/pages/admin/class_manage_page.dart';
import '../presentation/pages/admin/data_export_page.dart';
import '../presentation/pages/admin/data_import_page.dart';
import '../presentation/pages/admin/grade_entry_center_page.dart';
import '../presentation/pages/admin/lab_task_manage_page.dart';
import '../presentation/pages/admin/question_manage_page.dart';
import '../presentation/pages/admin/release_center_page.dart';
import '../presentation/pages/admin/repo_analytics_page.dart';
import '../presentation/pages/admin/student_manage_page.dart';
import '../presentation/pages/admin/survey_manage_page.dart';
import '../presentation/pages/admin/teacher_manage_page.dart';
import '../presentation/pages/admin/teaching_manage_page.dart';
import '../presentation/pages/admin/teacher_application_page.dart';
import '../presentation/pages/admin/teacher_application_manage_page.dart';
import '../presentation/pages/notification/notification_manage_page.dart';
import '../presentation/pages/repo/git_repo_page.dart';
import '../presentation/pages/repo/student_repo_page.dart';
import '../presentation/pages/hot/hot_videos_page.dart';
import '../presentation/pages/analytics/token_stats_page.dart';
import '../presentation/pages/analytics/student_token_page.dart';
import '../presentation/pages/analytics/class_token_page.dart';
import '../presentation/pages/analytics/agent_calls_dashboard_page.dart';
import '../presentation/pages/privacy/privacy_policy_page.dart';
import '../presentation/pages/privacy/my_data_page.dart';
import '../services/auth_service.dart';

/// 全局导航服务 — 跨页面 Tab 切换 + 子页面跳转 + 返回
///
/// 单例模式，由 HomePage 注册回调，供智能体等模块触发导航。
class NavigationService {
  static final NavigationService instance = NavigationService._();
  NavigationService._();

  /// HomePage 注册的 Tab 切换回调
  void Function(int tabIndex)? onSwitchTab;

  /// 全局 NavigatorState key（由 main.dart 提供）
  GlobalKey<NavigatorState>? navigatorKey;

  /// 关键词 → Tab 索引映射（角色感知）
  /// 由 HomePage 在 build 时动态注册
  Map<String, int> _tabMapping = {};

  /// 注册 Tab 映射
  void registerTabMapping(Map<String, int> mapping) {
    _tabMapping = mapping;
  }

  /// 切换到指定 Tab
  void switchToTab(int index) {
    onSwitchTab?.call(index);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 内层 Tab 总线（语音 → 顶层 Tab → 内层 TabController）
  //
  // 语音命令"打开考核的报告"分两步：
  //   1. switchToTab(顶层"考核") — HomePage 切换底部 NavigationBar
  //   2. requestInnerTab('assessment','报告') — 在总线上挂一个待消费请求，
  //      AssessmentPage 挂载后通过 consumeInnerTab 拿到并切自己的 TabController
  //
  // innerTabSeq 每次自增触发监听者回调；同一 page 监听自己的 pageKeyword，
  // 不属于自己的请求会被 consume 时跳过（保留给真正目标 page）。
  // ─────────────────────────────────────────────────────────────────────────

  /// 待处理的内层 tab 切换请求
  PendingInnerTabRequest? _pendingInnerTab;

  /// 序列号 ValueNotifier — 每次 requestInnerTab 自增 1，page 监听此变化
  /// （比直接监听 _pendingInnerTab 简单，避免 Map<page, listener> 复杂化）
  final ValueNotifier<int> innerTabSeq = ValueNotifier<int>(0);

  /// 提交一个内层 tab 切换请求
  ///
  /// [pageKeyword]：父页面标识（'assessment' / 'works' / ...）
  /// [tabKeyword]：内层 tab 关键词（如 '报告' / 'AI批阅'），由 page 自己解析为 idx
  void requestInnerTab(String pageKeyword, String tabKeyword) {
    final role = AuthService().currentUser?.role ?? 'student';
    if (!RoleGuard.canAccessInnerPage(role, pageKeyword)) {
      InitLogger.log('nav',
          'requestInnerTab denied role=$role page=$pageKeyword tab=$tabKeyword');
      return;
    }
    _pendingInnerTab = PendingInnerTabRequest(pageKeyword, tabKeyword);
    innerTabSeq.value = innerTabSeq.value + 1;
  }

  /// 消费匹配的内层 tab 请求 — page 在 build 后调用
  ///
  /// 仅当待处理请求的 pageKeyword 与传入参数匹配时返回；否则返回 null
  /// （让其他 page 有机会消费）。一旦消费即清空，避免重复触发。
  PendingInnerTabRequest? consumeInnerTab(String pageKeyword) {
    final req = _pendingInnerTab;
    if (req != null && req.pageKeyword == pageKeyword) {
      _pendingInnerTab = null;
      return req;
    }
    return null;
  }

  /// `assessment`/`works`/`lab`/... → 顶层 NavigationBar 的中文 label
  ///
  /// 教师 6 Tab：教学（教学+课堂聚合）、评价（实验+考核+作品聚合）、达成、归档
  /// 学生 6 Tab：学习、实验、考核、作品
  /// 必须与 home_page.dart 注册到 [registerTabMapping] 的 label 保持一致。
  static String? pageKeyToTabLabel(String pageKey, {required bool isTeacher}) {
    if (isTeacher) {
      switch (pageKey) {
        case 'evaluation':
        case 'assessment':
        case 'works':
        case 'lab':
        case 'experiment':
          return '评价';
        case 'achievement':
          return '达成';
        case 'archive':
          return '归档';
        case 'teaching':
        case 'classroom':
        case 'learning':
          return '教学';
      }
    } else {
      switch (pageKey) {
        case 'assessment':
          return '考核';
        case 'works':
        case 'showcase':
          return '作品';
        case 'lab':
        case 'experiment':
          return '实验';
        case 'learning':
          return '学习';
      }
    }
    return null;
  }

  /// VoiceAgent 英文 keyword → 候选中文 tab label（按角色有多个候选）
  ///
  /// VoiceAgent AI 输出的 keyword 是英文（如 'classroom'），
  /// 而 [_tabMapping] 由 HomePage 按角色动态注册（6 Tab 精简结构）。
  /// 本映射提供候选 label 列表，按顺序查找第一个在 _tabMapping 中存在的。
  ///
  /// 教师 Tab：首页 图谱 教学 评价 达成 归档 [+管理]
  /// 学生 Tab：首页 图谱 学习 实验 考核 作品
  static final _voiceKeywordToLabel = <String, List<String>>{
    'home': ['首页'],
    'graph': ['图谱'],
    'learning': ['教学', '学习'],
    'classroom': ['课堂', '教学', '学习'],
    'experiment': ['实验', '评价'],
    'assessment': ['考核', '评价'],
    'showcase': ['作品', '评价'],
    'achievement': ['达成'],
    'archive': ['归档'],
    'admin': ['管理'],
    'settings': ['设置'],
    'git': ['仓库'],
    'notification': ['通知'],
    'sync': ['同步'],
    // 以下非顶层 Tab，由 navigate_sub_page 处理
    'quiz': ['测验'],
    'video': ['视频'],
  };

  /// 根据关键词导航到对应 Tab
  /// 返回 true 表示成功匹配并导航
  bool navigateByKeyword(String keyword) {
    final normalized = keyword.toLowerCase();
    InitLogger.log('nav',
        'navigateByKeyword keyword=$keyword normalized=$normalized tabMapping keys=${_tabMapping.keys.toList()}');

    // 0) 英文 keyword（VoiceAgent AI 输出）→ 中文 Tab label
    final labels = _voiceKeywordToLabel[normalized];
    if (labels != null) {
      for (final label in labels) {
        final idx = _tabMapping[label];
        if (idx != null) {
          InitLogger.log('nav',
              'navigateByKeyword voiceKey $normalized → label=$label → idx=$idx');
          switchToTab(idx);
          return true;
        }
      }
      InitLogger.log('nav',
          'navigateByKeyword voiceKey $normalized labels=$labels none found in tabMapping');
    }

    // 1) 先在动态 Tab 映射中精确查找（角色感知）
    for (final entry in _tabMapping.entries) {
      if (normalized.contains(entry.key)) {
        switchToTab(entry.value);
        return true;
      }
    }

    // 2) 别名 → 标准 Tab 名映射（解析后查动态映射）
    const aliasMap = <String, String>{
      '首页': '首页',
      '主页': '首页',
      '回家': '首页',
      '知识图谱': '图谱',
      '学习中心': '学习',
      '课堂管理': '课堂',
      '实验任务': '实验',
      '考核管理': '考核',
      '考试': '考核',
      '作品展评': '作品',
      '成就': '达成',
      '达成度': '达成',
      '管理面板': '管理',
    };

    // 按别名长度降序匹配（优先匹配更精确的词）
    final sortedAliases = aliasMap.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final alias in sortedAliases) {
      if (normalized.contains(alias.key)) {
        final targetLabel = alias.value;
        if (_tabMapping.containsKey(targetLabel)) {
          switchToTab(_tabMapping[targetLabel]!);
          return true;
        }
      }
    }

    InitLogger.log('nav',
        'navigateByKeyword FAILED keyword=$keyword normalized=$normalized');
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 返回 / 前进 导航
  // ─────────────────────────────────────────────────────────────────────────

  /// 返回上一页（如果可以返回）
  /// 返回 true 表示成功返回，false 表示已在根路由
  bool goBack() {
    final nav = navigatorKey?.currentState;
    if (nav == null) return false;
    if (nav.canPop()) {
      nav.pop();
      return true;
    }
    return false;
  }

  /// 推送新页面
  Future<T?> pushPage<T>(Widget page) async {
    final nav = navigatorKey?.currentState;
    if (nav == null) return null;
    return nav.push<T>(MaterialPageRoute(builder: (_) => page));
  }

  /// 返回到根路由（首页）
  void popToRoot() {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
  }

  /// 导航到登录页（退出登录后）
  void navigateToLogin(Widget loginPage) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => loginPage),
      (route) => false,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 子页面语音导航
  // ─────────────────────────────────────────────────────────────────────────

  /// 子页面关键词 → 路由 ID 映射
  ///
  /// 涵盖所有可通过 Navigator.push 访问的二级/三级页面。
  /// key: 语音关键词（支持多个同义词）
  /// value: 内部路由标识符
  static const subPageKeywords = <String, String>{
    // ── 测验相关 ──
    '测验': 'quiz', '做题': 'quiz', '答题': 'quiz', '考试': 'quiz',
    '错题': 'wrong_answers', '错题本': 'wrong_answers',

    // ── 视频 / 资料 ──
    '视频': 'video', '教程': 'video', '播放': 'video',
    '资料': 'document', '文档': 'document',
    '课件': 'courseware', '课件工坊': 'courseware',

    // ── 学习 ──
    '进度': 'progress', '统计': 'progress', '成绩': 'progress',
    '计划': 'plan', '学习计划': 'plan',
    '学习链': 'learning_chain',
    '薄弱': 'weakness', '薄弱诊断': 'weakness',

    // ── 设置 ──
    '设置': 'settings', '配置': 'settings',
    'ai设置': 'ai_settings', 'ai配置': 'ai_settings',
    '语音设置': 'voice_settings',
    '课程管理': 'course_manage',

    // ── 工具 ──
    '搜索': 'search', '查找': 'search',
    '收藏': 'favorites', '我的收藏': 'favorites',
    '同步': 'sync', '数据同步': 'sync',
    '三端': 'crossplatform', '四端': 'crossplatform', '多端': 'crossplatform',
    '互通': 'crossplatform', '跨平台': 'crossplatform',
    '通知': 'notification', '消息': 'notification',
    '通知管理': 'notification_manage',
    '仓库': 'repo', 'git': 'repo',
    '反馈': 'feedback',
    '帮助': 'handbook', '使用手册': 'handbook',
    '实践': 'practice', '深度实践': 'practice',
    '成长曲线': 'growth_curve',

    // ── 个人中心 ──
    '个人中心': 'student_center', '学生中心': 'student_center',
    '教师工作台': 'teacher_workspace', '工作台': 'teacher_workspace',
    '聊天记录': 'chat_history', '对话记录': 'chat_history',
    'ai技能': 'ai_skill', '技能': 'ai_skill',

    // ── 管理 ──
    '学生管理': 'student_manage',
    '教师管理': 'teacher_manage',
    '班级管理': 'class_manage',
    '题目管理': 'question_manage',
    '题库管理': 'question_manage',
    '数据导出': 'data_export',
    '数据导入': 'data_import',
    '问卷管理': 'survey_manage',
    '教学管理': 'teaching_manage',
    '实验管理': 'lab_manage',
    '仓库分析': 'repo_analytics',
    '成绩录入': 'grade_entry',
    '成绩录入中心': 'grade_entry',
    '构建发布': 'release_center',
    '发布中心': 'release_center',
    '教师申请': 'teacher_application',
    '申请审核': 'teacher_application_manage',
    '教师申请审核': 'teacher_application_manage',

    // ── 推荐 ──
    '推荐': 'hot_videos', '推荐视频': 'hot_videos',

    // ── Token 统计 ──
    'token统计': 'token_stats', 'token': 'token_stats', '用量统计': 'token_stats',
    '学生token': 'student_token', '班级token': 'class_token',
    'ai调用': 'agent_calls', 'agent统计': 'agent_calls', '智能体统计': 'agent_calls',

    // ── 隐私 ──
    '隐私': 'privacy', '协议': 'privacy', '用户协议': 'privacy', '隐私声明': 'privacy',
    '我的数据': 'my_data', '导出我的': 'my_data', '删除我的数据': 'my_data',

    // ── 归档 ──
    '归档': 'archive', '存档': 'archive', '教学材料': 'archive',
    '期初': 'archive', '期中': 'archive', '期末': 'archive',
  };

  /// 尝试通过关键词匹配子页面并导航
  /// 返回匹配的路由 ID（null 表示未匹配）
  String? matchSubPage(String keyword) {
    final normalized = keyword.toLowerCase();

    // 按关键词长度降序匹配（优先匹配更具体的词）
    final sorted = subPageKeywords.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in sorted) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 子页面路由解析（keyword → Widget）
  // ─────────────────────────────────────────────────────────────────────────

  /// 根据路由 ID 创建对应的子页面 Widget
  /// 返回 null 表示路由 ID 无对应页面
  Widget? resolveSubPage(String routeId) {
    final role = AuthService().currentUser?.role ?? 'student';
    final isTeacherOrAdmin = RoleGuard.isTeacherOrAdmin(role);
    if (!RoleGuard.canAccessSubPage(role, routeId)) {
      InitLogger.log('nav', 'resolveSubPage denied role=$role route=$routeId');
      return null;
    }

    switch (routeId) {
      case 'quiz':
        return const QuizPage();
      case 'wrong_answers':
        return const WrongAnswersPage();
      case 'video':
        return const VideoListPage();
      case 'document':
        return const DocumentListPage();
      case 'courseware':
        return isTeacherOrAdmin
            ? const CoursewareWorkshopPage()
            : const LearningHubPage(initialTab: 1);
      case 'progress':
        return const ProgressPage();
      case 'plan':
        return const LearningPlanPage();
      case 'weakness':
        return const WeaknessDiagnosisPage();
      case 'settings':
        return const SettingsPage();
      case 'ai_settings':
        return const AiSettingsPage();
      case 'voice_settings':
        return const VoiceSettingsPage();
      case 'course_manage':
        return const CourseManagePage();
      case 'student_manage':
        return const StudentManagePage();
      case 'teacher_manage':
        return const TeacherManagePage();
      case 'class_manage':
        return const ClassManagePage();
      case 'question_manage':
        return const QuestionManagePage();
      case 'data_import':
        return const DataImportPage();
      case 'data_export':
        return const DataExportPage();
      case 'survey_manage':
        return const SurveyManagePage();
      case 'teaching_manage':
        return const TeachingManagePage();
      case 'lab_manage':
        return const LabTaskManagePage();
      case 'repo_analytics':
        return const RepoAnalyticsPage();
      case 'grade_entry':
        return const GradeEntryCenterPage();
      case 'release_center':
        return const ReleaseCenterPage();
      case 'search':
        return const SearchPage();
      case 'favorites':
        return const FavoritesPage();
      case 'sync':
        return const DataSyncPage();
      case 'crossplatform':
        return const CrossPlatformHubPage();
      case 'notification':
        return const NotificationListPage();
      case 'notification_manage':
        return const NotificationManagePage();
      case 'repo':
        return isTeacherOrAdmin ? const GitRepoPage() : const StudentRepoPage();
      case 'handbook':
        final role = AuthService().currentUser?.role ?? 'student';
        return HandbookPage(role: role);
      case 'practice':
        return const DeepPracticePage();
      case 'growth_curve':
        return const GrowthCurvePage();
      case 'student_center':
        return const StudentCenterPage();
      case 'teacher_workspace':
        return const TeacherWorkspacePage();
      case 'chat_history':
        return const ChatHistoryPage();
      case 'ai_skill':
        return const AiSkillPage(skillId: 'tutor');
      case 'feedback':
        return const FeedbackManagePage();
      case 'class_qa':
      case '班级问答':
      case '问答':
        return const ClassQaPage();
      case 'teacher_application':
        return const TeacherApplicationPage();
      case 'teacher_application_manage':
        return const TeacherApplicationManagePage();
      case 'hot_videos':
        return const HotVideosPage();
      case 'token_stats':
        return const TokenStatsPage();
      case 'student_token':
        return const StudentTokenPage();
      case 'class_token':
        return const ClassTokenPage();
      case 'agent_calls':
        return const AgentCallsDashboardPage();
      case 'privacy':
        return const PrivacyPolicyPage();
      case 'my_data':
        return const MyDataPage();
      case 'archive':
        return const ArchivePage();
      default:
        return null;
    }
  }

  /// 根据关键词匹配子页面并通过 Navigator.push 导航
  /// 返回 true 表示成功匹配并导航
  bool navigateToSubPage(String keyword) {
    final routeId = matchSubPage(keyword);
    if (routeId == null) return false;

    final page = resolveSubPage(routeId);
    if (page == null) return false;

    pushPage(page);
    return true;
  }

  /// 退出应用程序
  void exitApp() {
    SystemNavigator.pop();
  }

  /// 清理回调（HomePage dispose 时调用）
  void dispose() {
    onSwitchTab = null;
    _tabMapping = {};
    _pendingInnerTab = null;
  }
}

/// 待处理的内层 Tab 切换请求 — 由 [NavigationService.requestInnerTab] 提交，
/// 顶层 page（如 AssessmentPage）在 build 后通过 [NavigationService.consumeInnerTab] 取出。
class PendingInnerTabRequest {
  final String pageKeyword;
  final String tabKeyword;

  const PendingInnerTabRequest(this.pageKeyword, this.tabKeyword);
}
