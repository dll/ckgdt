import 'package:flutter/material.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/class_dao.dart';
import '../../../data/local/notification_dao.dart';
import '../../../services/auth_service.dart';

/// 发布通知页面 — 教师/管理员创建并发送通知
///
/// 表单字段：
/// - 标题（必填）
/// - 内容（必填，6行文本框）
/// - 发送范围：全部学生 / 指定班级
/// - 指定班级时显示班级下拉选择器
class ComposeNotificationPage extends StatefulWidget {
  const ComposeNotificationPage({super.key});

  @override
  State<ComposeNotificationPage> createState() =>
      _ComposeNotificationPageState();
}

class _ComposeNotificationPageState extends State<ComposeNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  final NotificationDao _notificationDao = NotificationDao();
  final ClassDao _classDao = ClassDao();
  final AuthService _authService = AuthService();

  /// 发送范围：'all' 或 'class'
  String _targetType = 'all';

  /// 选中的班级 ID（targetType='class' 时使用）
  int? _selectedClassId;

  /// 可选班级列表
  List<Map<String, dynamic>> _classes = [];

  /// 发布中状态
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  /// 加载可选班级
  Future<void> _loadClasses() async {
    try {
      final classes = await _classDao.getActiveClasses();
      if (mounted) {
        setState(() => _classes = classes);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'compose_notification_page._loadClasses', stack: st);
    }
  }

  /// 发布通知
  Future<void> _publishNotification() async {
    if (!_formKey.currentState!.validate()) return;

    // 指定班级时需选择班级
    if (_targetType == 'class' && _selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择目标班级')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final userId = _authService.getCurrentUserId();

      await _notificationDao.createNotification(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        creatorId: userId,
        targetType: _targetType,
        targetId:
            _targetType == 'class' ? _selectedClassId.toString() : null,
        type: 'manual',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知已发布')),
        );
        Navigator.of(context).pop(true); // 返回 true 表示已发布
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发布失败：$e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI 构建
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('发布通知'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 标题输入 ──────────────────────────────────────────────
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: '通知标题',
                  hintText: '请输入通知标题',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLength: 100,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入通知标题';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── 内容输入 ──────────────────────────────────────────────
              TextFormField(
                controller: _contentController,
                decoration: InputDecoration(
                  labelText: '通知内容',
                  hintText: '请输入通知内容...',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 100),
                    child: Icon(Icons.article_outlined),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 6,
                maxLength: 1000,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入通知内容';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── 发送范围 ──────────────────────────────────────────────
              Text(
                '发送范围',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: const Text('全部学生'),
                      subtitle: const Text('发送给所有活跃学生'),
                      value: 'all',
                      groupValue: _targetType,
                      onChanged: (v) {
                        setState(() {
                          _targetType = v!;
                          _selectedClassId = null;
                        });
                      },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    RadioListTile<String>(
                      title: const Text('指定班级'),
                      subtitle: const Text('仅发送给选定班级的学生'),
                      value: 'class',
                      groupValue: _targetType,
                      onChanged: (v) {
                        setState(() => _targetType = v!);
                      },
                    ),
                  ],
                ),
              ),

              // ── 班级选择器（仅 targetType='class' 时显示）──────────────
              if (_targetType == 'class') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(value: _selectedClassId,
                  decoration: InputDecoration(
                    labelText: '选择班级',
                    prefixIcon: const Icon(Icons.class_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _classes.map((cls) {
                    final id = cls['id'] as int;
                    final name = cls['name'] as String? ?? '未命名班级';
                    final count = cls['student_count'] as int? ?? 0;
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text('$name ($count人)'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedClassId = v),
                  hint: const Text('请选择班级'),
                  validator: (value) {
                    if (_targetType == 'class' && value == null) {
                      return '请选择目标班级';
                    }
                    return null;
                  },
                ),
              ],

              const SizedBox(height: 32),

              // ── 发布按钮 ──────────────────────────────────────────────
              FilledButton.icon(
                onPressed: _isPublishing ? null : _publishNotification,
                icon: _isPublishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_isPublishing ? '发布中...' : '发布通知'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
