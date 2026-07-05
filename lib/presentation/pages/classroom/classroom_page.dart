import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../data/local/classroom_dao.dart';
import '../../../data/local/class_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/default_class_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/voice_service.dart';
import '../../../core/error_handler.dart';
import '../../../core/constants/role_guard.dart';
import '../../widgets/agent_entry_button.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import 'classroom_question_tab.dart';


// ── Tab 实现拆分到 tabs/ 子目录（part / part of 模式）──────────────
part 'tabs/online_status_tab.dart';
part 'tabs/checkin_manage_tab.dart';
part 'tabs/interaction_tab.dart';
part 'tabs/tools_tab.dart';

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  课堂管理页面 — 在线状态 / 课堂签到 / 课堂互动                              ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

class ClassroomPage extends StatefulWidget {
  const ClassroomPage({super.key});

  @override
  State<ClassroomPage> createState() => _ClassroomPageState();
}

class _ClassroomPageState extends State<ClassroomPage>
    with SingleTickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _classroomDao = ClassroomDao();
  final _classDao = ClassDao();
  final _syncService = SyncService();

  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];

  @override
  String get innerTabPageKey => 'classroom';
  @override
  String get innerTabSpeakLabel => '课堂';
  @override
  TabController get innerTabController => _tabController;
  @override
  List<String> innerTabLabels() =>
      const ['在线状态', '课堂签到', '课堂互动', '课堂工具', '课堂提问'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _init();
    bindInnerTabRequest();
  }

  Future<void> _init() async {
    await _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final classes = await _classDao.getActiveClasses();
      // 默认班级走 DefaultClassService（确定性落到软件231），不再把所有
      // 学生灌进同一个班级（旧 syncAllStudentsToClass 会合并软件231+232，
      // 破坏班级隔离）。
      final defaultId =
          await DefaultClassService.instance.getDefaultClassId();
      if (mounted) {
        setState(() {
          _classes = classes;
          if (classes.isNotEmpty && _selectedClassId == null) {
            final hasDefault =
                defaultId != null && classes.any((c) => c['id'] == defaultId);
            _selectedClassId =
                hasDefault ? defaultId : classes.first['id'] as int;
          }
        });
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ClassroomPage._loadClasses', stack: st);
    }
  }

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = _authService.currentUser?.role ?? 'student';
    if (!RoleGuard.isTeacherOrAdmin(role)) {
      return _buildNoPermission(context);
    }

    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // ── 渐变页头（始终显示，不依赖班级加载状态）─────────────────
        _buildHeader(context, primary),
        // ── TabBar ────────────────────────────────────────────────
        Container(
          color: primary.withValues(alpha: 0.04),
          child: TabBar(
            controller: _tabController,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(icon: Icon(Icons.wifi, size: 18), text: '在线状态'),
              Tab(icon: Icon(Icons.fact_check, size: 18), text: '课堂签到'),
              Tab(icon: Icon(Icons.forum, size: 18), text: '课堂互动'),
              Tab(icon: Icon(Icons.build_circle, size: 18), text: '课堂工具'),
              Tab(icon: Icon(Icons.quiz, size: 18), text: '课堂提问'),
            ],
          ),
        ),
        // ── TabBarView ────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _OnlineStatusTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                syncService: _syncService,
              ),
              _CheckinManageTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                authService: _authService,
              ),
              _ClassroomInteractionTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                authService: _authService,
              ),
              _ClassroomToolsTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                authService: _authService,
              ),
              ClassroomQuestionTab(
                classroomDao: _classroomDao,
                classId: _selectedClassId,
                authService: _authService,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Color primary) {
    final user = _authService.currentUser;
    final displayName = user?.realName ?? user?.userId ?? '老师';
    final className = _classes.isNotEmpty
        ? (_classes.firstWhere(
            (c) => c['id'] == _selectedClassId,
            orElse: () => _classes.first,
          )['name'] as String? ?? '')
        : '';

    // 直接构建渐变，避免 ThemeExtension 可能的延迟
    final headerGradient = LinearGradient(
      colors: [primary, primary.withValues(alpha: 0.7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: 12,
      ),
      decoration: BoxDecoration(gradient: headerGradient),
      child: Row(
        children: [
          // 图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cast_for_education,
                size: 24, color: Colors.white),
          ),
          const SizedBox(width: 12),
          // 文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('课堂管理',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  '$displayName${className.isNotEmpty ? ' · $className' : ''}',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          // 同步按钮
          const AgentEntryButton(agentId: 'tutor', color: Colors.white),
          ValueListenableBuilder<SyncStatus>(
            valueListenable: _syncService.status,
            builder: (_, syncStatus, __) => IconButton(
              icon: syncStatus == SyncStatus.downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync, color: Colors.white),
              tooltip: '同步学生数据',
              onPressed: syncStatus == SyncStatus.downloading
                  ? null
                  : () async {
                      final result =
                          await _syncService.downloadAllStudentData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result.message)),
                        );
                      }
                    },
            ),
          ),
          // 班级选择
          if (_classes.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.class_, color: Colors.white),
              tooltip: '选择班级',
              onSelected: (id) => setState(() => _selectedClassId = id),
              itemBuilder: (_) => _classes
                  .map((c) => PopupMenuItem(
                        value: c['id'] as int,
                        child: Text(c['name'] as String? ?? ''),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildNoPermission(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('课堂管理')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('无权限访问',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            SizedBox(height: 8),
            Text('仅教师和管理员可访问课堂管理',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 0: 在线状态                                                           ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

