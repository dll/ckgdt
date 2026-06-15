import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../../core/error_handler.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../widgets/agent_entry_button.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import '../../pages/learning/video_player_page.dart';
import 'tabs/overview_tab.dart';
import 'tabs/scores_tab.dart';
import 'tabs/report_tab.dart';
import 'tabs/analysis_tab.dart';
import 'tabs/achievement_help_page.dart';

/// 课程达成度计算系统 — 8 Tab 壳页面
///
/// 各 Tab 实现已拆分至 tabs/ 子目录：
/// - overview_tab.dart: 达成度概览 + 批次详情
/// - scores_tab.dart: 成绩管理 + 平时/实验/考核达成
/// - report_tab.dart: 报告生成 + 预览对话框
/// - analysis_tab.dart: 计算过程 + 持续改进
class AchievementPage extends StatefulWidget {
  const AchievementPage({super.key});

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage>
    with TickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _achievementDao = AchievementDao();
  final _courseContext = CourseContextService();

  /// 数据变更通知器：成绩导入/删除时 +1，子 tab 监听后刷新
  final ValueNotifier<int> dataRevision = ValueNotifier(0);

  static const _allTabSpecs = <(IconData, String, String, String?)>[
    (Icons.analytics_outlined, '达成度概览', '01', null),
    (Icons.edit_note, '成绩管理', '02', null),
    (Icons.calculate_outlined, '计算过程', '03', null),
    (Icons.school_outlined, '平时达成', '04', 'pingshi'),
    (Icons.science_outlined, '实验达成', '05', 'experiment'),
    (Icons.assignment_outlined, '考核达成', '06', 'exam'),
    (Icons.build_outlined, '持续改进', '07', null),
    (Icons.summarize_outlined, '报告生成', '08', null),
  ];
  List<(IconData, String, String, String?)> _tabSpecs = _allTabSpecs;

  @override
  String get innerTabPageKey => 'achievement';
  @override
  String get innerTabSpeakLabel => '达成';
  @override
  TabController get innerTabController => _tabController;
  @override
  List<String> innerTabLabels() =>
      _tabSpecs.map((s) => s.$2).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabSpecs.length, vsync: this);
    bindInnerTabRequest();
    _refreshVisibleTabs();
  }

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    dataRevision.dispose();
    super.dispose();
  }

  /// 视频文件名
  static const _videoFileName = '达成度评价系统操作指南.mp4';

  /// GitHub Release 视频下载地址
  static const _videoDownloadUrl =
      'https://github.com/dll/mad-fd/releases/download/video-assets/default.mp4';

  Future<void> _refreshVisibleTabs() async {
    try {
      final courseName = await _courseContext.activeCourseName(
          fallback: CourseContextService.defaultCourseName);
      final objectives = await _achievementDao.getCourseObjectives(courseName);
      final hasExperiment = objectives.isEmpty ||
          objectives.any(
            (row) =>
                ((row['experiment_ratio'] as num?)?.toDouble() ?? 0) > 0.0001,
          );
      final nextSpecs = hasExperiment
          ? _allTabSpecs
          : _allTabSpecs
              .where((spec) => spec.$4 != 'experiment')
              .toList(growable: false);
      if (!mounted || _sameTabSpecs(_tabSpecs, nextSpecs)) return;

      final oldController = _tabController;
      final oldLabel = oldController.index < _tabSpecs.length
          ? _tabSpecs[oldController.index].$2
          : null;
      var nextIndex = oldLabel == null
          ? 0
          : nextSpecs.indexWhere((spec) => spec.$2 == oldLabel);
      if (nextIndex < 0) {
        nextIndex = oldController.index;
        if (nextIndex >= nextSpecs.length) nextIndex = nextSpecs.length - 1;
      }
      final nextController = TabController(
        length: nextSpecs.length,
        vsync: this,
        initialIndex: nextIndex,
      );
      setState(() {
        _tabSpecs = nextSpecs;
        _tabController = nextController;
      });
      oldController.dispose();
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementPage.refreshVisibleTabs', stack: st);
    }
  }

  bool _sameTabSpecs(
    List<(IconData, String, String, String?)> a,
    List<(IconData, String, String, String?)> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].$2 != b[i].$2 || a[i].$4 != b[i].$4) return false;
    }
    return true;
  }

  Future<void> _playGuideVideo() async {
    try {
      // 1. 先找本地 data/视频/ 目录
      String? videoPath = await _findLocalVideo();

      // 2. 本地没有则从 Gitee 下载
      if (videoPath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在从云端下载视频，请稍候...')),
        );
        videoPath = await _downloadVideoFromGitee();
      }

      if (videoPath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频下载失败，请检查网络后重试')),
        );
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InAppVideoPlayerPage(
            filePath: videoPath!,
            title: '达成度评价系统操作指南',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('视频加载失败: $e')),
      );
    }
  }

  /// 在本地 data/视频/ 目录查找视频文件
  Future<String?> _findLocalVideo() async {
    for (final file in await _localVideoCandidates()) {
      if (await file.exists()) return file.path;
    }
    return null;
  }

  Future<List<File>> _localVideoCandidates() async {
    final candidates = <File>[];

    if (!Platform.isAndroid && !Platform.isIOS) {
      final exeDir = File(Platform.resolvedExecutable).parent;
      var dir = exeDir;
      for (var i = 0; i < 6; i++) {
        candidates.add(File(_joinPath(dir.path, 'data', '视频', _videoFileName)));
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }

    final cacheDir = await _localVideoDirectory();
    candidates.add(File(_joinPath(cacheDir.path, _videoFileName)));
    return candidates;
  }

  Future<Directory> _localVideoDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(_joinPath(appDir.path, 'data', '视频'));
  }

  String _joinPath(String part1, String part2, [String? part3, String? part4]) {
    final parts = [
      part1,
      part2,
      if (part3 != null) part3,
      if (part4 != null) part4,
    ];
    return parts.join(Platform.pathSeparator);
  }

  /// 从 Gitee 仓库下载视频到本地 data/视频/ 目录
  Future<String?> _downloadVideoFromGitee() async {
    File? tempFile;
    try {
      final localDir = await _localVideoDirectory();
      if (!localDir.existsSync()) localDir.createSync(recursive: true);
      final file = File(_joinPath(localDir.path, _videoFileName));
      tempFile = File('${file.path}.download');
      if (await tempFile.exists()) await tempFile.delete();

      final response = await http
          .get(Uri.parse(_videoDownloadUrl))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        debugPrint(
          'AchievementPage: 视频下载失败，HTTP ${response.statusCode}',
        );
        return null;
      }

      if (response.bodyBytes.length < 1024 * 1024) {
        debugPrint('AchievementPage: 视频文件过小，跳过');
        return null;
      }

      await tempFile.writeAsBytes(response.bodyBytes, flush: true);

      if (await file.exists()) await file.delete();
      await tempFile.rename(file.path);
      return file.path;
    } catch (e) {
      debugPrint('AchievementPage: 下载视频失败: $e');
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: accent,
          ),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
                  indicatorColor: Colors.white,
                  indicatorWeight: 2,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.6,
                  ),
                  tabs: [
                    for (final (icon, label, serial, _) in _tabSpecs)
                      Tab(
                        height: 56,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(serial,
                                style: NoirTokens.serial(
                                    color:
                                        Colors.white.withValues(alpha: 0.85))),
                            const SizedBox(width: 8),
                            Icon(icon, size: 16),
                            const SizedBox(width: 6),
                            Text(label),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    iconTheme: const IconThemeData(color: Colors.white),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline, size: 20),
                        tooltip: '播放操作视频',
                        onPressed: _playGuideVideo,
                      ),
                      IconButton(
                        icon: const Icon(Icons.menu_book_outlined, size: 20),
                        tooltip: '达成度帮助',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AchievementHelpPage()),
                        ),
                      ),
                      const AgentEntryButton(agentId: 'achievement'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final spec in _tabSpecs) _buildTabContent(spec),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent((IconData, String, String, String?) spec) {
    switch (spec.$2) {
      case '达成度概览':
        return AchievementOverviewTab(
          authService: _authService,
          achievementDao: _achievementDao,
        );
      case '成绩管理':
        return ScoreManagementTab(
          authService: _authService,
          achievementDao: _achievementDao,
          dataRevision: dataRevision,
        );
      case '计算过程':
        return CalculationProcessTab(
          achievementDao: _achievementDao,
          dataRevision: dataRevision,
        );
      case '平时达成':
        return ComponentAchievementTab(
          achievementDao: _achievementDao,
          env: 'pingshi',
          dataRevision: dataRevision,
        );
      case '实验达成':
        return ComponentAchievementTab(
          achievementDao: _achievementDao,
          env: 'experiment',
          dataRevision: dataRevision,
        );
      case '考核达成':
        return ComponentAchievementTab(
          achievementDao: _achievementDao,
          env: 'exam',
          dataRevision: dataRevision,
        );
      case '持续改进':
        return ContinuousImprovementTab(
          achievementDao: _achievementDao,
        );
      case '报告生成':
        return ReportTab(
          authService: _authService,
          achievementDao: _achievementDao,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
