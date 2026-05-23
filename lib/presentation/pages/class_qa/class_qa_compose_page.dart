import 'package:flutter/material.dart';
import '../../../data/local/class_qa_dao.dart';
import '../../../data/models/class_qa_model.dart';
import '../../../services/auth_service.dart';

/// 提问编辑页 — 学生发起新问题（也允许教师发"FAQ 答疑"主帖）。
class ClassQaComposePage extends StatefulWidget {
  const ClassQaComposePage({super.key});
  @override
  State<ClassQaComposePage> createState() => _ClassQaComposePageState();
}

class _ClassQaComposePageState extends State<ClassQaComposePage> {
  final _titleCtl = TextEditingController();
  final _bodyCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _visibility = 'class';
  bool _saving = false;

  @override
  void dispose() {
    _titleCtl.dispose();
    _bodyCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = AuthService().currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    final now = DateTime.now().toIso8601String();
    final qa = ClassQaModel(
      authorId: user.userId,
      authorName: user.realName ?? user.userId,
      authorRole: user.role,
      title: _titleCtl.text.trim(),
      body: _bodyCtl.text.trim(),
      visibility: _visibility,
      createdAt: now,
      updatedAt: now,
    );
    final id = await ClassQaDao.instance.create(qa);
    if (!mounted) return;
    setState(() => _saving = false);
    if (id > 0) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提交失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提问')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleCtl,
              decoration: const InputDecoration(
                labelText: '问题标题',
                hintText: '简要描述（≤ 80 字）',
                border: OutlineInputBorder(),
              ),
              maxLength: 80,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '标题不能为空' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyCtl,
              decoration: const InputDecoration(
                labelText: '问题详情',
                hintText: '详细描述你的问题，可粘贴报错信息、代码片段等（支持 Markdown）',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 10,
              minLines: 5,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '问题详情不能为空' : null,
            ),
            const SizedBox(height: 16),
            const Text('可见性', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'class',
                  label: Text('全班可见'),
                  icon: Icon(Icons.groups),
                ),
                ButtonSegment(
                  value: 'private',
                  label: Text('仅老师可见'),
                  icon: Icon(Icons.lock_outline),
                ),
              ],
              selected: {_visibility},
              onSelectionChanged: (s) =>
                  setState(() => _visibility = s.first),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_saving ? '提交中...' : '提交问题'),
            ),
          ],
        ),
      ),
    );
  }
}
