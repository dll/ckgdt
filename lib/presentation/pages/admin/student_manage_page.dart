import 'package:flutter/material.dart';
import '../../../data/local/user_dao.dart';
import '../../../data/models/user_model.dart';
import '../../../services/auth_service.dart';
import 'student_detail_page.dart';

class StudentManagePage extends StatefulWidget {
  const StudentManagePage({super.key});

  @override
  State<StudentManagePage> createState() => _StudentManagePageState();
}

class _StudentManagePageState extends State<StudentManagePage> {
  final _userDao = UserDao();
  final _authService = AuthService();

  List<UserModel> _students = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      final students = await _authService.getStudents();
      setState(() {
        _students = students;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addStudent() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _AddStudentDialog(),
    );

    if (result != null) {
      final student = UserModel(
        userId: result['userId']!,
        realName: result['realName'],
        repositoryUrl: result['repositoryUrl'],
        role: 'student',
        createdAt: DateTime.now().toIso8601String(),
      );

      final success = await _authService.createStudent(student);
      if (success && mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学生管理'),

        actions: [
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
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editStudent(student),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteStudent(student),
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
  @override
  State<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<_AddStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _userIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _repoController = TextEditingController();

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
