import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../services/auth_service.dart';
import '../../../services/twin_service.dart';
import '../../../services/agent/agent_registry.dart';
import '../../../data/models/twin_profile_model.dart';
import '../../widgets/agent_chat_overlay.dart';
import '../../widgets/markdown_bubble.dart';

/// 数字孪生仪表盘页面 — 数据驱动 + AI 解读
///
/// 首屏展示真实 DAO 聚合数据（雷达图/成长曲线/指标卡片），
/// AI 解读懒加载（点击才调用 LLM）。
class VirtualTwinPage extends StatefulWidget {
  const VirtualTwinPage({super.key});

  @override
  State<VirtualTwinPage> createState() => _VirtualTwinPageState();
}

class _VirtualTwinPageState extends State<VirtualTwinPage> {
  final _authService = AuthService();
  final _twinService = TwinService();

  bool get _isTeacher => _authService.isTeacher || _authService.isAdmin;
  String get _agentId => _isTeacher ? 'virtual_teacher' : 'virtual_student';

  StudentTwinProfile? _studentProfile;
  TeacherTwinProfile? _teacherProfile;
  bool _profileLoading = true;

  // AI 解读
  String _aiReply = '';
  bool _aiLoading = false;
  bool _aiExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _profileLoading = true);
    try {
      final userId = _authService.currentUser?.userId ?? '';
      if (_isTeacher) {
        _teacherProfile = await _twinService.buildTeacherProfile(userId);
      } else {
        _studentProfile = await _twinService.buildStudentProfile(userId);
      }
    } catch (_) {}
    if (mounted) setState(() => _profileLoading = false);
  }

  Future<void> _loadAiInsight() async {
    if (_aiLoading) return;
    setState(() {
      _aiLoading = true;
      _aiExpanded = true;
    });
    try {
      final registry = AgentRegistry.instance;
      if (!registry.isInitialized) registry.initialize();
      final agent = registry.getAgent(_agentId);
      if (agent != null) {
        final result = await agent.handleMessage(
          _isTeacher ? '教学仪表盘' : '查看我的状态',
          registry.session,
        );
        _aiReply = result.content;
      }
    } catch (e) {
      _aiReply = '加载失败：$e';
    }
    if (mounted) setState(() => _aiLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isTeacher ? '虚拟教师' : '虚拟学生'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: '对话',
            onPressed: () =>
                AgentChatOverlay.show(context, agentId: _agentId),
          ),
        ],
      ),
      body: _profileLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Hero Header
                    _buildHeader(isDark),
                    const SizedBox(height: 16),
                    // 指标卡片
                    _buildStatCards(),
                    const SizedBox(height: 16),
                    // 雷达图
                    _buildRadarSection(isDark),
                    const SizedBox(height: 16),
                    // 成长曲线
                    if (!_isTeacher) ...[
                      _buildGrowthCurve(isDark),
                      const SizedBox(height: 16),
                    ],
                    // 教师：薄弱节点
                    if (_isTeacher && (_teacherProfile?.weakSpots.isNotEmpty ?? false)) ...[
                      _buildWeakSpots(),
                      const SizedBox(height: 16),
                    ],
                    // AI 解读（折叠）
                    _buildAiSection(isDark),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final level = _isTeacher ? '教学导师' : (_studentProfile?.level ?? '入门');
    final Color levelColor;
    switch (level) {
      case '精通':
        levelColor = Colors.amber;
      case '熟练':
        levelColor = Colors.green;
      case '进阶':
        levelColor = Colors.blue;
      default:
        levelColor = Colors.grey;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              _isTeacher ? '👩‍🏫' : '🧑‍🎓',
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _authService.currentUser?.realName ?? _authService.currentUser?.userId ?? '',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              level,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards() {
    if (_isTeacher) {
      final p = _teacherProfile ?? TeacherTwinProfile.empty();
      return Row(
        children: [
          _statCard('班级人数', '${p.classSize}', Icons.people, Colors.blue),
          _statCard('班级均分', p.classAvg.toStringAsFixed(1), Icons.bar_chart, Colors.green),
          _statCard('待批阅', '${p.pendingGrading}', Icons.assignment_late, Colors.red),
          _statCard('覆盖节点', '${p.nodeCoverage.length}', Icons.account_tree, Colors.orange),
        ],
      );
    }

    final p = _studentProfile ?? StudentTwinProfile.empty();
    return Row(
      children: [
        _statCard('测验均分', p.quizAvg.toStringAsFixed(1), Icons.quiz, Colors.blue),
        _statCard('实验完成', '${p.labCompletionRate.toStringAsFixed(0)}%', Icons.science, Colors.green),
        _statCard('错题消化', '${p.wrongDigestRate.toStringAsFixed(0)}%', Icons.auto_fix_high, Colors.orange),
        _statCard('节点覆盖', '${p.conceptCoverage.toStringAsFixed(0)}%', Icons.account_tree, Colors.purple),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadarSection(bool isDark) {
    Map<String, double> radar;
    if (_isTeacher) {
      // 教师用全班维度
      final p = _teacherProfile ?? TeacherTwinProfile.empty();
      radar = {
        '班级人数': (p.classSize / 50 * 100).clamp(0, 100),
        '班级均分': p.classAvg.clamp(0, 100),
        '待批阅': ((1 - p.pendingGrading / 20) * 100).clamp(0, 100),
        '节点覆盖': (p.nodeCoverage.length / 50 * 100).clamp(0, 100),
        '薄弱管控': p.weakSpots.isEmpty ? 100 : ((1 - p.weakSpots.length / 10) * 100).clamp(0, 100),
      };
    } else {
      radar = (_studentProfile?.radar ?? {});
      if (radar.isEmpty) {
        radar = {'基础知识': 0, '实践能力': 0, '创新思维': 0, '学习韧性': 0, '学习速度': 0};
      }
    }

    final labels = radar.keys.toList();
    final values = radar.values.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('能力雷达',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  dataSets: [
                    RadarDataSet(
                      dataEntries: values
                          .map((v) => RadarEntry(value: v.clamp(0, 100)))
                          .toList(),
                      fillColor: const Color(0xFF667eea).withValues(alpha: 0.2),
                      borderColor: const Color(0xFF667eea),
                      borderWidth: 2,
                    ),
                  ],
                  getTitle: (index, angle) => RadarChartTitle(
                    text: labels[index % labels.length],
                    angle: 0,
                  ),
                  titleTextStyle: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black54),
                  tickCount: 4,
                  ticksTextStyle: const TextStyle(fontSize: 0),
                  tickBorderData: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  gridBorderData: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  radarBorderData:
                      BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrowthCurve(bool isDark) {
    final weekly = _studentProfile?.weeklyMinutes ?? [];
    if (weekly.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('暂无学习时长数据',
              style: TextStyle(color: Colors.grey[500])),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('成长曲线（近 8 周学习时长/分钟）',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: isDark ? Colors.white10 : Colors.black12,
                      strokeWidth: 1,
                    ),
                    drawVerticalLine: false,
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => Text(
                          'W${value.toInt() + 1}',
                          style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: weekly
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      color: const Color(0xFF667eea),
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF667eea).withValues(alpha: 0.1),
                      ),
                      dotData: const FlDotData(show: true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeakSpots() {
    final spots = _teacherProfile?.weakSpots ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('薄弱节点 Top 5',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...spots.map((s) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: s.avgScore >= 60
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2),
                    child: Text(
                      s.avgScore.toStringAsFixed(0),
                      style: TextStyle(
                          fontSize: 11,
                          color: s.avgScore >= 60 ? Colors.orange : Colors.red,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(s.nodeTitle, style: const TextStyle(fontSize: 13)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildAiSection(bool isDark) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.lightbulb_outline, color: Color(0xFF667eea)),
            title: const Text('AI 解读', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Icon(_aiExpanded
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down),
            onTap: () {
              if (!_aiExpanded && _aiReply.isEmpty) {
                _loadAiInsight();
              } else {
                setState(() => _aiExpanded = !_aiExpanded);
              }
            },
          ),
          if (_aiExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _aiLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _aiReply.isEmpty
                      ? Text('点击展开获取 AI 解读',
                          style: TextStyle(color: Colors.grey[500]))
                      : MarkdownBubble(content: _aiReply, compact: true),
            ),
        ],
      ),
    );
  }
}
