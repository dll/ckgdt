import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const int defaultEvaluationPassScore = 85;

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
  static const String _defaultCourseName = '移动应用开发';

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
  // 评价提交达标分数线（实验 / 考核 / 作品共用）
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
  // 讯飞语音配置（AppID / APIKey / APISecret）
  // ═════════════════════════════════════════════════════════════════════════

  // 讯飞默认配置
  static const String _defaultXunfeiAppId = 'ae4a0e4a';
  static const String _defaultXunfeiApiKey = '7385e5cb32d3465474e613dfbfc69310';
  static const String _defaultXunfeiApiSecret =
      'NTI2NzVlOWQ0ZTM5YTgzNGYzZDI5NjQx';

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

  static const String _defaultGithubRepo = 'dll/mad-fd';
  static const String _defaultGiteeRepo = 'osgisOne/mad-fd';

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
    return prefs.getString(_courseNameKey) ?? _defaultCourseName;
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
