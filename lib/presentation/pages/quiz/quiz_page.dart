import 'package:flutter/material.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/wrong_answer_dao.dart';
import '../../../data/models/question_model.dart';
import '../../../data/models/quiz_result_model.dart';
import '../../../services/auth_service.dart';
import 'wrong_answers_page.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final _quizDao = QuizDao();
  final _wrongAnswerDao = WrongAnswerDao();
  final _authService = AuthService();
  
  List<String> _chapters = [];
  String? _selectedChapter;
  List<QuestionModel> _questions = [];
  int _currentIndex = 0;
  int? _selectedAnswer;
  bool _answered = false;
  int _correctCount = 0;
  bool _isLoading = true;
  bool _quizStarted = false;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    setState(() => _isLoading = true);
    try {
      final chapters = await _quizDao.getChapters();
      setState(() {
        _chapters = chapters;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startQuiz(String chapter) async {
    setState(() {
      _selectedChapter = chapter;
      _isLoading = true;
    });
    
    try {
      final questions = await _quizDao.getQuestionsByChapter(chapter);
      setState(() {
        _questions = questions;
        _quizStarted = true;
        _currentIndex = 0;
        _correctCount = 0;
        _selectedAnswer = null;
        _answered = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _submitAnswer() {
    if (_selectedAnswer == null) return;
    
    final currentQuestion = _questions[_currentIndex];
    final isCorrect = _selectedAnswer == currentQuestion.answerIndex;
    
    // 记录错题
    if (!isCorrect) {
      _recordWrongAnswer(currentQuestion);
    }
    
    setState(() {
      _answered = true;
      if (isCorrect) _correctCount++;
    });
  }

  Future<void> _recordWrongAnswer(QuestionModel question) async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final options = question.options;
        await _wrongAnswerDao.addWrongAnswer(
          userId: user.userId,
          questionId: question.id ?? 0,
          question: question.question,
          userAnswer: _selectedAnswer != null && _selectedAnswer! < options.length 
              ? options[_selectedAnswer!] 
              : '',
          correctAnswer: question.correctAnswer,
          chapter: _selectedChapter ?? '',
        );
      }
    } catch (e) {
      // 忽略错误
    }
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _answered = false;
      });
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final user = _authService.currentUser;
    if (user == null) return;

    final result = QuizResultModel(
      userId: user.userId,
      quizTimestamp: DateTime.now().toIso8601String(),
      score: ((_correctCount / _questions.length) * 100).round(),
      numCorrect: _correctCount,
      numTotal: _questions.length,
      chapter: _selectedChapter,
      completedAt: DateTime.now().toIso8601String(),
    );

    await _quizDao.saveQuizResult(result);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('测验完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _correctCount > _questions.length / 2 
                    ? Icons.celebration 
                    : Icons.sentiment_neutral,
                size: 64,
                color: _correctCount > _questions.length / 2 
                    ? Colors.green 
                    : Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                '得分: ${result.score}分',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text('正确: $_correctCount / ${_questions.length}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _quizStarted = false;
                  _questions = [];
                });
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_quizStarted && _questions.isNotEmpty) {
      return _buildQuizView();
    }

    return _buildChapterSelection();
  }

  Widget _buildChapterSelection() {
    if (_chapters.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '暂无测验题目',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadChapters,
              child: const Text('刷新'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '选择测验章节',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ..._chapters.map((chapter) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.orange,
              child: Icon(Icons.quiz, color: Colors.white),
            ),
            title: Text(chapter),
            trailing: const Icon(Icons.play_arrow),
            onTap: () => _startQuiz(chapter),
          ),
        )),
        const SizedBox(height: 24),
        // 错题本按钮
        Card(
          color: Colors.red[50],
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red,
              child: const Icon(Icons.error, color: Colors.white),
            ),
            title: const Text('错题本'),
            subtitle: const Text('查看和复习做错的题目'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WrongAnswersPage()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuizView() {
    final question = _questions[_currentIndex];
    
    return Column(
      children: [
        // 进度条
        LinearProgressIndicator(
          value: (_currentIndex + 1) / _questions.length,
          backgroundColor: Colors.grey[200],
          valueColor: const AlwaysStoppedAnimation(Color(0xFF667eea)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第 ${_currentIndex + 1} / ${_questions.length} 题',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Text(
                  question.question,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                ...List.generate(4, (index) {
                  final options = question.options;
                  final isSelected = _selectedAnswer == index;
                  final isCorrect = index == question.answerIndex;
                  
                  Color? bgColor;
                  Color? borderColor;
                  
                  if (_answered) {
                    if (isCorrect) {
                      bgColor = Colors.green[100];
                      borderColor = Colors.green;
                    } else if (isSelected && !isCorrect) {
                      bgColor = Colors.red[100];
                      borderColor = Colors.red;
                    }
                  } else if (isSelected) {
                    bgColor = const Color(0xFF667eea).withValues(alpha: 0.3);
                    borderColor = const Color(0xFF667eea);
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: _answered ? null : () {
                        setState(() => _selectedAnswer = index);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: bgColor,
                          border: Border.all(
                            color: borderColor ?? Colors.grey[300]!,
                            width: isSelected || (_answered && isCorrect) ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: borderColor ?? Colors.grey,
                                ),
                                color: isSelected ? borderColor : null,
                              ),
                              child: isSelected 
                                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(options[index])),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // 底部按钮
        Container(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _answered 
                  ? _nextQuestion 
                  : (_selectedAnswer != null ? _submitAnswer : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667eea),
                foregroundColor: Colors.white,
              ),
              child: Text(
                _answered 
                    ? (_currentIndex < _questions.length - 1 ? '下一题' : '完成测验')
                    : '提交答案'
              ),
            ),
          ),
        ),
      ],
    );
  }
}
