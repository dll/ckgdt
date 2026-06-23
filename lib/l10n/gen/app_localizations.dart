import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// 应用主标题（不含版本号）
  ///
  /// In zh, this message translates to:
  /// **'课程知识图谱与数字孪生'**
  String get appName;

  /// 带版本号的应用标题
  ///
  /// In zh, this message translates to:
  /// **'CKGDT v{version}'**
  String appNameWithVersion(String version);

  /// No description provided for @navHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get navHome;

  /// No description provided for @navGraph.
  ///
  /// In zh, this message translates to:
  /// **'图谱'**
  String get navGraph;

  /// No description provided for @navLearning.
  ///
  /// In zh, this message translates to:
  /// **'学习'**
  String get navLearning;

  /// No description provided for @navTeaching.
  ///
  /// In zh, this message translates to:
  /// **'教学'**
  String get navTeaching;

  /// No description provided for @navClassroom.
  ///
  /// In zh, this message translates to:
  /// **'课堂'**
  String get navClassroom;

  /// No description provided for @navLab.
  ///
  /// In zh, this message translates to:
  /// **'实验'**
  String get navLab;

  /// No description provided for @navAssessment.
  ///
  /// In zh, this message translates to:
  /// **'考核'**
  String get navAssessment;

  /// No description provided for @navWorks.
  ///
  /// In zh, this message translates to:
  /// **'作品'**
  String get navWorks;

  /// No description provided for @navAchievement.
  ///
  /// In zh, this message translates to:
  /// **'达成'**
  String get navAchievement;

  /// No description provided for @navAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理'**
  String get navAdmin;

  /// No description provided for @actionLogin.
  ///
  /// In zh, this message translates to:
  /// **'进入系统'**
  String get actionLogin;

  /// No description provided for @actionLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get actionLogout;

  /// No description provided for @actionSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get actionSearch;

  /// No description provided for @actionNotifications.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get actionNotifications;

  /// No description provided for @actionSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get actionSettings;

  /// No description provided for @actionRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get actionRefresh;

  /// No description provided for @actionSubmit.
  ///
  /// In zh, this message translates to:
  /// **'提交'**
  String get actionSubmit;

  /// No description provided for @actionCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get actionCancel;

  /// No description provided for @actionConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get actionConfirm;

  /// No description provided for @actionEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get actionEdit;

  /// No description provided for @actionDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get actionDelete;

  /// No description provided for @actionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get actionSave;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsThemeColor.
  ///
  /// In zh, this message translates to:
  /// **'主题色'**
  String get settingsThemeColor;

  /// No description provided for @settingsDisplayMode.
  ///
  /// In zh, this message translates to:
  /// **'显示模式'**
  String get settingsDisplayMode;

  /// No description provided for @settingsModeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsModeSystem;

  /// No description provided for @settingsModeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get settingsModeLight;

  /// No description provided for @settingsModeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settingsModeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get settingsLanguageChinese;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @loginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginTitle;

  /// No description provided for @loginUserId.
  ///
  /// In zh, this message translates to:
  /// **'学号 / 工号'**
  String get loginUserId;

  /// No description provided for @loginPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get loginPassword;

  /// No description provided for @loginQrCode.
  ///
  /// In zh, this message translates to:
  /// **'扫码登录'**
  String get loginQrCode;

  /// No description provided for @loginPasswordTab.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get loginPasswordTab;

  /// No description provided for @loginQrTab.
  ///
  /// In zh, this message translates to:
  /// **'扫码'**
  String get loginQrTab;

  /// No description provided for @homeWelcome.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来，{name}'**
  String homeWelcome(String name);

  /// No description provided for @homeRoleStudent.
  ///
  /// In zh, this message translates to:
  /// **'学生'**
  String get homeRoleStudent;

  /// No description provided for @homeRoleTeacher.
  ///
  /// In zh, this message translates to:
  /// **'教师'**
  String get homeRoleTeacher;

  /// No description provided for @homeRoleAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get homeRoleAdmin;

  /// No description provided for @qaTitle.
  ///
  /// In zh, this message translates to:
  /// **'班级问答'**
  String get qaTitle;

  /// No description provided for @qaCompose.
  ///
  /// In zh, this message translates to:
  /// **'提问'**
  String get qaCompose;

  /// No description provided for @qaVisibilityClass.
  ///
  /// In zh, this message translates to:
  /// **'全班可见'**
  String get qaVisibilityClass;

  /// No description provided for @qaVisibilityPrivate.
  ///
  /// In zh, this message translates to:
  /// **'仅老师可见'**
  String get qaVisibilityPrivate;

  /// No description provided for @qaStatusOpen.
  ///
  /// In zh, this message translates to:
  /// **'未回复'**
  String get qaStatusOpen;

  /// No description provided for @qaStatusAnswered.
  ///
  /// In zh, this message translates to:
  /// **'已回复'**
  String get qaStatusAnswered;

  /// No description provided for @qaStatusClosed.
  ///
  /// In zh, this message translates to:
  /// **'已结题'**
  String get qaStatusClosed;

  /// No description provided for @msgEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get msgEmpty;

  /// No description provided for @msgLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get msgLoading;

  /// No description provided for @msgError.
  ///
  /// In zh, this message translates to:
  /// **'出错了'**
  String get msgError;

  /// No description provided for @msgCopiedToClipboard.
  ///
  /// In zh, this message translates to:
  /// **'已复制到剪贴板'**
  String get msgCopiedToClipboard;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'zh':
      return AppL10nZh();
  }

  throw FlutterError(
      'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
