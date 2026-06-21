import 'package:flutter/material.dart';
import '../../../data/local/teacher_application_dao.dart';
import '../../../data/local/notification_dao.dart';
import '../../../services/auth_service.dart';
import '../../widgets/back_button_bar.dart';

/// 教师申请页面 — 学生填写工号即可提交申请
class TeacherApplicationPage extends StatefulWidget {
  const TeacherApplicationPage({super.key});

  @override
  State<TeacherApplicationPage> createState() => _TeacherApplicationPageState();
}

class _TeacherApplicationPageState extends State<TeacherApplicationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _workIdController = TextEditingController();
  final _schoolController = TextEditingController();
  final _reasonController = TextEditingController();
  final _dao = TeacherApplicationDao();
  final _authService = AuthService();
  bool _isSubmitting = false;
  Map<String, dynamic>? _existingApp;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final userId = _authService.currentUser?.userId;
    if (userId == null) return;
    final app = await _dao.getApplicationByUser(userId);
    if (mounted) setState(() => _existingApp = app);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _workIdController.dispose();
    _schoolController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = _authService.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);
    try {
      await _dao.submitApplication(
        applicantId: user.userId,
        applicantName: _nameController.text.trim(),
        workId: _workIdController.text.trim(),
        school: _schoolController.text.trim(),
        reason: _reasonController.text.trim(),
      );

      // 通知管理员
      try {
        final notifDao = NotificationDao();
        await notifDao.createNotification(
          title: '新教师申请',
          content: '${_nameController.text.trim()} 申请成为教师（工号：${_workIdController.text.trim()}），请审核。',
          type: 'teacher_application',
          creatorId: user.userId,
          targetType: 'teachers',
        );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('申请已提交，请等待管理员审核'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final isAlreadyTeacher = _authService.isTeacher || _authService.isAdmin;

    return Scaffold(
      appBar: const BackButtonBar(title: '教师申请'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 已是教师
            if (isAlreadyTeacher) ...[
              Card(
                color: Colors.green[50],
                child: const ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('您已是教师身份'),
                  subtitle: Text('无需再次申请'),
                ),
              ),
            ]
            // 已有申请
            else if (_existingApp != null) ...[
              _buildApplicationStatus(),
            ]
            // 申请表单
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '申请成为教师',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '填写您的教师工号提交申请，管理员审核通过后即可使用教师功能。',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '姓名 *',
                        hintText: '请输入您的真实姓名',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _workIdController,
                      decoration: const InputDecoration(
                        labelText: '教师工号 *',
                        hintText: '请输入您的教师工号',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().length < 4) ? '请输入有效的教师工号' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _schoolController,
                      decoration: const InputDecoration(
                        labelText: '所在学校',
                        hintText: '选填',
                        prefixIcon: Icon(Icons.school),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '申请说明',
                        hintText: '选填，简要说明申请原因',
                        prefixIcon: Icon(Icons.note),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前账号：${user?.userId ?? ""}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        label: Text(_isSubmitting ? '提交中...' : '提交申请'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApplicationStatus() {
    final status = _existingApp!['status'] as String;
    final createdAt = _existingApp!['created_at'] as String? ?? '';

    IconData icon;
    Color color;
    String label;
    String subtitle;

    switch (status) {
      case 'pending':
        icon = Icons.hourglass_top;
        color = Colors.orange;
        label = '审核中';
        subtitle = '您的申请正在等待管理员审核';
      case 'approved':
        icon = Icons.check_circle;
        color = Colors.green;
        label = '已通过';
        subtitle = '请重新登录以启用教师功能';
      case 'rejected':
        icon = Icons.cancel;
        color = Colors.red;
        label = '已拒绝';
        subtitle = _existingApp!['review_comment'] as String? ?? '管理员未通过您的申请';
      default:
        icon = Icons.help;
        color = Colors.grey;
        label = status;
        subtitle = '';
    }

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 36),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            const SizedBox(height: 4),
            Text('提交时间：$createdAt', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
