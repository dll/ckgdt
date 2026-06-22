import 'package:flutter/material.dart';

import '../../../core/design/noir_tokens.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/ordinary_score_dao.dart';
import '../../../services/auth_service.dart';

class StudentOrdinaryScoreTab extends StatefulWidget {
  const StudentOrdinaryScoreTab({super.key});

  @override
  State<StudentOrdinaryScoreTab> createState() =>
      _StudentOrdinaryScoreTabState();
}

class _StudentOrdinaryScoreTabState extends State<StudentOrdinaryScoreTab> {
  final _ordinaryDao = OrdinaryScoreDao();
  final _authService = AuthService();

  OrdinaryScoreSnapshot? _snapshot;
  OrdinaryStudentScore? _score;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await _ordinaryDao.loadSnapshot();
      final userId = _authService.getCurrentUserId();
      OrdinaryStudentScore? score;
      if (userId != null) {
        for (final row in snapshot.rows) {
          if (row.studentId == userId) {
            score = row;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _score = score;
        _loading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'StudentOrdinaryScoreTab.loadData', stack: st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _snapshot == null) {
      return const Center(
        child: CircularProgressIndicator(color: NoirTokens.accent),
      );
    }
    if (_error != null && _snapshot == null) {
      return Center(
        child: _emptyState(Icons.error_outline, '成绩加载失败', _error!),
      );
    }

    final snapshot = _snapshot;
    final settings = snapshot?.settings ??
        OrdinaryScoreSettings.defaults(snapshot?.courseId ?? 'mad');
    final score = _score;
    final metrics = score?.metrics;
    final user = _authService.currentUser;
    final displayName = user?.realName?.trim().isNotEmpty == true
        ? user!.realName!
        : user?.userId ?? '当前学生';

    return RefreshIndicator(
      onRefresh: _loadData,
      color: NoirTokens.accent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _panel(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: NoirTokens.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fact_check_outlined,
                      color: NoirTokens.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('我的平时成绩',
                          style: NoirTokens.title(color: NoirTokens.paper)),
                      const SizedBox(height: 4),
                      Text(
                        '$displayName · ${snapshot?.courseName ?? '当前课程'}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: NoirTokens.paper.withValues(alpha: 0.56),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_fmt(score?.totalScore ?? 0)}/100',
                  style: const TextStyle(
                    color: NoirTokens.accent,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (score == null) ...[
            const SizedBox(height: 12),
            _panel(
              child: _emptyState(
                Icons.person_search_outlined,
                '暂无你的平时成绩记录',
                '系统会根据课堂积分、测验结果、课件学习和 AI 自主学习实时汇总。',
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final itemWidth = width >= 880
                  ? (width - 24) / 3
                  : width >= 560
                      ? (width - 12) / 2
                      : width;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _scoreCard(
                    width: itemWidth,
                    icon: Icons.record_voice_over_outlined,
                    label: '课堂表现',
                    score: score?.classroomScore ?? 0,
                    full: settings.classroomWeight,
                    percent: score?.classroomPercent ?? 0,
                    caption:
                        '课堂积分 ${_fmt(metrics?.earnedClassroomPoints ?? 0)} 分 · 回答 ${metrics?.answerCount ?? 0} 次',
                  ),
                  _scoreCard(
                    width: itemWidth,
                    icon: Icons.quiz_outlined,
                    label: '期间测验',
                    score: score?.quizScore ?? 0,
                    full: settings.quizWeight,
                    percent: score?.quizPercent ?? 0,
                    caption:
                        '测验 ${metrics?.quizAttempts ?? 0} 次 · 均分 ${_fmt(metrics?.quizAverage ?? 0)}',
                  ),
                  _scoreCard(
                    width: itemWidth,
                    icon: Icons.self_improvement_outlined,
                    label: '课外学习',
                    score: score?.extraScore ?? 0,
                    full: settings.extraWeight,
                    percent: score?.extraPercent ?? 0,
                    caption:
                        '课件 ${metrics?.coursewareRecords ?? 0} 条 · AI ${metrics?.aiRequests ?? 0} 次',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _buildDetailPanel(score),
        ],
      ),
    );
  }

  Widget _scoreCard({
    required double width,
    required IconData icon,
    required String label,
    required double score,
    required double full,
    required double percent,
    required String caption,
  }) {
    final ratio = full > 0 ? (score / full).clamp(0.0, 1.0).toDouble() : 0.0;
    return SizedBox(
      width: width,
      child: _panel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: NoirTokens.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: NoirTokens.paper,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_fmt(score)}/${_fmt(full)}',
                  style: const TextStyle(
                    color: NoirTokens.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: NoirTokens.paper.withValues(alpha: 0.10),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(NoirTokens.accent),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_fmt(percent)}% · $caption',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: NoirTokens.paper.withValues(alpha: 0.52),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel(OrdinaryStudentScore? score) {
    final m = score?.metrics;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dataset_outlined,
                  color: NoirTokens.accent, size: 20),
              const SizedBox(width: 8),
              Text('数据来源', style: NoirTokens.title(color: NoirTokens.paper)),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow('课堂表现',
              '课堂积分 ${_fmt(m?.earnedClassroomPoints ?? 0)} 分，点名 ${m?.rollCallCount ?? 0} 次，正确 ${m?.rollCallCorrectCount ?? 0} 次，签到 ${m?.checkinCount ?? 0} 次'),
          _detailRow('期间测验',
              '已完成 ${m?.quizAttempts ?? 0} 次，平均 ${_fmt(m?.quizAverage ?? 0)} 分，最高 ${_fmt(m?.quizBest ?? 0)} 分'),
          _detailRow('课外学习',
              '课件 ${m?.coursewareRecords ?? 0} 条/${_fmt(m?.coursewareMinutes ?? 0)} 分钟，扩展 ${m?.extendedRecords ?? 0} 条，推荐 ${((m?.recommendRecords ?? 0) + (m?.recommendFavorites ?? 0))} 条，AI ${m?.aiRequests ?? 0} 次'),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: NoirTokens.accent,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: NoirTokens.paper.withValues(alpha: 0.72),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: NoirTokens.paper.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NoirTokens.paper.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: NoirTokens.paper.withValues(alpha: 0.45), size: 42),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(
                color: NoirTokens.paper,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NoirTokens.paper.withValues(alpha: 0.52),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(num value) {
    final v = value.toDouble();
    if ((v - v.round()).abs() < 0.05) return v.round().toString();
    return v.toStringAsFixed(1);
  }
}
