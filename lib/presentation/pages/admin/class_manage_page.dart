import 'package:flutter/material.dart';
import '../../../data/local/class_dao.dart';
import '../../../data/local/user_dao.dart';
import '../../../data/models/user_model.dart';

/// 班级管理页面 — 支持班级 CRUD、归档/取消归档、成员管理
class ClassManagePage extends StatefulWidget {
  const ClassManagePage({super.key});

  @override
  State<ClassManagePage> createState() => _ClassManagePageState();
}

class _ClassManagePageState extends State<ClassManagePage>
    with SingleTickerProviderStateMixin {
  final _classDao = ClassDao();
  final _userDao = UserDao();
  late TabController _tabController;

  List<Map<String, dynamic>> _activeClasses = [];
  List<Map<String, dynamic>> _archivedClasses = [];
  Map<String, int> _stats = {};
  bool _isLoading = true;
  bool _demoGenerated = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    if (!_demoGenerated) {
      try {
        await _classDao.generateDemoData();
      } catch (e) {
        debugPrint('ClassManagePage: generateDemoData error: $e');
      }
      _demoGenerated = true;
    }
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final active = await _classDao.getActiveClasses();
      final archived = await _classDao.getArchivedClasses();
      final stats = await _classDao.getClassStats();

      // 计算总学生数
      int totalStudents = 0;
      for (final cls in active) {
        totalStudents += (cls['student_count'] as int?) ?? 0;
      }
      for (final cls in archived) {
        totalStudents += (cls['student_count'] as int?) ?? 0;
      }
      stats['totalStudents'] = totalStudents;

      if (!mounted) return;
      setState(() {
        _activeClasses = active;
        _archivedClasses = archived;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('ClassManagePage: _loadData error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('班级管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: theme.colorScheme.primary,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('进行中'),
                  const SizedBox(width: 6),
                  _buildBadge(_activeClasses.length, theme.colorScheme.primary),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('已归档'),
                  const SizedBox(width: 6),
                  _buildBadge(_archivedClasses.length, Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStatsOverview(theme),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActiveTab(theme),
                      _buildArchivedTab(theme),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateClassDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('新建班级', style: TextStyle(color: Colors.white)),
        backgroundColor: theme.colorScheme.primary,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stats Overview
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatsOverview(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667eea).withValues(alpha: 0.08),
            const Color(0xFF764ba2).withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF667eea).withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            icon: Icons.class_outlined,
            label: '总班级',
            value: '${_stats['total'] ?? 0}',
            color: const Color(0xFF667eea),
          ),
          _buildStatDivider(),
          _buildStatItem(
            icon: Icons.play_circle_outline,
            label: '进行中',
            value: '${_stats['active'] ?? 0}',
            color: Colors.green,
          ),
          _buildStatDivider(),
          _buildStatItem(
            icon: Icons.archive_outlined,
            label: '已归档',
            value: '${_stats['archived'] ?? 0}',
            color: Colors.orange,
          ),
          _buildStatDivider(),
          _buildStatItem(
            icon: Icons.people_outline,
            label: '总学生',
            value: '${_stats['totalStudents'] ?? 0}',
            color: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 36,
      color: Colors.grey.withValues(alpha: 0.2),
    );
  }

  Widget _buildBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Active Tab
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActiveTab(ThemeData theme) {
    if (_activeClasses.isEmpty) {
      return _buildEmptyState(
        icon: Icons.class_outlined,
        title: '暂无进行中的班级',
        subtitle: '点击右下角按钮创建新班级',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: _activeClasses.length,
        itemBuilder: (context, index) {
          return _buildClassCard(_activeClasses[index], theme, isArchived: false);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Archived Tab
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildArchivedTab(ThemeData theme) {
    if (_archivedClasses.isEmpty) {
      return _buildEmptyState(
        icon: Icons.archive_outlined,
        title: '暂无已归档的班级',
        subtitle: '归档的班级会在此处显示',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: _archivedClasses.length,
        itemBuilder: (context, index) {
          return _buildClassCard(_archivedClasses[index], theme, isArchived: true);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Class Card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildClassCard(
    Map<String, dynamic> cls,
    ThemeData theme, {
    required bool isArchived,
  }) {
    final classId = cls['id'] as int;
    final name = cls['name'] as String? ?? '未命名班级';
    final semester = cls['semester'] as String?;
    final teacherName = cls['teacher_name'] as String?;
    final description = cls['description'] as String?;
    final studentCount = (cls['student_count'] as int?) ?? 0;
    final createdAt = cls['created_at'] as String?;

    final cardColor = isArchived
        ? Colors.grey.withValues(alpha: 0.06)
        : theme.cardColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isArchived ? 0.5 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isArchived
            ? BorderSide(color: Colors.grey.withValues(alpha: 0.2))
            : BorderSide.none,
      ),
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showMemberSheet(classId, name, isArchived),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部行: 班级名 + 操作菜单
              Row(
                children: [
                  // 班级图标
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isArchived
                          ? Colors.grey.withValues(alpha: 0.15)
                          : const Color(0xFF667eea).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isArchived ? Icons.archive_rounded : Icons.school_rounded,
                      color: isArchived ? Colors.grey : const Color(0xFF667eea),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 班级名 + 学期
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isArchived ? Colors.grey[600] : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (semester != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            semester,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 归档状态标签
                  if (isArchived)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '已归档',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  // 操作菜单
                  _buildPopupMenu(classId, name, isArchived),
                ],
              ),
              // 描述
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              // 底部信息行
              Row(
                children: [
                  // 教师
                  if (teacherName != null) ...[
                    Icon(Icons.person_outline,
                        size: 15, color: Colors.grey[500]),
                    const SizedBox(width: 3),
                    Text(
                      teacherName,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 16),
                  ],
                  // 学生数
                  Icon(Icons.people_outline, size: 15, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(
                    '$studentCount 人',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  // 创建时间
                  if (createdAt != null) ...[
                    Icon(Icons.access_time, size: 13, color: Colors.grey[400]),
                    const SizedBox(width: 3),
                    Text(
                      _formatDate(createdAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Popup Menu
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPopupMenu(int classId, String name, bool isArchived) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: Colors.grey[500], size: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'members':
            _showMemberSheet(classId, name, isArchived);
            break;
          case 'edit':
            _showEditClassDialog(classId);
            break;
          case 'archive':
            _confirmArchive(classId, name);
            break;
          case 'unarchive':
            _confirmUnarchive(classId, name);
            break;
          case 'delete':
            _confirmDelete(classId, name);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'members',
          child: ListTile(
            leading: Icon(Icons.group, size: 20),
            title: Text('成员管理'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        if (!isArchived)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit_outlined, size: 20),
              title: Text('编辑班级'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        const PopupMenuDivider(),
        if (!isArchived)
          const PopupMenuItem(
            value: 'archive',
            child: ListTile(
              leading: Icon(Icons.archive_outlined, size: 20, color: Colors.orange),
              title: Text('归档班级', style: TextStyle(color: Colors.orange)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (isArchived)
          const PopupMenuItem(
            value: 'unarchive',
            child: ListTile(
              leading: Icon(Icons.unarchive_outlined, size: 20, color: Colors.green),
              title: Text('取消归档', style: TextStyle(color: Colors.green)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, size: 20, color: Colors.red),
            title: Text('删除班级', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Archive / Unarchive / Delete Confirmations
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _confirmArchive(int classId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认归档'),
        content: Text(
          '确定要将「$name」移至已归档吗？\n\n归档后班级将从"进行中"列表中隐藏，但数据不会丢失，可随时取消归档。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认归档'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _classDao.archiveClass(classId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('「$name」已归档'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () async {
                await _classDao.unarchiveClass(classId);
                _loadData();
              },
            ),
          ),
        );
        _loadData();
      }
    }
  }

  Future<void> _confirmUnarchive(int classId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('取消归档'),
        content: Text('确定要将「$name」恢复为进行中吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _classDao.unarchiveClass(classId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「$name」已恢复为进行中')),
        );
        _loadData();
      }
    }
  }

  Future<void> _confirmDelete(int classId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('确认删除'),
          ],
        ),
        content: Text(
          '确定要删除「$name」吗？\n\n此操作不可撤销，班级及其所有成员关联数据将被永久删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _classDao.deleteClass(classId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「$name」已删除')),
        );
        _loadData();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Create Class Dialog
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showCreateClassDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => const _ClassFormDialog(title: '新建班级'),
    );

    if (result != null) {
      try {
        await _classDao.createClass(
          name: result['name']!,
          semester: result['semester'],
          teacherId: result['teacherId'],
          teacherName: result['teacherName'],
          description: result['description'],
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('班级创建成功')),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败: $e')),
          );
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Edit Class Dialog
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showEditClassDialog(int classId) async {
    final cls = await _classDao.getClass(classId);
    if (cls == null || !mounted) return;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _ClassFormDialog(
        title: '编辑班级',
        initialName: cls['name'] as String? ?? '',
        initialSemester: cls['semester'] as String?,
        initialTeacherId: cls['teacher_id'] as String?,
        initialTeacherName: cls['teacher_name'] as String?,
        initialDescription: cls['description'] as String?,
      ),
    );

    if (result != null) {
      try {
        await _classDao.updateClass(classId, {
          'name': result['name'],
          'semester': result['semester'],
          'teacher_id': result['teacherId'],
          'teacher_name': result['teacherName'],
          'description': result['description'],
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('班级信息已更新')),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败: $e')),
          );
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Member Management Sheet
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showMemberSheet(
      int classId, String className, bool isArchived) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ClassMemberSheet(
        classId: classId,
        className: className,
        isArchived: isArchived,
        classDao: _classDao,
        userDao: _userDao,
        onMembersChanged: _loadData,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Empty State
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }
}

// =============================================================================
// _ClassFormDialog — 新建 / 编辑班级表单
// =============================================================================

class _ClassFormDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final String? initialSemester;
  final String? initialTeacherId;
  final String? initialTeacherName;
  final String? initialDescription;

  const _ClassFormDialog({
    required this.title,
    this.initialName,
    this.initialSemester,
    this.initialTeacherId,
    this.initialTeacherName,
    this.initialDescription,
  });

  @override
  State<_ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<_ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _userDao = UserDao();

  late final TextEditingController _nameController;
  late final TextEditingController _semesterController;
  late final TextEditingController _descriptionController;

  List<UserModel> _teachers = [];
  String? _selectedTeacherId;
  String? _selectedTeacherName;
  bool _loadingTeachers = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _semesterController =
        TextEditingController(text: widget.initialSemester ?? '');
    _descriptionController =
        TextEditingController(text: widget.initialDescription ?? '');
    _selectedTeacherId = widget.initialTeacherId;
    _selectedTeacherName = widget.initialTeacherName;
    _loadTeachers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _semesterController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    try {
      final teachers = await _userDao.getTeachers();
      if (mounted) {
        setState(() {
          _teachers = teachers;
          _loadingTeachers = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 班级名称（必填）
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '班级名称 *',
                    hintText: '例如：移动应用开发 2024-A班',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入班级名称';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 学期
                TextFormField(
                  controller: _semesterController,
                  decoration: const InputDecoration(
                    labelText: '学期',
                    hintText: '例如：2024-2025学年第一学期',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                // 授课教师
                _loadingTeachers
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      )
                    : DropdownButtonFormField<String>(
                        value: _selectedTeacherId,
                        decoration: const InputDecoration(
                          labelText: '授课教师',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        isExpanded: true,
                        hint: const Text('选择教师'),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('未指定', style: TextStyle(color: Colors.grey)),
                          ),
                          ..._teachers.map((t) => DropdownMenuItem(
                                value: t.userId,
                                child: Text(
                                  '${t.realName ?? t.userId}（${t.userId}）',
                                ),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedTeacherId = value;
                            if (value != null) {
                              final teacher = _teachers.firstWhere(
                                (t) => t.userId == value,
                              );
                              _selectedTeacherName =
                                  teacher.realName ?? teacher.userId;
                            } else {
                              _selectedTeacherName = null;
                            }
                          });
                        },
                      ),
                const SizedBox(height: 16),

                // 描述
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '班级描述',
                    hintText: '简要描述班级信息',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  minLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'name': _nameController.text.trim(),
                'semester': _semesterController.text.trim().isEmpty
                    ? null
                    : _semesterController.text.trim(),
                'teacherId': _selectedTeacherId,
                'teacherName': _selectedTeacherName,
                'description': _descriptionController.text.trim().isEmpty
                    ? null
                    : _descriptionController.text.trim(),
              });
            }
          },
          child: Text(widget.initialName != null ? '保存' : '创建'),
        ),
      ],
    );
  }
}

// =============================================================================
// _ClassMemberSheet — 成员管理 DraggableScrollableSheet
// =============================================================================

class _ClassMemberSheet extends StatefulWidget {
  final int classId;
  final String className;
  final bool isArchived;
  final ClassDao classDao;
  final UserDao userDao;
  final VoidCallback onMembersChanged;

  const _ClassMemberSheet({
    required this.classId,
    required this.className,
    required this.isArchived,
    required this.classDao,
    required this.userDao,
    required this.onMembersChanged,
  });

  @override
  State<_ClassMemberSheet> createState() => _ClassMemberSheetState();
}

class _ClassMemberSheetState extends State<_ClassMemberSheet> {
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    try {
      final members = await widget.classDao.getClassMembers(widget.classId);
      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('_ClassMemberSheet._loadMembers error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredMembers {
    if (_searchQuery.isEmpty) return _members;
    final query = _searchQuery.toLowerCase();
    return _members.where((m) {
      final name = (m['real_name'] as String? ?? '').toLowerCase();
      final userId = (m['user_id'] as String? ?? '').toLowerCase();
      return name.contains(query) || userId.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 拖拽手柄
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题栏
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.group,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.className,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '共 ${_members.length} 名成员',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 添加成员按钮
                    if (!widget.isArchived)
                      TextButton.icon(
                        onPressed: _showAddMembersDialog,
                        icon: const Icon(Icons.person_add_outlined, size: 18),
                        label: const Text('添加'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                        ),
                      ),
                    // 关闭
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              // 搜索栏
              if (_members.length > 5)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: '搜索成员...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.grey.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.grey.withValues(alpha: 0.3),
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              const Divider(height: 1),
              // 成员列表
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredMembers.isEmpty
                        ? _buildEmptyMembers()
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            itemCount: _filteredMembers.length,
                            itemBuilder: (ctx, index) {
                              return _buildMemberTile(
                                  _filteredMembers[index], theme);
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyMembers() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty ? '未找到匹配的成员' : '暂无成员',
            style: TextStyle(color: Colors.grey[500]),
          ),
          if (!widget.isArchived && _searchQuery.isEmpty) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _showAddMembersDialog,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('添加学生'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member, ThemeData theme) {
    final userId = member['user_id'] as String? ?? '';
    final realName = member['real_name'] as String?;
    final memberRole = member['role'] as String? ?? 'student';
    final userRole = member['user_role'] as String? ?? 'student';
    final joinedAt = member['joined_at'] as String?;
    final displayName = realName ?? userId;

    final isTeacherMember = memberRole == 'teacher' || userRole == 'teacher' || userRole == 'admin';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isTeacherMember
              ? Colors.orange.withValues(alpha: 0.15)
              : const Color(0xFF667eea).withValues(alpha: 0.12),
          child: Text(
            displayName.isNotEmpty ? displayName[0] : '?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isTeacherMember
                  ? Colors.orange[700]
                  : const Color(0xFF667eea),
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                displayName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isTeacherMember) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '教师',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '学号 $userId${joinedAt != null ? '  ·  加入于 ${_formatShortDate(joinedAt)}' : ''}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        trailing: widget.isArchived
            ? null
            : IconButton(
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red.withValues(alpha: 0.7),
                  size: 20,
                ),
                tooltip: '移除成员',
                onPressed: () => _confirmRemoveMember(userId, displayName),
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Add Members Dialog
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showAddMembersDialog() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _AddMembersDialog(
        classId: widget.classId,
        classDao: widget.classDao,
      ),
    );

    if (result != null && result.isNotEmpty) {
      int successCount = 0;
      for (final uid in result) {
        final ok = await widget.classDao.addMember(widget.classId, uid);
        if (ok) successCount++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 $successCount 名学生')),
        );
        _loadMembers();
        widget.onMembersChanged();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Remove Member Confirmation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _confirmRemoveMember(String userId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('移除成员'),
        content: Text('确定要将「$displayName」从班级中移除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success =
          await widget.classDao.removeMember(widget.classId, userId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将「$displayName」移出班级')),
        );
        _loadMembers();
        widget.onMembersChanged();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _formatShortDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}

// =============================================================================
// _AddMembersDialog — 添加学生到班级（多选）
// =============================================================================

class _AddMembersDialog extends StatefulWidget {
  final int classId;
  final ClassDao classDao;

  const _AddMembersDialog({
    required this.classId,
    required this.classDao,
  });

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  List<UserModel> _availableStudents = [];
  final Set<String> _selectedIds = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAvailableStudents();
  }

  Future<void> _loadAvailableStudents() async {
    try {
      // 获取已在其他班级但不在当前班级的学生
      final currentMembers =
          await widget.classDao.getClassMembers(widget.classId);
      final currentMemberIds =
          currentMembers.map((m) => m['user_id'] as String).toSet();

      final allStudents = await UserDao().getStudents();
      final available = allStudents
          .where((s) => !currentMemberIds.contains(s.userId))
          .toList();

      if (mounted) {
        setState(() {
          _availableStudents = available;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('_AddMembersDialog._loadAvailableStudents error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<UserModel> get _filteredStudents {
    if (_searchQuery.isEmpty) return _availableStudents;
    final query = _searchQuery.toLowerCase();
    return _availableStudents.where((s) {
      final name = (s.realName ?? '').toLowerCase();
      final id = s.userId.toLowerCase();
      return name.contains(query) || id.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.person_add_outlined, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('添加学生')),
          if (_selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '已选 ${_selectedIds.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _availableStudents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sentiment_satisfied_alt,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          '没有可添加的学生',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '所有学生已分配到班级',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // 搜索栏
                      TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: '搜索学号或姓名...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                          fillColor: Colors.grey.withValues(alpha: 0.06),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 全选/取消全选
                      Row(
                        children: [
                          Text(
                            '共 ${_filteredStudents.length} 名学生可添加',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (_selectedIds.length ==
                                    _filteredStudents.length) {
                                  _selectedIds.clear();
                                } else {
                                  _selectedIds.clear();
                                  _selectedIds.addAll(
                                    _filteredStudents.map((s) => s.userId),
                                  );
                                }
                              });
                            },
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _selectedIds.length == _filteredStudents.length
                                  ? '取消全选'
                                  : '全选',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 8),
                      // 学生列表
                      Expanded(
                        child: _filteredStudents.isEmpty
                            ? Center(
                                child: Text(
                                  '未找到匹配的学生',
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _filteredStudents.length,
                                itemBuilder: (ctx, index) {
                                  final student = _filteredStudents[index];
                                  final isSelected =
                                      _selectedIds.contains(student.userId);
                                  return CheckboxListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    value: isSelected,
                                    onChanged: (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _selectedIds.add(student.userId);
                                        } else {
                                          _selectedIds.remove(student.userId);
                                        }
                                      });
                                    },
                                    secondary: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isSelected
                                          ? theme.colorScheme.primary
                                              .withValues(alpha: 0.15)
                                          : Colors.grey.withValues(alpha: 0.1),
                                      child: Text(
                                        (student.realName ?? student.userId)
                                            .substring(0, 1),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      student.realName ?? student.userId,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      '学号: ${student.userId}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    activeColor: theme.colorScheme.primary,
                                    checkboxShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedIds.toList()),
          child: Text(
            _selectedIds.isEmpty ? '添加' : '添加 (${_selectedIds.length})',
          ),
        ),
      ],
    );
  }
}
