import 'package:flutter/material.dart';
import '../../../data/local/wrong_answer_dao.dart';
import '../../../data/local/learning_path_dao.dart';
import '../../../services/ai_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../../services/tts_flutter_service.dart';
import '../../widgets/back_button_bar.dart';

class WrongAnswersPage extends StatefulWidget {
  const WrongAnswersPage({super.key});

  @override
  State<WrongAnswersPage> createState() => _WrongAnswersPageState();
}

class _WrongAnswersPageState extends State<WrongAnswersPage> {
  final _wrongAnswerDao = WrongAnswerDao();
  final _authService = AuthService();
  final _courseContext = CourseContextService();

  List<Map<String, dynamic>> _wrongAnswers = [];
  bool _isLoading = true;
  Color primary = const Color(0xFF1677FF);

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

  /// 手动触发 AI 解释生成
  Future<void> _generateExplanation(Map<String, dynamic> wrong) async {
    try {
      final aiService = AiService();
      final courseName = await _courseContext.activeCourseName();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在生成 AI 解析...')),
        );
      }

      final prompt =
          '题目：${wrong['question']}\n学生答案：${wrong['user_answer']}\n正确答案：${wrong['correct_answer']}\n\n'
          '请用 2-3 句话简明解释为什么正确答案是对的，以及学生答案错在哪里。';

      final explanation = await aiService.chat(
        [
          {'role': 'user', 'content': prompt}
        ],
        systemPrompt: '你是《$courseName》课程的教学助手，专门为学生解释测验错题。回答简洁精准。',
      );

      if (explanation.isNotEmpty) {
        await _wrongAnswerDao.updateExplanation(
            wrong['id'] as int, explanation);
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
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

  Future<void> _generateRemediationPath() async {
    final user = _authService.currentUser;
    if (user == null) return;
    try {
      final pathId =
          await LearningPathDao().generateRemediationPath(user.userId);
      if (!mounted) return;
      if (pathId > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('已生成补强路径，可在学习路径中查看'),
              backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无可关联的薄弱节点')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e'), backgroundColor: Colors.red),
        );
      }
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
    primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: BackButtonBar(
        title: '错题本',
        actions: [
          if (_wrongAnswers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.route),
              tooltip: '生成补强路径',
              onPressed: _generateRemediationPath,
            ),
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
                      Icon(Icons.check_circle,
                          size: 64, color: Colors.green[300]),
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
                              style: TextStyle(
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.bold),
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
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
                                  // AI 解释区域
                                  if (wrong['explanation'] != null &&
                                      (wrong['explanation'] as String)
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: primary.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color:
                                              primary.withValues(alpha: 0.15),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.auto_awesome,
                                                  size: 16,
                                                  color: Colors.amber[700]),
                                              const SizedBox(width: 6),
                                              Text(
                                                'AI 解析',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: primary,
                                                ),
                                              ),
                                              const Spacer(),
                                              InkWell(
                                                onTap: () {
                                                  TtsFlutterService.instance
                                                      .speak(
                                                          wrong['explanation']
                                                              as String);
                                                },
                                                child: Icon(Icons.volume_up,
                                                    size: 18,
                                                    color: Colors.grey[500]),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            wrong['explanation'] as String,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[800],
                                              height: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _generateExplanation(wrong),
                                      icon: const Icon(Icons.auto_awesome,
                                          size: 16),
                                      label: const Text('生成 AI 解析'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                          // 返回首页并切换到知识图谱 Tab
                                          Navigator.pop(context, 'go_learn');
                                        },
                                        icon: Icon(Icons.menu_book,
                                            size: 18, color: primary),
                                        label: Text('去学习',
                                            style: TextStyle(color: primary)),
                                      ),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _removeWrongAnswer(wrong['id']),
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
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
