import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/learning_record_dao.dart';
import '../../../data/models/quiz_result_model.dart';
import '../../../services/auth_service.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> with SingleTickerProviderStateMixin {
  final _quizDao = QuizDao();
  final _learningRecordDao = LearningRecordDao();
  final _authService = AuthService();
  late TabController _tabController;
  
  List<QuizResultModel> _results = [];
  Map<String, dynamic> _quizSummary = {};
  Map<String, dynamic> _learningStats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final results = await _quizDao.getQuizResults(user.userId);
        final quizSummary = await _quizDao.getQuizSummary(user.userId);
        final learningStats = await _learningRecordDao.getStatistics(user.userId);
        setState(() {
          _results = results;
          _quizSummary = quizSummary;
          _learningStats = learningStats;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF667eea),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: '测验成绩'),
            Tab(text: '学习记录'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildQuizTab(),
                _buildLearningTab(),
              ],
            ),
    );
  }

  Widget _buildQuizTab() {
    final totalCount = _quizSummary['total_count'] ?? 0;
    final avgScore = (_quizSummary['avg_score'] ?? 0).toDouble();
    final totalCorrect = _quizSummary['total_correct'] ?? 0;
    final totalQuestions = _quizSummary['total_questions'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 统计卡片
            Row(
              children: [
                Expanded(child: _buildStatCard('测验次数', '$totalCount', Icons.quiz, Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('平均分', avgScore.toStringAsFixed(1), Icons.trending_up, Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('正确率', totalQuestions > 0 ? '${((totalCorrect / totalQuestions) * 100).toStringAsFixed(1)}%' : '0%', Icons.check_circle, Colors.orange)),
              ],
            ),
            const SizedBox(height: 24),
            
            // 成绩趋势图
            if (_results.isNotEmpty) ...[
              const Text('成绩趋势', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(height: 200, child: _buildChart()),
              const SizedBox(height: 24),
            ],
            
            // 测验记录
            const Text('测验记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_results.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('暂无测验记录', style: TextStyle(color: Colors.grey))))
            else
              ..._results.take(10).map((result) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: result.score >= 60 ? Colors.green : Colors.red,
                    child: Text('${result.score}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(result.chapter ?? '综合测验'),
                  subtitle: Text('正确: ${result.numCorrect}/${result.numTotal}'),
                  trailing: Text(result.quizTimestamp?.substring(0, 10) ?? '', style: const TextStyle(color: Colors.grey)),
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildLearningTab() {
    final totalRecords = _learningStats['total_records'] ?? 0;
    final uniqueNodes = _learningStats['unique_nodes'] ?? 0;
    final thisWeek = _learningStats['this_week'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 学习统计
            Row(
              children: [
                Expanded(child: _buildStatCard('学习记录', '$totalRecords', Icons.book, Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('学习节点', '$uniqueNodes', Icons.account_tree, Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('本周学习', '$thisWeek', Icons.calendar_today, Colors.orange)),
              ],
            ),
            const SizedBox(height: 24),
            
            const Text('学习建议', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTip(Icons.schedule, '建议每天学习1-2小时'),
                    const SizedBox(height: 8),
                    _buildTip(Icons.folder, '先完成基础知识图谱学习'),
                    const SizedBox(height: 8),
                    _buildTip(Icons.quiz, '每章学完后做测验巩固'),
                    const SizedBox(height: 8),
                    _buildTip(Icons.repeat, '错题要反复练习'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final spots = _results.reversed.toList().asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.score.toDouble());
    }).toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: 100,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF667eea),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: const Color(0xFF667eea).withValues(alpha: 0.1)),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF667eea)),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
  }
}
