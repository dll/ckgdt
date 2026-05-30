import 'package:flutter/material.dart';
import '../../widgets/back_button_bar.dart';
import '../../../data/local/class_qa_dao.dart';
import '../../../data/models/class_qa_model.dart';
import '../../../services/auth_service.dart';
import 'class_qa_detail_page.dart';
import 'class_qa_compose_page.dart';

/// 班级问答广场页 — 学生可发问，老师可回复，全班可见或仅老师可见。
class ClassQaPage extends StatefulWidget {
  const ClassQaPage({super.key});
  @override
  State<ClassQaPage> createState() => _ClassQaPageState();
}

class _ClassQaPageState extends State<ClassQaPage> {
  final _auth = AuthService();
  List<ClassQaModel> _items = [];
  bool _loading = true;
  String _filter = 'all'; // all / open / answered

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _auth.currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    final items = await ClassQaDao.instance.list(
      viewerId: user.userId,
      viewerIsTeacher: _auth.isTeacher || _auth.isAdmin,
      status: _filter == 'all' ? null : _filter,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: BackButtonBar(
        title: '班级问答',
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: '筛选',
            onSelected: (v) {
              setState(() => _filter = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('全部')),
              PopupMenuItem(value: 'open', child: Text('未回复')),
              PopupMenuItem(value: 'answered', child: Text('已回复')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_note),
        label: const Text('提问'),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ClassQaComposePage()),
          );
          _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? _buildEmpty(theme)
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) => _buildItem(_items[i], theme),
                  ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined,
              size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('暂无问答',
              style: TextStyle(color: theme.colorScheme.outline)),
          const SizedBox(height: 4),
          Text('点击右下角"提问"开始',
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildItem(ClassQaModel qa, ThemeData theme) {
    final isPrivate = qa.visibility == 'private';
    final isAnswered = qa.status == 'answered' || qa.status == 'closed';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isAnswered
            ? Colors.green.withValues(alpha: 0.15)
            : theme.colorScheme.primary.withValues(alpha: 0.15),
        foregroundColor: isAnswered ? Colors.green : theme.colorScheme.primary,
        child: Icon(isAnswered ? Icons.check : Icons.help_outline),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(qa.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (isPrivate)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.lock_outline, size: 14, color: Colors.grey),
            ),
        ],
      ),
      subtitle: Text(
        '${qa.authorName} · ${_short(qa.body)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ClassQaDetailPage(qaId: qa.id!)),
        );
        _load();
      },
    );
  }

  String _short(String s) {
    s = s.replaceAll('\n', ' ').trim();
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }
}
