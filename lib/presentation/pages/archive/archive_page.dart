import 'package:flutter/material.dart';
import '../../../core/error_handler.dart';
import '../../../services/agent/agents/archive_agent.dart';
import '../../../data/local/archive_dao.dart';
import '../../widgets/agent_entry_button.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import 'archive_constants.dart';
import 'tabs/period_tab.dart';
import 'tabs/midterm_tab.dart';
import 'tabs/final_tab.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage>
    with SingleTickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _dao = ArchiveDao();
  final _agent = ArchiveAgent();
  String _detectedCourseType = 'assess';

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
    _detectCourseTypeFromSyllabus();
  }

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _detectCourseTypeFromSyllabus() async {
    try {
      final syllabi = await _dao.getDocuments(
        period: 'beginning',
        documentType: 'syllabus',
      );
      final content = syllabi.isNotEmpty ? syllabi.first.content : null;
      final detected = detectCourseTypeFromSyllabus(content);
      if (detected != _detectedCourseType && mounted) {
        setState(() => _detectedCourseType = detected);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePage._detectCourseType', stack: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final courseTypeLabel = isExamCourse(_detectedCourseType) ? '考试' : '考查';
    return Column(
      children: [
        Container(
          color: primary.withValues(alpha: 0.05),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.school_outlined, size: 16, color: primary),
              const SizedBox(width: 6),
              Text('课程类型：$courseTypeLabel（由大纲自动检测）',
                  style: TextStyle(fontSize: 12, color: primary)),
            ],
          ),
        ),
        Container(
          color: primary.withValues(alpha: 0.05),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  tabAlignment: TabAlignment.fill,
                  labelColor: primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: primary,
                  tabs: List.generate(archivePeriodLabels.length, (i) => Tab(
                    icon: Icon(archivePeriodIcons[i], size: 20),
                    text: archivePeriodLabels[i],
                  )),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: AgentEntryButton(agentId: 'archive'),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ArchivePeriodTab(
                periodKey: 'beginning',
                courseType: _detectedCourseType,
                dao: _dao,
                agent: _agent,
                onSyllabusChanged: _detectCourseTypeFromSyllabus,
              ),
              MidtermTab(
                courseType: _detectedCourseType,
                dao: _dao,
                agent: _agent,
              ),
              FinalTab(
                courseType: _detectedCourseType,
                dao: _dao,
                agent: _agent,
              ),
              ArchivePeriodTab(
                periodKey: 'archive',
                courseType: _detectedCourseType,
                dao: _dao,
                agent: _agent,
                onSyllabusChanged: _detectCourseTypeFromSyllabus,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
