// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'CKGDT';

  @override
  String appNameWithVersion(String version) {
    return 'CKGDT v$version';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navGraph => 'Graph';

  @override
  String get navLearning => 'Learn';

  @override
  String get navTeaching => 'Teach';

  @override
  String get navClassroom => 'Class';

  @override
  String get navLab => 'Lab';

  @override
  String get navAssessment => 'Review';

  @override
  String get navWorks => 'Works';

  @override
  String get navAchievement => 'OBE';

  @override
  String get navAdmin => 'Admin';

  @override
  String get actionLogin => 'Sign In';

  @override
  String get actionLogout => 'Sign Out';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionNotifications => 'Notifications';

  @override
  String get actionSettings => 'Settings';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get actionSubmit => 'Submit';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionSave => 'Save';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsThemeColor => 'Theme color';

  @override
  String get settingsDisplayMode => 'Display mode';

  @override
  String get settingsModeSystem => 'System';

  @override
  String get settingsModeLight => 'Light';

  @override
  String get settingsModeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get loginTitle => 'Sign In';

  @override
  String get loginUserId => 'Student / Staff ID';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginQrCode => 'QR Sign In';

  @override
  String get loginPasswordTab => 'Account';

  @override
  String get loginQrTab => 'QR';

  @override
  String homeWelcome(String name) {
    return 'Welcome back, $name';
  }

  @override
  String get homeRoleStudent => 'Student';

  @override
  String get homeRoleTeacher => 'Instructor';

  @override
  String get homeRoleAdmin => 'Administrator';

  @override
  String get qaTitle => 'Class Q&A';

  @override
  String get qaCompose => 'Ask';

  @override
  String get qaVisibilityClass => 'All visible';

  @override
  String get qaVisibilityPrivate => 'Teacher only';

  @override
  String get qaStatusOpen => 'Open';

  @override
  String get qaStatusAnswered => 'Answered';

  @override
  String get qaStatusClosed => 'Closed';

  @override
  String get msgEmpty => 'No data';

  @override
  String get msgLoading => 'Loading...';

  @override
  String get msgError => 'Error';

  @override
  String get msgCopiedToClipboard => 'Copied to clipboard';
}
