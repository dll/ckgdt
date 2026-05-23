import 'package:flutter/material.dart';
import '../../../data/local/class_qa_dao.dart';
import '../../../data/models/class_qa_model.dart';
import '../../../services/auth_service.dart';

/// 班级问答详情页 — 显示问题 + 所有回复 + 教师回复入口 + 学生互助回复
class ClassQaDetailPage extends StatefulWidget {
  final int qaId;
  const ClassQaDetailPage({super.key, required this.qaId});
  @override
  State<ClassQaDetailPage> createState() => _ClassQaDetailPageState();
}

class _ClassQaDetailPageState extends State<ClassQaDetailPage> {
  final _auth = AuthService();
  final _replyCtl = TextEditingController();
  ClassQaModel? _qa;
  List<ClassQaReplyModel> _replies = [];
  bool _loading = true;
  bool _replying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final qa = await ClassQaDao.instance.get(widget.qaId);
    final replies = await ClassQaDao.instance.listReplies(widget.qaId);
    if (!mounted) return;
    setState(() {
      _qa = qa;
      _replies = replies;
      _loading = false;
    });
  }

  Future<void> _submitReply() async {
    final txt = _replyCtl.text.trim();
    if (txt.isEmpty || _qa == null) return;
    final user = _auth.currentUser;
    if (user == null) return;
    setState(() => _replying = true);
    final reply = ClassQaReplyModel(
      qaId: _qa!.id!,
      authorId: user.userId,
      authorName: user.realName ?? user.userId,
      authorRole: user.role,
      body: txt,
      isTeacher: _auth.isTeacher || _auth.isAdmin,
      createdAt: DateTime.now().toIso8601String(),
    );
    final id = await ClassQaDao.instance.addReply(reply);
    if (!mounted) return;
    setState(() => _replying = false);
    if (id > 0) {
      _replyCtl.clear();
      _load();
    }
  }

  Future<void> _accept(ClassQaReplyModel reply) async {
    if (_qa == null || reply.id == null) return;
    await ClassQaDao.instance
        .updateStatus(_qa!.id!, status: 'closed', acceptedReplyId: reply.id);
    _load();
  }

  Future<void> _like(ClassQaReplyModel reply) async {
    if (reply.id == null) return;
    await ClassQaDao.instance.incrementLike(reply.id!);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading || _qa == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('问题详情')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final qa = _qa!;
    final isAuthor = qa.authorId == _auth.currentUser?.userId;
    return Scaffold(
      appBar: AppBar(title: const Text('问题详情')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 问题主体
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(qa.title,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (qa.visibility == 'private')
                              const Icon(Icons.lock_outline,
                                  size: 18, color: Colors.grey),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('${qa.authorName} · ${qa.createdAt.substring(0, 16)}',
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.outline)),
                        const SizedBox(height: 12),
                        SelectableText(qa.body),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${_replies.length} 条回复',
                    style: TextStyle(
                        fontSize: 13, color: theme.colorScheme.outline),
                  ),
                ),
                const SizedBox(height: 8),
                // 回复列表
                ..._replies.map((r) =>
                    _buildReplyCard(r, theme, isAuthor: isAuthor, qa: qa)),
              ],
            ),
          ),
          // 回复输入
          _buildReplyInput(theme),
        ],
      ),
    );
  }

  Widget _buildReplyCard(ClassQaReplyModel r, ThemeData theme,
      {required bool isAuthor, required ClassQaModel qa}) {
    final isAccepted = qa.acceptedReplyId == r.id;
    final highlight = r.isTeacher
        ? Colors.amber.withValues(alpha: 0.10)
        : Colors.transparent;
    return Card(
      color: highlight == Colors.transparent ? null : highlight,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (r.isTeacher)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.school, size: 16, color: Colors.amber),
                  ),
                Text(r.authorName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (r.isTeacher)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('老师',
                        style: TextStyle(
                            fontSize: 11, color: Colors.amber)),
                  ),
                if (isAccepted)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Chip(
                      label: Text('已采纳', style: TextStyle(fontSize: 10)),
                      backgroundColor: Colors.green,
                      labelStyle: TextStyle(color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                const Spacer(),
                Text(r.createdAt.substring(11, 16),
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(r.body, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                  onPressed: () => _like(r),
                  visualDensity: VisualDensity.compact,
                ),
                Text('${r.likes}',
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.outline)),
                const Spacer(),
                if (isAuthor && !isAccepted && qa.status != 'closed')
                  TextButton.icon(
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('采纳此回答'),
                    onPressed: () => _accept(r),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyInput(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            12, 8, 12, 8 + MediaQuery.of(context).viewInsets.bottom),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _replyCtl,
                decoration: const InputDecoration(
                  hintText: '回复...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                minLines: 1,
                maxLines: 4,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _replying ? null : _submitReply,
              child: _replying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }
}
