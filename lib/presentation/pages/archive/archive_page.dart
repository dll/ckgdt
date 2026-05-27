import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/agent/agents/archive_agent.dart';
import '../../../data/local/archive_dao.dart';
import '../../../data/models/archive_document_model.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import 'archive_constants.dart';
import 'tabs/period_tab.dart';
import 'tabs/archive_action_tab.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage>
    with SingleTickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _dao = ArchiveDao();
  final _agent = ArchiveAgent();
  String _courseType = 'exam';
  bool _isLoading = true;

  @override
  String get innerTabPageKey => 'archive';
  @override
  String get innerTabSpeakLabel => '归档';
  @override
  TabController get innerTabController => _tabController;
  @override
  List<String> innerTabLabels() => archivePeriodLabels;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: archivePeriodLabels.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    bindInnerTabRequest();
    _isLoading = false;
  }

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    super.dispose();
  }

  void _onCourseTypeChanged(String val) {
    if (val != _courseType) setState(() => _courseType = val);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Container(
          color: primary.withValues(alpha: 0.05),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.school_outlined, size: 18, color: primary),
              const SizedBox(width: 8),
              Text('课程类型', style: TextStyle(fontSize: 13, color: primary)),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'exam', label: Text('考试', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'assess', label: Text('考查', style: TextStyle(fontSize: 12))),
                ],
                selected: {_courseType},
                onSelectionChanged: (s) => _onCourseTypeChanged(s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const Spacer(),
              Text(periodLabelForCurrentTab, style: TextStyle(fontSize: 13, color: primary)),
            ],
          ),
        ),
        Container(
          color: primary.withValues(alpha: 0.05),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primary,
            tabs: List.generate(archivePeriodLabels.length, (i) => Tab(
              icon: Icon(archivePeriodIcons[i], size: 20),
              text: archivePeriodLabels[i],
            )),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ArchivePeriodTab(
                periodKey: 'beginning',
                courseType: _courseType,
                dao: _dao,
                agent: _agent,
              ),
              ArchivePeriodTab(
                periodKey: 'midterm',
                courseType: _courseType,
                dao: _dao,
                agent: _agent,
              ),
              ArchivePeriodTab(
                periodKey: 'final',
                courseType: _courseType,
                dao: _dao,
                agent: _agent,
              ),
              ArchiveActionTab(
                courseType: _courseType,
                dao: _dao,
                onRefresh: () => setState(() {}),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get periodLabelForCurrentTab {
    final idx = _tabController.index;
    if (idx >= 0 && idx < archivePeriodLabels.length) {
      return archivePeriodLabels[idx];
    }
    return '';
  }
}
