import 'package:flutter/material.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../services/auth_service.dart';
import '../../widgets/agent_entry_button.dart';
import 'tabs/overview_tab.dart';
import 'tabs/scores_tab.dart';
import 'tabs/report_tab.dart';
import 'tabs/analysis_tab.dart';

import '../../../core/constants/color_ohos_compat.dart';
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
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _achievementDao = AchievementDao();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Container(
          color: primary.withValues(alpha: 0.05),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: primary,
                  tabs: const [
                    Tab(icon: Icon(Icons.analytics_outlined, size: 18), text: '达成度概览'),
                    Tab(icon: Icon(Icons.edit_note, size: 18), text: '成绩管理'),
                    Tab(icon: Icon(Icons.school_outlined, size: 18), text: '平时达成'),
                    Tab(icon: Icon(Icons.science_outlined, size: 18), text: '实验达成'),
                    Tab(icon: Icon(Icons.assignment_outlined, size: 18), text: '考核达成'),
                    Tab(icon: Icon(Icons.calculate_outlined, size: 18), text: '计算过程'),
                    Tab(icon: Icon(Icons.summarize_outlined, size: 18), text: '报告生成'),
                    Tab(icon: Icon(Icons.build_outlined, size: 18), text: '持续改进'),
                  ],
                ),
              ),
              const AgentEntryButton(agentId: 'achievement'),
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
              PingshiAchievementTab(
                achievementDao: _achievementDao,
              ),
              ExperimentAchievementTab(
                achievementDao: _achievementDao,
              ),
              ExamAchievementTab(
                achievementDao: _achievementDao,
              ),
              CalculationProcessTab(
                achievementDao: _achievementDao,
              ),
              ReportTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
              ContinuousImprovementTab(
                achievementDao: _achievementDao,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
