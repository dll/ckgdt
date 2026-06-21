import 'package:flutter/material.dart';
import '../../../data/local/class_dao.dart';
import '../../../data/models/user_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/default_class_service.dart';
import 'student_detail_page.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

class StudentManagePage extends StatefulWidget {
  const StudentManagePage({super.key});

  @override
  State<StudentManagePage> createState() => _StudentManagePageState();
}

class _StudentManagePageState extends State<StudentManagePage> {
  final _authService = AuthService();
  final _classDao = ClassDao();
  final _defaultClassService = DefaultClassService.instance;

  List<UserModel> _students = [];
  List<Map<String, dynamic>> _classes = [];
  int? _selectedClassId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadClasses();
    await _loadStudents();
  }

  Future<void> _loadClasses() async {
    try {
      _classes = await _defaultClassService.getAvailableClasses();
      if (_classes.isNotEmpty && _selectedClassId == null) {
        _selectedClassId = await _defaultClassService.getDefaultClassId();
        // 如果没有设置过默认，用第一个活跃班级
        if (_selectedClassId == null) {
          _selectedClassId = _classes.first['id'] as int;
          await _defaultClassService.setDefaultClassId(_selectedClassId!);
        }
      }
    } catch (e) { swallowDebug(e, tag: 'student_manage_page'); }
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      List<UserModel> students;
      if (_selectedClassId != null) {
        students = await _classDao.getClassStudents(_selectedClassId!);
      } else {
        students = await _authService.getStudents();
      }
      if (mounted) {
        setState(() {
          _students = students;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cleanOrphanedData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理孤立数据'),
        content: const Text(
          '将删除所有已删除学生残留的关联数据（测验成绩、学习记录、错题、收藏等），'
          '同时清理远程仓库中的孤立同步文件。\n\n确定要清理吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final count = await _authService.cleanOrphanedData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count > 0
                ? '已清理 $count 条孤立数据记录，远程文件将异步清理'
                : '没有发现孤立数据'),
          ),
        );
      }
    }
  }

  Future<void> _addStudent() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddStudentDialog(classDao: _classDao),
    );

    if (result != null) {
      final student = UserModel(
        userId: result['userId'] as String,
        realName: result['realName'] as String?,
        repositoryUrl: result['repositoryUrl'] as String?,
        role: 'student',
        createdAt: DateTime.now().toIso8601String(),
      );

      final success = await _authService.createStudent(student);
      if (success && context.mounted) {
        // 如果选择了班级，自动加入 class_members
        final classId = result['classId'] as int?;
        if (classId != null) {
          await _classDao.addMember(classId, student.userId, role: 'student');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('添加成功')),
        );
        _loadStudents();
      }
    }
  }

  Future<void> _editStudent(UserModel student) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _EditStudentDialog(student: student),
    );

    if (result != null) {
      final updatedStudent = UserModel(
        userId: student.userId,
        realName: result['realName'],
        repositoryUrl: result['repositoryUrl'],
        role: student.role,
        createdAt: student.createdAt,
      );

      final success = await _authService.updateStudent(updatedStudent);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新成功')),
        );
        _loadStudents();
      }
    }
  }

  Future<void> _deleteStudent(UserModel student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除学生 ${student.realName ?? student.userId} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _authService.deleteStudent(student.userId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
        _loadStudents();
      }
    }
  }

  Future<void> _resetPassword(UserModel student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置密码'),
        content: Text(
          '确定要重置 ${student.realName ?? student.userId} 的密码吗？\n\n'
          '密码将恢复为默认密码（学号后6位）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success =
          await _authService.resetStudentPassword(student.userId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '已重置 ${student.realName ?? student.userId} 的密码为默认密码')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _classes.isNotEmpty && _classes.length > 1
            ? DropdownButton<int>(
                value: _selectedClassId,
                dropdownColor: Colors.white,
                underline: const SizedBox(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
                items: _classes.map((c) => DropdownMenuItem<int>(
                  value: c['id'] as int,
                  child: Text(c['name'] as String? ?? ''),
                )).toList(),
                onChanged: (id) async {
                  if (id != null) {
                    setState(() => _selectedClassId = id);
                    await _defaultClassService.setDefaultClassId(id);
                    _loadStudents();
                  }
                },
              )
            : const Text('学生管理'),

        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: '清理孤立数据',
            onPressed: _cleanOrphanedData,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStudents,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('暂无学生', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _addStudent,
                        icon: const Icon(Icons.add),
                        label: const Text('添加学生'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStudents,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      final hasRepo = student.repositoryUrl != null &&
                          student.repositoryUrl!.isNotEmpty;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple,
                            child: Text(
                              (student.realName ?? student.userId).substring(0, 1),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(student.realName ?? student.userId),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('学号: ${student.userId}'),
                              if (hasRepo)
                                Row(
                                  children: [
                                    Icon(Icons.code, size: 14, color: Colors.green[700]),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        student.repositoryUrl!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green[700],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasRepo)
                                IconButton(
                                  icon: Icon(Icons.visibility, color: Colors.green[700]),
                                  tooltip: '查看仓库详情',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => StudentDetailPage(
                                          student: student,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20),
                                tooltip: '更多操作',
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _editStudent(student);
                                    case 'reset_password':
                                      _resetPassword(student);
                                    case 'delete':
                                      _deleteStudent(student);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: Icon(Icons.edit, color: Colors.blue, size: 20),
                                      title: Text('编辑信息', style: TextStyle(fontSize: 14)),
                                      dense: true,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'reset_password',
                                    child: ListTile(
                                      leading: Icon(Icons.lock_reset, color: Colors.orange, size: 20),
                                      title: Text('重置密码', style: TextStyle(fontSize: 14)),
                                      dense: true,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete, color: Colors.red, size: 20),
                                      title: Text('删除学生', style: TextStyle(fontSize: 14)),
                                      dense: true,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: hasRepo
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StudentDetailPage(
                                        student: student,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addStudent,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _AddStudentDialog extends StatefulWidget {
  final ClassDao classDao;

  const _AddStudentDialog({required this.classDao});

  @override
  State<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<_AddStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _userIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _repoController = TextEditingController();

  List<Map<String, dynamic>> _classes = [];
  int? _selectedClassId;
  String? _teacherName;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final classes = await widget.classDao.getActiveClasses();
    if (mounted) {
      setState(() {
        _classes = classes;
        if (classes.isNotEmpty) {
          _selectedClassId = classes.first['id'] as int;
          _teacherName = classes.first['teacher_name'] as String?;
        }
      });
    }
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _nameController.dispose();
    _repoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加学生'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _userIdController,
                decoration: const InputDecoration(
                  labelText: '学号',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入学号';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '姓名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // 班级下拉框
              DropdownButtonFormField<int>(
                initialValue: _selectedClassId,
                decoration: const InputDecoration(
                  labelText: '班级',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.class_),
                ),
                items: _classes.map((c) {
                  return DropdownMenuItem<int>(
                    value: c['id'] as int,
                    child: Text(c['name'] as String? ?? ''),
                  );
                }).toList(),
                onChanged: (classId) {
                  setState(() {
                    _selectedClassId = classId;
                    final cls = _classes.firstWhere(
                        (c) => c['id'] == classId,
                        orElse: () => {});
                    _teacherName = cls['teacher_name'] as String?;
                  });
                },
                validator: (v) => v == null ? '请选择班级' : null,
              ),
              const SizedBox(height: 16),
              // 教师（只读，根据班级自动填充）
              TextFormField(
                readOnly: true,
                controller: TextEditingController(
                    text: _teacherName != null
                        ? '$_teacherName'
                        : ''),
                decoration: const InputDecoration(
                  labelText: '任课教师',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                  hintText: '选择班级后自动填充',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _repoController,
                decoration: const InputDecoration(
                  labelText: 'Gitee 仓库地址（选填）',
                  hintText: 'https://gitee.com/owner/repo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.code),
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
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'userId': _userIdController.text,
                'realName': _nameController.text,
                'repositoryUrl': _repoController.text,
                'classId': _selectedClassId,
              });
            }
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _EditStudentDialog extends StatefulWidget {
  final UserModel student;

  const _EditStudentDialog({required this.student});

  @override
  State<_EditStudentDialog> createState() => _EditStudentDialogState();
}

class _EditStudentDialogState extends State<_EditStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _repoController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.student.realName);
    _repoController = TextEditingController(text: widget.student.repositoryUrl ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _repoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑学生'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '姓名',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入姓名';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _repoController,
                decoration: const InputDecoration(
                  labelText: 'Gitee 仓库地址',
                  hintText: 'https://gitee.com/owner/repo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.code),
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
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'realName': _nameController.text,
                'repositoryUrl': _repoController.text,
              });
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
