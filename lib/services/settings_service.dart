import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/error_handler.dart';
import 'course_context_service.dart';

/// 课堂试用内置讯飞语音凭据。
///
/// 与 AI 课堂试用 Key 保持同一发布策略：校内试用包默认可用，公开发布时使用：
///
/// ```shell
/// flutter build ... --dart-define=USE_BUILTIN_TRIAL_VOICE_KEYS=false
/// ```
///
/// 关闭后系统不再回退到内置语音凭据，用户需要在系统设置中自行填写。
const bool kUseBuiltinTrialVoiceKeys = bool.fromEnvironment(
  'USE_BUILTIN_TRIAL_VOICE_KEYS',
  defaultValue: true,
);

class SettingsService {
  SettingsService._();

  // ── 持久化 Key ────────────────────────────────────────────────────────────
  static const String _legacyThemeKey = 'theme_mode'; // 旧 bool 键（兼容）
  static const String _themeModeKey =
      'theme_mode_index'; // 0=system 1=light 2=dark
  static const String _colorIndexKey = 'color_index'; // 0=科技蓝 1=清新绿 2=轻奢紫
  static const String _localeKey = 'app_locale'; // 'zh' / 'en' / null=系统
  static const String _notificationKey = 'notification_enabled';
  static const String _quickLoginKey = 'quick_login_enabled';
  static const String _feedbackEnabledKey = 'feedback_enabled';
  static const String _evaluationPassScoreKey = 'evaluation_pass_score';
  static const String _teacherAiGradingEnabledKey =
      'teacher_ai_grading_enabled';
  static const int defaultEvaluationPassScore = 60;

  // ── 讯飞语音配置 ────────────────────────────────────────────────────────
  static const String _xunfeiAppIdKey = 'xunfei_app_id';
  static const String _xunfeiApiKeyKey = 'xunfei_api_key';
  static const String _xunfeiApiSecretKey = 'xunfei_api_secret';

  // ── 考核报告封面默认值 ──────────────────────────────────────────────────
  static const String _advisorNameKey = 'assessment_advisor_name';
  static const String _collegeNameKey = 'assessment_college_name';
  static const String _courseNameKey = 'assessment_course_name';
  static const String _defaultAdvisorName = '刘东良';
  static const String _defaultCollegeName = '计算机与信息工程学院';
  static const String _defaultCourseName = '课程知识图谱与数字孪生';

  // ═════════════════════════════════════════════════════════════════════════
  // 显示模式  ThemeMode（跟随系统 / 浅色 / 深色）
  // ═════════════════════════════════════════════════════════════════════════

  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();

    // 读取新键
    if (prefs.containsKey(_themeModeKey)) {
      final index = prefs.getInt(_themeModeKey) ?? 0;
      return _indexToThemeMode(index);
    }

    // 兼容旧 bool 键：true → 深色，false → 跟随系统
    if (prefs.containsKey(_legacyThemeKey)) {
      final isDark = prefs.getBool(_legacyThemeKey) ?? false;
      return isDark ? ThemeMode.dark : ThemeMode.system;
    }

    return ThemeMode.dark; // 默认深色模式（匹配登录页 Noir 风格）
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, _themeModeToIndex(mode));
  }

  // ─── 向下兼容旧接口（部分页面仍使用）────────────────────────────────────
  static Future<bool> isDarkMode() async {
    final mode = await getThemeMode();
    return mode == ThemeMode.dark;
  }

  static Future<void> setDarkMode(bool isDark) async {
    await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 主题色索引  0=科技蓝  1=清新绿  2=轻奢紫
  // ═════════════════════════════════════════════════════════════════════════

  static Future<int> getColorIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_colorIndexKey) ?? 0).clamp(0, 2);
  }

  static Future<void> setColorIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorIndexKey, index.clamp(0, 2));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 应用语言（i18n）
  // ═════════════════════════════════════════════════════════════════════════

  /// 当前语言；返回 null 表示跟随系统。
  static Future<Locale?> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  /// 设置语言；传 null 表示跟随系统。
  static Future<void> setLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, locale.languageCode);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 通知开关
  // ═════════════════════════════════════════════════════════════════════════

  static Future<bool> isNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationKey) ?? true;
  }

  static Future<void> setNotificationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationKey, enabled);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 快速登录开关（管理员设置，默认关闭）
  // ═════════════════════════════════════════════════════════════════════════

  static Future<bool> isQuickLoginEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_quickLoginKey) ?? false;
  }

  static Future<void> setQuickLoginEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_quickLoginKey, enabled);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 问题反馈浮动按钮（管理员控制，默认开启）
  // ═════════════════════════════════════════════════════════════════════════

  static Future<bool> isFeedbackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_feedbackEnabledKey) ?? true;
  }

  static Future<void> setFeedbackEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_feedbackEnabledKey, enabled);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 评价统计参考分数线（实验 / 考核 / 作品共用，不拦截学生提交）
  // ═════════════════════════════════════════════════════════════════════════

  static Future<int> getEvaluationPassScore() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_evaluationPassScoreKey) ?? defaultEvaluationPassScore)
        .clamp(60, 100);
  }

  static Future<void> setEvaluationPassScore(int score) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_evaluationPassScoreKey, score.clamp(60, 100));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 教师系统级 AI 批阅开关（实验 / 考核 / 作品共用，默认开启）
  // ═════════════════════════════════════════════════════════════════════════

  static Future<bool> isTeacherAiGradingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_teacherAiGradingEnabledKey) ?? true;
  }

  static Future<void> setTeacherAiGradingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_teacherAiGradingEnabledKey, enabled);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 讯飞语音配置（AppID / APIKey / APISecret）
  // ═════════════════════════════════════════════════════════════════════════

  // 讯飞课堂试用配置。用户填写的配置始终优先于内置试用值。
  static const String _trialXunfeiAppId = 'ae4a0e4a';
  static const String _trialXunfeiApiKey = '7385e5cb32d3465474e613dfbfc69310';
  static const String _trialXunfeiApiSecret =
      'NTI2NzVlOWQ0ZTM5YTgzNGYzZDI5NjQx';

  static String get _defaultXunfeiAppId =>
      kUseBuiltinTrialVoiceKeys ? _trialXunfeiAppId : '';
  static String get _defaultXunfeiApiKey =>
      kUseBuiltinTrialVoiceKeys ? _trialXunfeiApiKey : '';
  static String get _defaultXunfeiApiSecret =>
      kUseBuiltinTrialVoiceKeys ? _trialXunfeiApiSecret : '';

  static Future<String> getXunfeiAppId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_xunfeiAppIdKey);
    return (v == null || v.isEmpty) ? _defaultXunfeiAppId : v;
  }

  static Future<void> setXunfeiAppId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_xunfeiAppIdKey, value);
  }

  static Future<String> getXunfeiApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_xunfeiApiKeyKey);
    return (v == null || v.isEmpty) ? _defaultXunfeiApiKey : v;
  }

  static Future<void> setXunfeiApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_xunfeiApiKeyKey, value);
  }

  static Future<String> getXunfeiApiSecret() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_xunfeiApiSecretKey);
    return (v == null || v.isEmpty) ? _defaultXunfeiApiSecret : v;
  }

  static Future<void> setXunfeiApiSecret(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_xunfeiApiSecretKey, value);
  }

  // ── 语音功能开关（应急 — 桌面端 record 包偶发原生崩溃时可关掉）──
  static const String _voiceDisabledKey = 'voice_disabled';

  /// 用户主动关闭语音功能（默认 false）。
  /// 关掉后 VoiceService 不再调用任何 record 包 API（绕过原生层崩溃）。
  static Future<bool> isVoiceDisabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_voiceDisabledKey) ?? false;
  }

  static Future<void> setVoiceDisabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceDisabledKey, value);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 构建发布中心（admin 工具）— GitHub PAT / Gitee Token / 仓库
  //
  // 与 Xunfei API key 同档次：admin 机器本身可信，不引入 secure_storage 依赖。
  // 仅用于点"一键发布"按钮上传 Release 资产。
  // ═════════════════════════════════════════════════════════════════════════
  static const String _releaseGithubPatKey = 'release.github_pat';
  static const String _releaseGiteeTokenKey = 'release.gitee_token';
  static const String _releaseGithubRepoKey = 'release.github_repo';
  static const String _releaseGiteeRepoKey = 'release.gitee_repo';

  static const String _defaultGithubRepo = 'dll/mad-kgdt';
  static const String _defaultGiteeRepo = 'chzcldl/mad-kgdt';

  static Future<String> getReleaseGithubPat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_releaseGithubPatKey) ?? '';
  }

  static Future<void> setReleaseGithubPat(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_releaseGithubPatKey, value.trim());
  }

  static Future<String> getReleaseGiteeToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_releaseGiteeTokenKey) ?? '';
  }

  static Future<void> setReleaseGiteeToken(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_releaseGiteeTokenKey, value.trim());
  }

  static Future<String> getReleaseGithubRepo() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_releaseGithubRepoKey);
    return (v == null || v.isEmpty) ? _defaultGithubRepo : v;
  }

  static Future<void> setReleaseGithubRepo(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_releaseGithubRepoKey, value.trim());
  }

  static Future<String> getReleaseGiteeRepo() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_releaseGiteeRepoKey);
    return (v == null || v.isEmpty) ? _defaultGiteeRepo : v;
  }

  static Future<void> setReleaseGiteeRepo(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_releaseGiteeRepoKey, value.trim());
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 考核报告封面默认值
  // ═════════════════════════════════════════════════════════════════════════

  static Future<String> getAdvisorName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_advisorNameKey) ?? _defaultAdvisorName;
  }

  static Future<void> setAdvisorName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_advisorNameKey, value);
  }

  static Future<String> getCollegeName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_collegeNameKey) ?? _defaultCollegeName;
  }

  static Future<void> setCollegeName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_collegeNameKey, value);
  }

  static Future<String> getCourseName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_courseNameKey);
    if (saved != null && saved.isNotEmpty) return saved;
    try {
      final ctx = CourseContextService();
      return await ctx.activeCourseName(fallback: _defaultCourseName);
    } catch (e, st) {
      swallowDebug(e, tag: 'SettingsService.getCourseName', stack: st);
      return _defaultCourseName;
    }
  }

  static Future<void> setCourseName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_courseNameKey, value);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 私有工具方法
  // ═════════════════════════════════════════════════════════════════════════

  static ThemeMode _indexToThemeMode(int index) {
    switch (index) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static int _themeModeToIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 1;
      case ThemeMode.dark:
        return 2;
      case ThemeMode.system:
        return 0;
    }
  }
}
