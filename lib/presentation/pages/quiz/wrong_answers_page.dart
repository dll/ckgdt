import 'package:flutter/material.dart';
import '../../../data/local/wrong_answer_dao.dart';
import '../../../services/auth_service.dart';

class WrongAnswersPage extends StatefulWidget {
  const WrongAnswersPage({super.key});

  @override
  State<WrongAnswersPage> createState() => _WrongAnswersPageState();
}

class _WrongAnswersPageState extends State<WrongAnswersPage> {
  final _wrongAnswerDao = WrongAnswerDao();
  final _authService = AuthService();

  List<Map<String, dynamic>> _wrongAnswers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final wrongAnswers = await _wrongAnswerDao.getWrongAnswers(user.userId);
        setState(() {
          _wrongAnswers = wrongAnswers;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeWrongAnswer(int id) async {
    final userId = _authService.currentUser?.userId ?? '';
    await _wrongAnswerDao.removeWrongAnswer(id, userId);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从错题本移除')),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有错题吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = _authService.currentUser;
      if (user != null) {
        await _wrongAnswerDao.clearWrongAnswers(user.userId);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已清空所有错题')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('错题本'),

        actions: [
          if (_wrongAnswers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _wrongAnswers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 64, color: Colors.green[300]),
                      const SizedBox(height: 16),
                      const Text(
                        '太棒了！没有错题',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _wrongAnswers.length,
                    itemBuilder: (context, index) {
                      final wrong = _wrongAnswers[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red[100],
                            child: Text(
                              '${wrong['times'] ?? 1}',
                              style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            wrong['question'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '错误次数: ${wrong['times'] ?? 1}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '题目：${wrong['question']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '你的答案：${wrong['user_answer']}',
                                    style: TextStyle(color: Colors.red[700]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '正确答案：${wrong['correct_answer']}',
                                    style: TextStyle(color: Colors.green[700]),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                          // 返回首页并切换到知识图谱 Tab
                                          Navigator.pop(context, 'go_learn');
                                        },
                                        icon: const Icon(Icons.menu_book,
                                            size: 18,
                                            color: Color(0xFF667eea)),
                                        label: const Text('去学习',
                                            style: TextStyle(
                                                color: Color(0xFF667eea))),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _removeWrongAnswer(wrong['id']),
                                        icon: const Icon(Icons.remove_circle_outline),
                                        label: const Text('移除'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
