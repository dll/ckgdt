import 'package:flutter/material.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../services/auth_service.dart';
import '../../widgets/agent_entry_button.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import 'tabs/overview_tab.dart';
import 'tabs/scores_tab.dart';
import 'tabs/report_tab.dart';
import 'tabs/analysis_tab.dart';

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
    with SingleTickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _achievementDao = AchievementDao();

  static const _tabSpecs = <(IconData, String, String)>[
    (Icons.analytics_outlined, '达成度概览', '01'),
    (Icons.edit_note, '成绩管理', '02'),
    (Icons.calculate_outlined, '计算过程', '03'),
    (Icons.school_outlined, '平时达成', '04'),
    (Icons.science_outlined, '实验达成', '05'),
    (Icons.assignment_outlined, '考核达成', '06'),
    (Icons.build_outlined, '持续改进', '07'),
    (Icons.summarize_outlined, '报告生成', '08'),
  ];

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
  }

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    super.dispose();
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
                    for (final (icon, label, serial) in _tabSpecs)
                      Tab(
                        height: 56,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(serial,
                                style: NoirTokens.serial(
                                    color: Colors.white.withValues(alpha: 0.85))),
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
                  // 顶栏入口在黑底上要可见，反转图标颜色
                  data: Theme.of(context).copyWith(
                    iconTheme: const IconThemeData(color: Colors.white),
                  ),
                  child: const AgentEntryButton(agentId: 'achievement'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              AchievementOverviewTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
              ScoreManagementTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
              CalculationProcessTab(
                achievementDao: _achievementDao,
              ),
              PingshiAchievementTab(
                achievementDao: _achievementDao,
              ),
              ExperimentAchievementTab(
                achievementDao: _achievementDao,
              ),
              ExamAchievementTab(
                achievementDao: _achievementDao,
              ),
              ContinuousImprovementTab(
                achievementDao: _achievementDao,
              ),
              ReportTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
