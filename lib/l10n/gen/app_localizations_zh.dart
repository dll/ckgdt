// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppL10nZh extends AppL10n {
  AppL10nZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '课程知识图谱与数字孪生';

  @override
  String appNameWithVersion(String version) {
    return 'CKGDT v$version';
  }

  @override
  String get navHome => '首页';

  @override
  String get navGraph => '图谱';

  @override
  String get navLearning => '学习';

  @override
  String get navTeaching => '教学';

  @override
  String get navClassroom => '课堂';

  @override
  String get navLab => '实验';

  @override
  String get navAssessment => '考核';

  @override
  String get navWorks => '作品';

  @override
  String get navAchievement => '达成';

  @override
  String get navAdmin => '管理';

  @override
  String get actionLogin => '进入系统';

  @override
  String get actionLogout => '退出登录';

  @override
  String get actionSearch => '搜索';

  @override
  String get actionNotifications => '通知';

  @override
  String get actionSettings => '设置';

  @override
  String get actionRefresh => '刷新';

  @override
  String get actionSubmit => '提交';

  @override
  String get actionCancel => '取消';

  @override
  String get actionConfirm => '确定';

  @override
  String get actionEdit => '编辑';

  @override
  String get actionDelete => '删除';

  @override
  String get actionSave => '保存';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsThemeColor => '主题色';

  @override
  String get settingsDisplayMode => '显示模式';

  @override
  String get settingsModeSystem => '跟随系统';

  @override
  String get settingsModeLight => '浅色';

  @override
  String get settingsModeDark => '深色';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get loginTitle => '登录';

  @override
  String get loginUserId => '学号 / 工号';

  @override
  String get loginPassword => '密码';

  @override
  String get loginQrCode => '扫码登录';

  @override
  String get loginPasswordTab => '账号';

  @override
  String get loginQrTab => '扫码';

  @override
  String homeWelcome(String name) {
    return '欢迎回来，$name';
  }

  @override
  String get homeRoleStudent => '学生';

  @override
  String get homeRoleTeacher => '教师';

  @override
  String get homeRoleAdmin => '管理员';

  @override
  String get qaTitle => '班级问答';

  @override
  String get qaCompose => '提问';

  @override
  String get qaVisibilityClass => '全班可见';

  @override
  String get qaVisibilityPrivate => '仅老师可见';

  @override
  String get qaStatusOpen => '未回复';

  @override
  String get qaStatusAnswered => '已回复';

  @override
  String get qaStatusClosed => '已结题';

  @override
  String get msgEmpty => '暂无数据';

  @override
  String get msgLoading => '加载中...';

  @override
  String get msgError => '出错了';

  @override
  String get msgCopiedToClipboard => '已复制到剪贴板';
}
