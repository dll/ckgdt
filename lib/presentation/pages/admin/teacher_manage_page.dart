import 'package:flutter/material.dart';
import '../../../data/local/user_dao.dart';
import '../../../data/models/user_model.dart';
import '../../../data/local/class_dao.dart';

/// 教师管理页面 — 管理员面板
///
/// 功能：教师/管理员列表、搜索筛选、增删改、班级关联查看、统计概览。
class TeacherManagePage extends StatefulWidget {
  const TeacherManagePage({super.key});

  @override
  State<TeacherManagePage> createState() => _TeacherManagePageState();
}

class _TeacherManagePageState extends State<TeacherManagePage> {
  final _userDao = UserDao();
  final _classDao = ClassDao();

  List<UserModel> _allTeachers = [];
  List<UserModel> _filteredTeachers = [];
  Map<String, List<Map<String, dynamic>>> _teacherClassesMap = {};

  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // 统计数据
  int _totalCount = 0;
  int _activeCount = 0;
  int _adminCount = 0;
  int _teacherCount = 0;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 数据加载
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _loadTeachers() async {
    setState(() => _isLoading = true);
    try {
      final teachers = await _userDao.getTeachers();

      // 为每位教师加载关联班级
      final classesMap = <String, List<Map<String, dynamic>>>{};
      for (final t in teachers) {
        try {
          final classes = await _classDao.getTeacherClasses(t.userId);
          classesMap[t.userId] = classes;
        } catch (_) {
          classesMap[t.userId] = [];
        }
      }

      // 计算统计数据
      final total = teachers.length;
      final active = teachers.where((t) => t.isActive).length;
      final admins = teachers.where((t) => t.isAdmin).length;
      final pureTeachers = teachers.where((t) => t.isTeacher).length;

      if (!mounted) return;
      setState(() {
        _allTeachers = teachers;
        _teacherClassesMap = classesMap;
        _totalCount = total;
        _activeCount = active;
        _adminCount = admins;
        _teacherCount = pureTeachers;
        _isLoading = false;
      });

      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('加载教师列表失败：$e', isError: true);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 搜索与过滤
  // ───────────────────────────────────────────────────────────────────────────

  void _applyFilter() {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredTeachers = List.from(_allTeachers));
      return;
    }
    setState(() {
      _filteredTeachers = _allTeachers.where((t) {
        final name = (t.realName ?? '').toLowerCase();
        final id = t.userId.toLowerCase();
        final role = _roleLabel(t.role).toLowerCase();
        return name.contains(query) || id.contains(query) || role.contains(query);
      }).toList();
    });
  }

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _applyFilter();
  }

  void _clearSearch() {
    _searchController.clear();
    _searchQuery = '';
    _applyFilter();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 添加教师
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _addTeacher() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _AddTeacherDialog(),
    );

    if (result == null || !mounted) return;

    final userId = result['userId']!;
    final realName = result['realName'] ?? '';
    final role = result['role'] ?? 'teacher';

    // 检查用户是否已存在
    final existing = await _userDao.getUser(userId);
    if (existing != null && mounted) {
      _showSnackBar('用户 $userId 已存在，无法重复添加', isError: true);
      return;
    }

    final teacher = UserModel(
      userId: userId,
      realName: realName.isNotEmpty ? realName : null,
      role: role,
      createdAt: DateTime.now().toIso8601String(),
    );

    final success = await _userDao.createUser(teacher);
    if (!mounted) return;

    if (success) {
      _showSnackBar('教师 ${realName.isNotEmpty ? realName : userId} 添加成功');
      _loadTeachers();
    } else {
      _showSnackBar('添加失败，请重试', isError: true);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 编辑教师
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _editTeacher(UserModel teacher) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _EditTeacherDialog(teacher: teacher),
    );

    if (result == null || !mounted) return;

    final updatedTeacher = UserModel(
      userId: teacher.userId,
      realName: result['realName'],
      machineCode: teacher.machineCode,
      role: result['role'] ?? teacher.role,
      createdAt: teacher.createdAt,
      lastLogin: teacher.lastLogin,
      isActive: result['isActive'] == 'true',
    );

    final success = await _userDao.updateUser(updatedTeacher);
    if (!mounted) return;

    if (success) {
      _showSnackBar('教师信息更新成功');
      _loadTeachers();
    } else {
      _showSnackBar('更新失败，请重试', isError: true);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 删除教师
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _deleteTeacher(UserModel teacher) async {
    // 默认管理员不能删除
    if (teacher.userId == '419116') {
      _showSnackBar('默认管理员账号不可删除', isError: true);
      return;
    }

    final displayName = teacher.realName ?? teacher.userId;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('确认删除'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除 $displayName 吗？'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '此操作不可撤销，该教师关联的班级将不会被删除。',
                      style: TextStyle(fontSize: 13, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final success = await _userDao.deleteUser(teacher.userId);
    if (!mounted) return;

    if (success) {
      _showSnackBar('$displayName 已删除');
      _loadTeachers();
    } else {
      _showSnackBar('删除失败，请重试', isError: true);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 查看教师班级
  // ───────────────────────────────────────────────────────────────────────────

  void _showTeacherClasses(UserModel teacher) {
    final classes = _teacherClassesMap[teacher.userId] ?? [];
    final displayName = teacher.realName ?? teacher.userId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // 拖拽手柄
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.class_outlined, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      '$displayName 的班级',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${classes.length} 个班级',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 班级列表
              Expanded(
                child: classes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.school_outlined,
                                size: 56, color: Colors.grey.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text(
                              '暂未分配班级',
                              style: TextStyle(
                                color: Colors.grey.withValues(alpha: 0.7),
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: classes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final cls = classes[index];
                          final isArchived = cls['is_archived'] == 1;
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isArchived
                                    ? Colors.grey.withValues(alpha: 0.3)
                                    : Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.2),
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isArchived
                                    ? Colors.grey.withValues(alpha: 0.2)
                                    : Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.1),
                                child: Icon(
                                  isArchived ? Icons.archive_outlined : Icons.groups,
                                  color: isArchived
                                      ? Colors.grey
                                      : Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                cls['name'] ?? '未命名班级',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  decoration: isArchived
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              subtitle: Text(
                                cls['semester'] ?? '未设置学期',
                                style: const TextStyle(fontSize: 13),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isArchived)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        '已归档',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey),
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${cls['student_count'] ?? 0} 人',
                                    style: TextStyle(
                                      color: Colors.grey.withValues(alpha: 0.7),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 切换教师启用状态
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _toggleTeacherActive(UserModel teacher) async {
    if (teacher.userId == '419116') {
      _showSnackBar('默认管理员不可禁用', isError: true);
      return;
    }

    final newState = !teacher.isActive;
    final updated = UserModel(
      userId: teacher.userId,
      realName: teacher.realName,
      machineCode: teacher.machineCode,
      role: teacher.role,
      createdAt: teacher.createdAt,
      lastLogin: teacher.lastLogin,
      isActive: newState,
    );

    final success = await _userDao.updateUser(updated);
    if (!mounted) return;

    if (success) {
      _showSnackBar(newState ? '已启用' : '已禁用');
      _loadTeachers();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 辅助方法
  // ───────────────────────────────────────────────────────────────────────────

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return '管理员';
      case 'teacher':
        return '教师';
      default:
        return role;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.deepOrange;
      case 'teacher':
        return const Color(0xFF667eea);
      default:
        return Colors.grey;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'teacher':
        return Icons.school;
      default:
        return Icons.person;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI 构建
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('教师管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadTeachers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTeachers,
              child: CustomScrollView(
                slivers: [
                  // 统计卡片
                  SliverToBoxAdapter(child: _buildStatisticsSection(primaryColor)),
                  // 搜索栏
                  SliverToBoxAdapter(child: _buildSearchBar(primaryColor)),
                  // 列表或空状态
                  _filteredTeachers.isEmpty
                      ? SliverFillRemaining(child: _buildEmptyState())
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= _filteredTeachers.length) return null;
                                return _buildTeacherCard(_filteredTeachers[index]);
                              },
                              childCount: _filteredTeachers.length,
                            ),
                          ),
                        ),
                  // 底部间距（避免 FAB 遮挡末尾项）
                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTeacher,
        icon: const Icon(Icons.person_add),
        label: const Text('添加教师'),
      ),
    );
  }

  // ─── 统计概览卡片 ──────────────────────────────────────────────────────────

  Widget _buildStatisticsSection(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.people,
              label: '总计',
              value: '$_totalCount',
              color: primaryColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.check_circle_outline,
              label: '启用中',
              value: '$_activeCount',
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.school,
              label: '教师',
              value: '$_teacherCount',
              color: const Color(0xFF667eea),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.admin_panel_settings,
              label: '管理员',
              value: '$_adminCount',
              color: Colors.deepOrange,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 搜索栏 ────────────────────────────────────────────────────────────────

  Widget _buildSearchBar(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: '搜索教师姓名、工号或角色…',
          prefixIcon: Icon(Icons.search, color: primaryColor.withValues(alpha: 0.6)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: _clearSearch,
                )
              : null,
          filled: true,
          fillColor: primaryColor.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ─── 空状态 ────────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final hasFilter = _searchQuery.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilter ? Icons.search_off : Icons.people_outline,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilter ? '未找到匹配的教师' : '暂无教师数据',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.withValues(alpha: 0.7),
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('清除搜索'),
            ),
          ] else ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _addTeacher,
              icon: const Icon(Icons.person_add),
              label: const Text('添加教师'),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 教师卡片 ──────────────────────────────────────────────────────────────

  Widget _buildTeacherCard(UserModel teacher) {
    final displayName = teacher.realName ?? teacher.userId;
    final roleColor = _roleColor(teacher.role);
    final classes = _teacherClassesMap[teacher.userId] ?? [];
    final activeClasses = classes.where((c) => c['is_archived'] != 1).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: teacher.isActive
              ? roleColor.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTeacherClasses(teacher),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 头像
              _buildAvatar(teacher, roleColor),
              const SizedBox(width: 14),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行：姓名 + 角色标签
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: teacher.isActive ? null : Colors.grey,
                              decoration: teacher.isActive
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildRoleChip(teacher.role, roleColor),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 第二行：工号
                    Text(
                      '工号: ${teacher.userId}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 第三行：班级信息 + 状态
                    Row(
                      children: [
                        Icon(Icons.class_outlined,
                            size: 14, color: Colors.grey.withValues(alpha: 0.6)),
                        const SizedBox(width: 4),
                        Text(
                          activeClasses > 0
                              ? '负责 $activeClasses 个班级'
                              : '暂无班级',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.withValues(alpha: 0.6),
                          ),
                        ),
                        const Spacer(),
                        if (!teacher.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '已禁用',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // 操作菜单
              _buildPopupMenu(teacher),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(UserModel teacher, Color roleColor) {
    final initial = (teacher.realName ?? teacher.userId).characters.first;
    return Stack(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: teacher.isActive
              ? roleColor.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.15),
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: teacher.isActive ? roleColor : Colors.grey,
            ),
          ),
        ),
        // 在线状态小圆点
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: teacher.isActive ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).cardColor,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleChip(String role, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_roleIcon(role), size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            _roleLabel(role),
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupMenu(UserModel teacher) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: Colors.grey.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 40),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            _editTeacher(teacher);
            break;
          case 'classes':
            _showTeacherClasses(teacher);
            break;
          case 'toggle':
            _toggleTeacherActive(teacher);
            break;
          case 'delete':
            _deleteTeacher(teacher);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined, size: 20),
            title: Text('编辑信息', style: TextStyle(fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'classes',
          child: ListTile(
            leading: Icon(Icons.class_outlined, size: 20),
            title: Text('查看班级', style: TextStyle(fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: ListTile(
            leading: Icon(
              teacher.isActive ? Icons.block : Icons.check_circle_outline,
              size: 20,
              color: teacher.isActive ? Colors.orange : Colors.green,
            ),
            title: Text(
              teacher.isActive ? '禁用账号' : '启用账号',
              style: const TextStyle(fontSize: 14),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, size: 20, color: Colors.red),
            title: Text('删除', style: TextStyle(fontSize: 14, color: Colors.red)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 统计卡片组件
// =============================================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 添加教师对话框
// =============================================================================

class _AddTeacherDialog extends StatefulWidget {
  const _AddTeacherDialog();

  @override
  State<_AddTeacherDialog> createState() => _AddTeacherDialogState();
}

class _AddTeacherDialogState extends State<_AddTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  final _userIdController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedRole = 'teacher';

  @override
  void dispose() {
    _userIdController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.person_add, size: 24),
          SizedBox(width: 8),
          Text('添加教师'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _userIdController,
                decoration: const InputDecoration(
                  labelText: '工号 *',
                  hintText: '请输入教师工号',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入工号';
                  }
                  if (value.trim().length < 4) {
                    return '工号至少 4 位';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '姓名',
                  hintText: '请输入教师姓名',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: '角色 *',
                  prefixIcon: Icon(Icons.assignment_ind_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'teacher', child: Text('教师')),
                  DropdownMenuItem(value: 'admin', child: Text('管理员')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedRole = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '初始密码为工号后 6 位',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'userId': _userIdController.text.trim(),
                'realName': _nameController.text.trim(),
                'role': _selectedRole,
              });
            }
          },
          icon: const Icon(Icons.check, size: 18),
          label: const Text('添加'),
        ),
      ],
    );
  }
}

// =============================================================================
// 编辑教师对话框
// =============================================================================

class _EditTeacherDialog extends StatefulWidget {
  final UserModel teacher;

  const _EditTeacherDialog({required this.teacher});

  @override
  State<_EditTeacherDialog> createState() => _EditTeacherDialogState();
}

class _EditTeacherDialogState extends State<_EditTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String _selectedRole;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.teacher.realName ?? '');
    _selectedRole = widget.teacher.role;
    _isActive = widget.teacher.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDefaultAdmin = widget.teacher.userId == '419116';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.edit, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '编辑 — ${widget.teacher.realName ?? widget.teacher.userId}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 工号（只读）
              TextFormField(
                initialValue: widget.teacher.userId,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: '工号',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                style: TextStyle(color: Colors.grey.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 16),
              // 姓名
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '姓名 *',
                  hintText: '请输入教师姓名',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入姓名';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // 角色
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: '角色',
                  prefixIcon: Icon(Icons.assignment_ind_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'teacher', child: Text('教师')),
                  DropdownMenuItem(value: 'admin', child: Text('管理员')),
                ],
                onChanged: isDefaultAdmin
                    ? null // 默认管理员角色不可修改
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedRole = value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              // 启用状态
              SwitchListTile(
                title: const Text('账号状态'),
                subtitle: Text(_isActive ? '已启用' : '已禁用'),
                value: _isActive,
                onChanged: isDefaultAdmin
                    ? null // 默认管理员不可禁用
                    : (value) => setState(() => _isActive = value),
                contentPadding: EdgeInsets.zero,
              ),
              if (isDefaultAdmin)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '默认管理员角色和状态不可修改',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'realName': _nameController.text.trim(),
                'role': _selectedRole,
                'isActive': _isActive.toString(),
              });
            }
          },
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('保存'),
        ),
      ],
    );
  }
}
