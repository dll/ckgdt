import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/local/survey_dao.dart';

/// 问卷统计报告页面 — 管理员查看问卷回收数据与可视化分析
class SurveyStatsPage extends StatefulWidget {
  final int surveyId;

  const SurveyStatsPage({super.key, required this.surveyId});

  @override
  State<SurveyStatsPage> createState() => _SurveyStatsPageState();
}

class _SurveyStatsPageState extends State<SurveyStatsPage> {
  final _surveyDao = SurveyDao();

  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      final stats = await _surveyDao.getSurveyStats(widget.surveyId);
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = '加载失败: $e';
        });
      }
    }
  }

  Future<void> _copyReport() async {
    try {
      final report = await _surveyDao.generateReport(widget.surveyId);
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('统计报告已复制到剪贴板'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成报告失败: $e')),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('问卷统计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: '复制报告',
            onPressed: _copyReport,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 56, color: Colors.red[300]),
                      const SizedBox(height: 12),
                      Text(_errorMsg!,
                          style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadStats,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: _buildBody(primary),
                ),
    );
  }

  Widget _buildBody(Color primary) {
    final survey = _stats!['survey'] as Map<String, dynamic>?;
    final totalQuestions = (_stats!['total_questions'] as int?) ?? 0;
    final totalResponses = (_stats!['total_responses'] as int?) ?? 0;
    final questionStats =
        _stats!['question_stats'] as List<Map<String, dynamic>>? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 问卷概览卡片 ──────────────────────────────────────────────
        _buildOverviewCard(survey, totalQuestions, totalResponses, primary),
        const SizedBox(height: 16),

        // ── 回收率指标 ──────────────────────────────────────────────
        _buildResponseRateCard(totalResponses, primary),
        const SizedBox(height: 20),

        // ── 各题统计 ──────────────────────────────────────────────
        if (questionStats.isEmpty)
          _buildEmptyState()
        else
          ...List.generate(questionStats.length, (i) {
            final qs = questionStats[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildQuestionStatCard(qs, i + 1, primary),
            );
          }),

        const SizedBox(height: 24),

        // ── 导出按钮 ──────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _copyReport,
            icon: const Icon(Icons.description_outlined),
            label: const Text('生成文本报告并复制'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 问卷概览卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOverviewCard(Map<String, dynamic>? survey, int totalQuestions,
      int totalResponses, Color primary) {
    final title = survey?['title'] ?? '未知问卷';
    final description = survey?['description'] ?? '';
    final status = survey?['status'] ?? 'draft';
    final createdAt = survey?['created_at'] ?? '';
    final deadline = survey?['deadline'] ?? '';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'published':
        statusColor = Colors.green;
        statusLabel = '进行中';
        break;
      case 'closed':
        statusColor = Colors.red;
        statusLabel = '已关闭';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = '草稿';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.assignment, color: primary, size: 28),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                _miniStat(Icons.quiz_outlined, '题目数', '$totalQuestions',
                    Colors.blue),
                const SizedBox(width: 16),
                _miniStat(Icons.people_outline, '回收数', '$totalResponses',
                    Colors.orange),
                const SizedBox(width: 16),
                _miniStat(
                  Icons.calendar_today,
                  '创建时间',
                  _formatDate(createdAt),
                  Colors.teal,
                ),
              ],
            ),
            if (deadline.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    '截止时间: $deadline',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 回收率卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildResponseRateCard(int totalResponses, Color primary) {
    // 回收率基于估算总人数（如有班级关联可精确）
    // 此处简单展示回收数及趋势指标
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.trending_up, color: primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '回收情况',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '已回收 $totalResponses 份问卷',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: totalResponses > 0
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                totalResponses > 0 ? '有效' : '待回收',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: totalResponses > 0 ? Colors.green : Colors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 各题统计卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildQuestionStatCard(
      Map<String, dynamic> qs, int index, Color primary) {
    final question = qs['question'] as String? ?? '';
    final type = qs['type'] as String? ?? 'text';

    String typeLabel;
    IconData typeIcon;
    Color typeColor;
    switch (type) {
      case 'single_choice':
        typeLabel = '单选题';
        typeIcon = Icons.radio_button_checked;
        typeColor = Colors.blue;
        break;
      case 'multi_choice':
        typeLabel = '多选题';
        typeIcon = Icons.check_box;
        typeColor = Colors.indigo;
        break;
      case 'rating':
        typeLabel = '评分题';
        typeIcon = Icons.star;
        typeColor = Colors.amber;
        break;
      default:
        typeLabel = '文本题';
        typeIcon = Icons.text_fields;
        typeColor = Colors.teal;
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 题目标题行
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: primary.withValues(alpha: 0.1),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(typeIcon, size: 12, color: typeColor),
                            const SizedBox(width: 4),
                            Text(
                              typeLabel,
                              style:
                                  TextStyle(fontSize: 11, color: typeColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 按题型渲染统计内容
            if (type == 'single_choice' || type == 'multi_choice')
              _buildChoiceStats(qs, primary)
            else if (type == 'rating')
              _buildRatingStats(qs)
            else
              _buildTextStats(qs),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 选择题统计 — 水平条形图
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChoiceStats(Map<String, dynamic> qs, Color primary) {
    final counts = qs['counts'] as Map<String, int>? ?? {};
    final total = (qs['total'] as int?) ?? 0;

    if (counts.isEmpty) {
      return _buildNoDataHint();
    }

    // 找到最大值用于比例计算
    final maxCount =
        counts.values.isNotEmpty ? counts.values.reduce((a, b) => a > b ? a : b) : 1;

    final barColors = [
      const Color(0xFF667eea),
      const Color(0xFF764ba2),
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
      Colors.indigo,
    ];

    return Column(
      children: [
        ...counts.entries.toList().asMap().entries.map((mapEntry) {
          final idx = mapEntry.key;
          final entry = mapEntry.value;
          final count = entry.value;
          final percentage = total > 0 ? (count / total * 100) : 0.0;
          final ratio = maxCount > 0 ? count / maxCount : 0.0;
          final barColor = barColors[idx % barColors.length];

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 选项文本 + 数据
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$count 人 (${percentage.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 水平条形图
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: ratio.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  barColor,
                                  barColor.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '共 $total 人作答',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 评分题统计 — 星级分布 + 均分
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRatingStats(Map<String, dynamic> qs) {
    final average = (qs['average'] as num?)?.toDouble() ?? 0.0;
    final distribution = qs['distribution'] as Map<int, int>? ?? {};
    final total = (qs['total'] as int?) ?? 0;

    final maxCount = distribution.values.isNotEmpty
        ? distribution.values.reduce((a, b) => a > b ? a : b)
        : 1;

    return Column(
      children: [
        // 平均分显示
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                average.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(5, (i) {
                      return Icon(
                        i < average.round()
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color: Colors.amber,
                      );
                    }),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '满分 5.0，共 $total 人评分',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 星级分布
        ...List.generate(5, (i) {
          final star = 5 - i;
          final count = distribution[star] ?? 0;
          final ratio = maxCount > 0 ? count / maxCount : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                // 星级标签
                SizedBox(
                  width: 60,
                  child: Row(
                    children: [
                      Text('$star', style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 2),
                      const Icon(Icons.star_rounded,
                          size: 14, color: Colors.amber),
                    ],
                  ),
                ),
                // 条形图
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ratio.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$count 人',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 文本题统计 — 回答列表
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTextStats(Map<String, dynamic> qs) {
    final answers = qs['answers'] as List<String>? ?? [];
    final total = (qs['total'] as int?) ?? 0;
    final answerRate = total > 0 ? (answers.length / total * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 回答率
        Row(
          children: [
            Icon(Icons.comment_outlined, size: 16, color: Colors.teal[400]),
            const SizedBox(width: 6),
            Text(
              '收到 ${answers.length} 条文本回答 (${answerRate.toStringAsFixed(0)}%)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (answers.isEmpty)
          _buildNoDataHint()
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: answers.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: Colors.grey[200],
              ),
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.teal.withValues(alpha: 0.1),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        answers[i],
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 辅助 Widget
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('暂无统计数据', style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 4),
            Text(
              '问卷可能尚未添加题目或回收回答',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 6),
          Text('暂无作答数据', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '未知';
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return isoDate.length > 10 ? isoDate.substring(0, 10) : isoDate;
    }
  }
}
