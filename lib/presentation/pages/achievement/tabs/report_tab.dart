import 'dart:io';
import 'dart:math';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../data/local/achievement_dao.dart';
import '../../../../services/achievement/achievement_docx_service.dart';
import '../../../../services/achievement/achievement_template_excel_service.dart';
import '../../../../services/achievement/excel_chart_injector.dart';
import '../../../../services/archive/native_docx_service.dart';
import '../../../../services/output_path_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../core/error_handler.dart';
import '../../../widgets/markdown_bubble.dart';
import '../achievement_shared.dart';
import '../achievement_config.dart';

class ReportTab extends StatefulWidget {
  final AuthService authService;
  final AchievementDao achievementDao;

  const ReportTab({
    super.key,
    required this.authService,
    required this.achievementDao,
  });

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  List<Map<String, dynamic>> _batches = [];
  int? _selectedBatchId;
  bool _loadingBatches = true;
  bool _calculating = false;
  bool _generatingReport = false;

  // 计算结果
  Map<String, dynamic>? _calcResults;
  List<double> _objectiveAchievements = [0, 0, 0, 0];
  List<double> _objectiveWeights = List<double>.from(kDefaultWeights);
  double _weightedAchievement = 0.0;
  Map<String, List<double>> _statistics =
      {}; // objectiveKey -> [mean, max, min, std]
  Map<String, dynamic>? _surveySummary;
  // 课程目标配置：优先取大纲导入的 course_objectives，回退默认。
  AchievementConfig _config = AchievementConfig.defaults;

  List<int> _activeObjectiveIndexesFor(
    AchievementConfig config, [
    List<double>? weights,
  ]) {
    final resolvedWeights = weights ?? _objectiveWeights;
    final indexes = [
      for (var i = 0; i < 4; i++)
        if ((i < resolvedWeights.length && resolvedWeights[i] > 0) ||
            (i < config.fullMarks.length && config.fullMarks[i] > 0))
          i
    ];
    return indexes.isEmpty ? [0, 1, 2, 3] : indexes;
  }

  List<int> get _activeObjectiveIndexes => _activeObjectiveIndexesFor(_config);

  @override
  void initState() {
    super.initState();
    _loadBatches();
    _loadConfig();
  }

  Future<void> _loadConfig([String? courseName]) async {
    try {
      final rows = await widget.achievementDao
          .getCourseObjectives(courseName ?? '移动应用开发');
      if (mounted && rows.isNotEmpty) {
        setState(() => _config = AchievementConfig.fromObjectiveRows(rows));
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ReportTab.loadConfig', stack: st);
    }
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await widget.achievementDao.getBatches();
      if (mounted) {
        setState(() {
          _batches = batches;
          _loadingBatches = false;
          if (_batches.isNotEmpty && _selectedBatchId == null) {
            _selectedBatchId = _batches.first['id'] as int;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  Future<void> _calculateAchievement() async {
    if (_selectedBatchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择批次')),
      );
      return;
    }

    setState(() {
      _calculating = true;
      _calcResults = null;
    });

    try {
      // 获取该批次所有成绩
      final scores =
          await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      if (scores.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('该批次无成绩数据，请先录入成绩'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _calculating = false);
        }
        return;
      }

      // 计算每个目标的达成度（满分：目标1=15, 目标2=25, 目标3=30, 目标4=30）
      final objScores = List<List<double>>.generate(4, (i) {
        return scores.map<double>((s) {
          return (s['obj${i + 1}_score'] ?? 0).toDouble();
        }).toList();
      });

      // 使用与 DAO addScore() 一致的满分比计算达成度（满分取大纲/SSOT 配置）
      final fullMarks = _config.fullMarks;
      final objAchievements = List<double>.generate(4, (i) {
        final values = objScores[i];
        final mean = values.reduce((a, b) => a + b) / values.length;
        final fullMark = i < fullMarks.length ? fullMarks[i] : 0.0;
        return fullMark > 0 ? (mean / fullMark).clamp(0.0, 1.0) : 0.0;
      });

      // 加权达成度（权重优先取大纲导入的 course_objectives，回退默认）
      final objWeights = await widget.achievementDao
          .resolveObjectiveWeights(_selectedBatchId!);
      double weighted = 0;
      for (int i = 0; i < 4; i++) {
        weighted += objAchievements[i] * objWeights[i];
      }

      // 统计数据：mean, max, min, std
      final stats = <String, List<double>>{};
      for (int i = 0; i < 4; i++) {
        final List<double> values = objScores[i];
        final mean = values.reduce((a, b) => a + b) / values.length;
        final maxVal = values.reduce(max<double>);
        final minVal = values.reduce(min<double>);
        final variance =
            values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
                values.length;
        final std = sqrt(variance);
        stats['objective${i + 1}'] = [mean, maxVal, minVal, std];
      }

      // 保存计算结果到数据库（容错：calc_results_json 列可能不存在于旧 DB）
      try {
        await widget.achievementDao.saveCalculationResults(
          batchId: _selectedBatchId!,
          objective1Achievement: objAchievements[0],
          objective2Achievement: objAchievements[1],
          objective3Achievement: objAchievements[2],
          objective4Achievement: objAchievements[3],
          weightedAchievement: weighted,
        );
      } catch (e) {
        // 旧数据库可能缺少 calc_results_json 列，忽略保存失败
        swallow(e, tag: 'ReportTab.saveCalcResults');
      }

      // 同时更新批次状态
      await widget.achievementDao
          .updateBatchStatus(_selectedBatchId!, 'completed');

      // 加载问卷满意度数据
      Map<String, dynamic>? surveyData;
      try {
        surveyData = await widget.achievementDao.getSurveySatisfactionSummary();
      } catch (e, st) {
        swallowDebug(e, tag: 'ReportTab.surveySatisfaction', stack: st);
      }

      if (mounted) {
        setState(() {
          _objectiveAchievements = objAchievements;
          _objectiveWeights = objWeights;
          _weightedAchievement = weighted;
          _statistics = stats;
          _surveySummary = surveyData;
          _calcResults = {
            'student_count': scores.length,
            'batch_name': _batches.firstWhere(
              (b) => b['id'] == _selectedBatchId,
              orElse: () => {'batch_name': ''},
            )['batch_name'],
          };
          _calculating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('计算失败：$e'), backgroundColor: Colors.red),
        );
        setState(() => _calculating = false);
      }
    }
  }

  Future<void> _generateMarkdownReport() async {
    if (_calcResults == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先生成报告')),
      );
      return;
    }

    setState(() => _generatingReport = true);

    try {
      final batch = _batches.firstWhere(
        (b) => b['id'] == _selectedBatchId,
        orElse: () => <String, dynamic>{},
      );

      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final courseName = batch['course_name'] ?? '移动应用开发';
      final className = batch['class_name'] ?? '软件23';
      final semester = batch['semester'] ?? '-';
      final teacherId = batch['teacher_id'] ?? '';

      // 获取三类评价分项达成度（班级平均）
      final combined = await widget.achievementDao
          .calculateCombinedAchievement(_selectedBatchId!);
      final pingshiAvg = combined['pingshi'] as Map<String, double>;
      final experimentAvg = combined['experiment'] as Map<String, double>;
      final examAvg = combined['exam'] as Map<String, double>;
      final combinedAvg = combined['combined'] as Map<String, double>;

      // 获取学生个体成绩
      final scores =
          await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      final studentCount = scores.length;

      final buffer = StringBuffer();
      final cfg = _config;
      final objDescFull = cfg.descriptions;
      final objIndicators = cfg.indicators;
      final objAssessContent = cfg.assessContents;
      final objMarks = cfg.fullMarks.map((m) => m.toInt()).toList();
      final activeObjectiveIndexes = _activeObjectiveIndexesFor(cfg);
      final rawEnvWeights =
          (combined['weightsByObjective'] as List?) ?? const [];
      Map<String, double> envWeightAt(int index) {
        if (index >= 0 && index < rawEnvWeights.length) {
          final raw = rawEnvWeights[index] as Map?;
          return {
            'pingshi': (raw?['pingshi'] as num?)?.toDouble() ?? 0,
            'experiment': (raw?['experiment'] as num?)?.toDouble() ?? 0,
            'exam': (raw?['exam'] as num?)?.toDouble() ?? 0,
          };
        }
        return {'pingshi': 0.20, 'experiment': 0.30, 'exam': 0.50};
      }

      List<(String, String, double)> envDefsFor(int index) {
        final w = envWeightAt(index);
        return [
          ('平时成绩', 'pingshi', w['pingshi'] ?? 0),
          ('实验成绩', 'experiment', w['experiment'] ?? 0),
          ('考核成绩', 'exam', w['exam'] ?? 0),
        ].where((e) => e.$3 > 0).toList();
      }

      final activeEnvKeys = [
        for (final env in ['pingshi', 'experiment', 'exam'])
          if (activeObjectiveIndexes.any((i) => (envWeightAt(i)[env] ?? 0) > 0))
            env
      ];
      final envLabel = {
        'pingshi': '平时成绩',
        'experiment': '实验成绩',
        'exam': '考核成绩',
      };

      String ratioCell(int index, String key) {
        final w = envWeightAt(index)[key] ?? 0;
        if (w <= 0) return '—';
        return '${objMarks[index]}（${(w * 100).toStringAsFixed(0)}%）';
      }

      buffer.writeln('# $semester《$courseName》课程目标达成评价报告');
      buffer.writeln();

      // ══════════════════════════════════════════════════
      // 一、基本信息（对齐 DOCX 表0 + 表1）
      // ══════════════════════════════════════════════════
      buffer.writeln('## 一、基本信息');
      buffer.writeln();
      buffer.writeln('### 1. 课程基本信息');
      buffer.writeln();
      buffer.writeln('| 项目 | 内容 | 项目 | 内容 |');
      buffer.writeln('|------|------|------|------|');
      buffer.writeln('| 课程名称 | $courseName | 授课班级 | $className |');
      if (teacherId.isNotEmpty) {
        buffer.writeln('| 授课教师 | $teacherId | 学生人数 | $studentCount |');
      } else {
        buffer.writeln('| 学生人数 | $studentCount | 评价日期 | $dateStr |');
      }
      buffer.writeln('| 课程性质 | 考查（大作业） | 评价方式 | 定量+定性 |');
      buffer.writeln('| 开课学期 | $semester | 达成度预期阈值 | 0.60 |');
      buffer.writeln();

      buffer.writeln('### 2. 课程支撑毕业要求与课程目标对应关系');
      buffer.writeln();
      buffer.writeln('| 毕业要求指标点 | 课程目标 | 权重 | 课程目标描述 |');
      buffer.writeln('|---------------|---------|------|------------|');
      for (final i in activeObjectiveIndexes) {
        buffer.writeln(
            '| 指标点${objIndicators[i]} | ${kObjectiveNames[i]} | ${_objectiveWeights[i].toStringAsFixed(2)} | ${objDescFull[i]} |');
      }
      buffer.writeln();

      buffer.writeln('### 3. 评价方式及成绩评定对照表');
      buffer.writeln();
      buffer.writeln(
          '| 课程目标 | 权重 | 支撑指标点 | ${activeEnvKeys.map((e) => envLabel[e]).join(' | ')} |');
      buffer.writeln(
          '|----------|------|-----------|${activeEnvKeys.map((_) => '-----------------').join('|')}|');
      for (final i in activeObjectiveIndexes) {
        buffer.writeln(
            '| ${kObjectiveNames[i]} | ${_objectiveWeights[i].toStringAsFixed(2)} | 指标点${objIndicators[i]} | ${activeEnvKeys.map((env) => ratioCell(i, env)).join(' | ')} |');
      }
      buffer.writeln();

      // ══════════════════════════════════════════════════
      // 二、课程考核标准（对齐 DOCX 表2 + 表3 + 表4）
      // ══════════════════════════════════════════════════
      buffer.writeln('## 二、课程考核标准');
      buffer.writeln();

      if (activeObjectiveIndexes
          .any((i) => (envWeightAt(i)['pingshi'] ?? 0) > 0)) {
        buffer.writeln('### 1. 平时成绩评价标准');
        buffer.writeln();
        buffer.writeln(
            '| 课程目标 | 考核内容 | 优秀（90-100%） | 良好（70-89%） | 合格（60-69%） | 不合格（0-59%） |');
        buffer.writeln(
            '|----------|---------|----------------|---------------|---------------|----------------|');
        for (final i in activeObjectiveIndexes) {
          if ((envWeightAt(i)['pingshi'] ?? 0) <= 0) continue;
          final content = objAssessContent[i].split('、').first;
          buffer.writeln(
              '| ${kObjectiveNames[i]} | $content | 全面掌握，表现突出 | 较好掌握，表现良好 | 基本掌握，表现一般 | 未能掌握，需要改进 |');
        }
        buffer.writeln();
      }

      if (activeObjectiveIndexes
          .any((i) => (envWeightAt(i)['experiment'] ?? 0) > 0)) {
        buffer.writeln('### 2. 实验成绩评价标准');
        buffer.writeln();
        buffer.writeln(
            '| 课程目标 | 考核内容 | 优秀（90-100%） | 良好（70-89%） | 合格（60-69%） | 不合格（0-59%） |');
        buffer.writeln(
            '|----------|---------|----------------|---------------|---------------|----------------|');
        for (final i in activeObjectiveIndexes) {
          if ((envWeightAt(i)['experiment'] ?? 0) <= 0) continue;
          final parts = objAssessContent[i].split('、');
          final expItem = parts.length > 1 ? parts[1] : parts[0];
          buffer.writeln(
              '| ${kObjectiveNames[i]} | $expItem | 独立完成，结果正确 | 基本完成，结果较好 | 能够完成，有少量错误 | 无法完成或错误较多 |');
        }
        buffer.writeln();
      }

      buffer.writeln('### 3. 考核评价内容');
      buffer.writeln();
      buffer.writeln('| 课程目标 | 考核内容 | 分值 |');
      buffer.writeln('|----------|---------|------|');
      for (final i in activeObjectiveIndexes) {
        if ((envWeightAt(i)['exam'] ?? 0) <= 0) continue;
        final examContent = objAssessContent[i].split('、').last;
        buffer.writeln(
            '| ${kObjectiveNames[i]} | $examContent | ${objMarks[i]} |');
      }
      buffer.writeln();

      // ══════════════════════════════════════════════════
      // 三、达成度计算（对齐 DOCX 表5）
      // ══════════════════════════════════════════════════
      buffer.writeln('## 三、达成度计算（定量评价）');
      buffer.writeln();
      buffer.writeln('> 计算公式：达成度 = 班级平均分 ÷ 满分；课程目标达成度 = Σ(达成度 × 环节权重)');
      buffer.writeln();

      buffer.writeln('### 1. 课程目标达成度计算');
      buffer.writeln();
      buffer.writeln(
          '| 课程目标 | 权重 | 评价环节 | 满分 | 班级平均分 | 达成度 | 环节权重 | 课程目标达成度 | 支撑指标点 | 指标点达成度 |');
      buffer.writeln(
          '|----------|------|---------|------|-----------|--------|---------|--------------|-----------|------------|');

      final assessMapByKey = {
        'pingshi': pingshiAvg,
        'experiment': experimentAvg,
        'exam': examAvg,
      };
      for (final i in activeObjectiveIndexes) {
        final objCombined = combinedAvg['obj${i + 1}'] ?? 0;
        final envDefs = envDefsFor(i);
        for (int j = 0; j < envDefs.length; j++) {
          final isFirstRow = j == 0;
          final (envName, envKey, envWeight) = envDefs[j];
          final ach = assessMapByKey[envKey]?['obj${i + 1}'] ?? 0.0;
          final avgScore = ach * objMarks[i];
          buffer.writeln(
              '| ${isFirstRow ? kObjectiveNames[i] : ''} | ${isFirstRow ? _objectiveWeights[i].toStringAsFixed(2) : ''} | $envName | ${objMarks[i]} | ${avgScore.toStringAsFixed(2)} | ${ach.toStringAsFixed(4)} | ${envWeight.toStringAsFixed(2)} | ${isFirstRow ? objCombined.toStringAsFixed(4) : ''} | ${isFirstRow ? '指标点${objIndicators[i]}' : ''} | ${isFirstRow ? objCombined.toStringAsFixed(4) : ''} |');
        }
      }
      buffer.writeln();

      // 达成度汇总
      buffer.writeln('| 项目 | 达成度 | 预期阈值 | 是否达成 |');
      buffer.writeln('|------|--------|---------|---------|');
      for (final i in activeObjectiveIndexes) {
        final a = _objectiveAchievements[i];
        buffer.writeln(
            '| ${kObjectiveNames[i]}（权重${(_objectiveWeights[i] * 100).toStringAsFixed(0)}%） | ${a.toStringAsFixed(4)} | 0.60 | ${a >= 0.60 ? '达成' : '未达成'} |');
      }
      buffer.writeln(
          '| **课程总体达成度** | **${_weightedAchievement.toStringAsFixed(4)}** | **0.60** | **${_weightedAchievement >= 0.60 ? '达成' : '未达成'}** |');
      buffer.writeln();

      // 成绩统计
      buffer.writeln('### 2. 成绩统计');
      buffer.writeln();
      buffer.writeln(
          '| 统计指标 | ${activeObjectiveIndexes.map((i) => '目标${i + 1}').join(' | ')} |');
      buffer.writeln(
          '|----------|${activeObjectiveIndexes.map((_) => '-------').join('|')}|');
      for (int idx = 0; idx < 4; idx++) {
        final label = ['平均分', '最高分', '最低分', '标准差'][idx];
        buffer.write('| $label ');
        for (final i in activeObjectiveIndexes) {
          final s = _statistics['objective${i + 1}'];
          buffer.write('| ${s != null ? s[idx].toStringAsFixed(2) : "-"} ');
        }
        buffer.writeln('|');
      }
      buffer.writeln();

      // 学生个体达成
      buffer.writeln('### 3. 学生个体达成情况');
      buffer.writeln();
      buffer.writeln('共有 $studentCount 名学生参与评价。');
      buffer.writeln();
      buffer.writeln(
          '| 序号 | 学号 | 姓名 | ${activeObjectiveIndexes.map((i) => '目标${i + 1}达成度').join(' | ')} | 综合达成度 |');
      buffer.writeln(
          '|------|------|------|${activeObjectiveIndexes.map((_) => '-----------').join('|')}|-----------|');
      for (int idx = 0; idx < scores.length; idx++) {
        final s = scores[idx];
        final sid = s['student_id']?.toString() ?? '';
        final sname = s['student_name']?.toString() ?? '';
        double wt = 0;
        final achValues = <String>[];
        for (final i in activeObjectiveIndexes) {
          final ach = (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
          wt += ach * _objectiveWeights[i];
          achValues.add(ach.toStringAsFixed(4));
        }
        buffer.writeln(
            '| ${idx + 1} | $sid | $sname | ${achValues.join(' | ')} | ${wt.toStringAsFixed(4)} |');
      }
      buffer.writeln();

      // ══════════════════════════════════════════════════
      // 四、达成结果分析（对齐 DOCX 表6）
      // ══════════════════════════════════════════════════
      buffer.writeln('## 四、达成结果分析');
      buffer.writeln();

      buffer.writeln('### 1. 定量评价情况分析');
      buffer.writeln();

      // 从课程配置动态生成分析描述（不再硬编码课程内容）
      final objAnalysisDesc = List<String>.generate(4, (i) {
        final desc = cfg.descriptions[i];
        final assess = cfg.assessContents[i];
        final parts = assess.split('、');
        final envList = envDefsFor(i).map((env) {
          final label = env.$1;
          final ratio = (env.$3 * 100).toStringAsFixed(0);
          final content = parts.isNotEmpty ? '（${parts.last}）' : '';
          return '$label$content（$ratio%）';
        }).toList();
        final preview = desc.isEmpty
            ? kObjectiveNames[i]
            : desc.substring(0, min(desc.length, 30));
        return '课程目标${i + 1}主要考核$preview。'
            '该目标通过${envList.join("、")}综合评定。';
      });

      for (final i in activeObjectiveIndexes) {
        final a = _objectiveAchievements[i];
        final pA = pingshiAvg['obj${i + 1}'] ?? 0;
        final eA = experimentAvg['obj${i + 1}'] ?? 0;
        final xA = examAvg['obj${i + 1}'] ?? 0;
        String perf;
        if (a >= 0.85) {
          perf = '优秀，学生整体掌握良好';
        } else if (a >= 0.70) {
          perf = '良好，大部分学生达到预期';
        } else if (a >= 0.60) {
          perf = '达标但有提升空间';
        } else {
          perf = '未达标，需要重点关注和改进';
        }
        buffer.writeln(
            '**${kObjectiveNames[i]}**（达成度：${a.toStringAsFixed(4)}，$perf）');
        buffer.writeln();
        buffer.writeln(objAnalysisDesc[i]);
        buffer.writeln();
        if ((envWeightAt(i)['pingshi'] ?? 0) > 0) {
          buffer.writeln('- 平时环节达成度：${pA.toStringAsFixed(4)}');
        }
        if ((envWeightAt(i)['experiment'] ?? 0) > 0) {
          buffer.writeln('- 实验环节达成度：${eA.toStringAsFixed(4)}');
        }
        if ((envWeightAt(i)['exam'] ?? 0) > 0) {
          buffer.writeln('- 考核环节达成度：${xA.toStringAsFixed(4)}');
        }
        final lowCount = scores.where((s) {
          final ach = (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
          return ach < 0.6;
        }).length;
        if (lowCount > 0) {
          buffer.writeln('- 有 $lowCount 名学生该目标达成度低于0.60，需个别辅导');
        }
        buffer.writeln();
      }

      buffer.writeln('### 2. 定性评价情况分析');
      buffer.writeln();
      if (_surveySummary?['hasSurveyData'] == true) {
        final totalResp = _surveySummary!['totalResponses'] as int? ?? 0;
        final overallSat =
            (_surveySummary!['overallSatisfaction'] as double?) ?? 0;
        buffer.writeln(
            '共回收有效问卷 **$totalResp** 份，综合满意度为 **${(overallSat * 100).toStringAsFixed(1)}%**。');
        buffer.writeln();
        final qStats =
            (_surveySummary!['questionStats'] as List<Map<String, dynamic>>?) ??
                [];
        for (final qs in qStats) {
          final question = qs['question'] as String? ?? '';
          buffer.writeln('**$question**');
          if (qs['type'] == 'single_choice') {
            final counts = qs['counts'] as Map<String, int>? ?? {};
            final total = (qs['total'] as int?) ?? 1;
            for (final entry in counts.entries) {
              final pct = total > 0
                  ? (entry.value / total * 100).toStringAsFixed(1)
                  : '0';
              buffer.writeln('- ${entry.key}：${entry.value}人（$pct%）');
            }
          } else if (qs['type'] == 'rating') {
            buffer.writeln(
                '- 平均评分：${(qs['average'] as double? ?? 0).toStringAsFixed(2)} / 5.0');
          }
          buffer.writeln();
        }
      } else {
        final sortedIdx = [...activeObjectiveIndexes]..sort((a, b) =>
            _objectiveAchievements[b].compareTo(_objectiveAchievements[a]));
        buffer.writeln('从评价结果可以看出：');
        buffer.writeln();
        buffer.writeln(
            '- 学生在${kObjectiveNames[sortedIdx[0]]}方面表现最好（${_objectiveAchievements[sortedIdx[0]].toStringAsFixed(4)}）');
        final weakest = sortedIdx.last;
        buffer.writeln(
            '- ${kObjectiveNames[weakest]}方面相对较弱（${_objectiveAchievements[weakest].toStringAsFixed(4)}）');
        buffer.writeln();
        buffer.writeln('主要原因可能是：');
        buffer.writeln();
        buffer.writeln('1. 部分课程目标对应的考核内容综合性较强，学生对关键知识点迁移应用不足');
        buffer.writeln('2. 过程性评价中暴露出学生阶段性复盘和问题整理不充分');
        buffer.writeln('3. 终结性考核任务对分析、设计和表达能力要求较高，低分学生需要专项训练');
        buffer.writeln('4. 后续应结合大纲对照表，针对达成度偏低的目标补充训练与反馈');
        buffer.writeln();
      }

      buffer.writeln('### 3. 教学持续改进');
      buffer.writeln();
      buffer.writeln('#### 本轮教学改进措施执行情况');
      buffer.writeln();
      buffer.writeln('针对上一轮该课程教学持续改进意见，在本轮教学中持续改进的措施执行情况如下：');
      buffer.writeln();
      buffer.writeln('1. 在平时作业中加大与课程目标相关的分析应用问题的题目训练，实现期末考核内容与平时训练内容相一致');
      buffer.writeln('2. 在每一章结束后，在作业中增加与该章知识点相关的文献阅读培训，扩展学生的知识面并提高其文献阅读与总结能力');
      buffer.writeln('3. 根据大纲对照表复核各考核环节比例，优化过程性评价和终结性评价的衔接');
      buffer.writeln();
      buffer.writeln('#### 后续教学持续改进措施');
      buffer.writeln();
      buffer.writeln('针对本次课程目标达成评价情况分析，今后教学中拟采取以下改进措施：');
      buffer.writeln();
      for (final i in activeObjectiveIndexes) {
        final a = _objectiveAchievements[i];
        final objDesc = cfg.descriptions[i].length > 20
            ? cfg.descriptions[i].substring(0, 20)
            : cfg.descriptions[i];
        if (a < 0.60) {
          buffer.writeln(
              '${i + 1}. **${kObjectiveNames[i]}（${a.toStringAsFixed(4)}，未达标）**：大幅增加与「$objDesc」相关的课时和实践环节，增设单元测验，对低分学生进行一对一辅导');
        } else if (a < 0.70) {
          buffer.writeln(
              '${i + 1}. ${kObjectiveNames[i]}（${a.toStringAsFixed(4)}）：加大「$objDesc」相关的对比分析训练，补充测验题目');
        } else {
          buffer.writeln(
              '${i + 1}. ${kObjectiveNames[i]}（${a.toStringAsFixed(4)}）：保持现有教学节奏，适当提高考核难度，培养学生创新能力');
        }
      }
      buffer.writeln();

      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('评价教师签字：____________　　日期：$dateStr');
      buffer.writeln();
      buffer.writeln('教研室主任签字：____________　　日期：____________');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln('*报告由知识图谱教学系统自动生成*');

      final reportText = buffer.toString();

      if (mounted) {
        setState(() => _generatingReport = false);
        _showReportDialog(reportText);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generatingReport = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('报告生成失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showReportDialog(String reportText) {
    showDialog(
      context: context,
      builder: (ctx) => ReportPreviewDialog(reportText: reportText),
    );
  }

  Future<void> _exportDocx() async {
    if (_calcResults == null || _selectedBatchId == null) return;
    try {
      final batch = _batches.firstWhere((b) => b['id'] == _selectedBatchId,
          orElse: () => <String, dynamic>{});
      final teacherName = widget.authService.currentUser?.realName ?? '教师';
      final scores = await widget.achievementDao.getScores(_selectedBatchId!);
      final cfg = _config;

      // 分环节达成度（平时/实验/期末）用于报告表5
      final combined = await widget.achievementDao
          .calculateCombinedAchievement(_selectedBatchId!);
      final pingshiAvg = combined['pingshi'] as Map<String, double>? ?? {};
      final experimentAvg =
          combined['experiment'] as Map<String, double>? ?? {};
      final examAvg = combined['exam'] as Map<String, double>? ?? {};
      final rawEnvWeights =
          (combined['weightsByObjective'] as List?) ?? const [];

      Map<String, double> envWeightAt(int index) {
        if (index >= 0 && index < rawEnvWeights.length) {
          final raw = rawEnvWeights[index] as Map?;
          return {
            'pingshi': (raw?['pingshi'] as num?)?.toDouble() ?? 0,
            'experiment': (raw?['experiment'] as num?)?.toDouble() ?? 0,
            'exam': (raw?['exam'] as num?)?.toDouble() ?? 0,
          };
        }
        return {'pingshi': 0.20, 'experiment': 0.30, 'exam': 0.50};
      }

      final activeObjectiveIndexes = _activeObjectiveIndexesFor(cfg);
      final objectives = <Map<String, dynamic>>[];
      for (final i in activeObjectiveIndexes) {
        if (_objectiveWeights[i] <= 0 && cfg.fullMarks[i] <= 0) continue;
        final objKey = 'obj${i + 1}';
        final envWeight = envWeightAt(i);
        final envDefs = [
          ('平时', 'pingshi', envWeight['pingshi'] ?? 0),
          ('实验', 'experiment', envWeight['experiment'] ?? 0),
          ('考核', 'exam', envWeight['exam'] ?? 0),
        ].where((e) => e.$3 > 0).toList();
        final envs = <Map<String, dynamic>>[];
        for (final (label, key, w) in envDefs) {
          final src = key == 'pingshi'
              ? pingshiAvg
              : key == 'experiment'
                  ? experimentAvg
                  : examAvg;
          final ach = src[objKey] ?? 0;
          envs.add({
            'name': label,
            'full': cfg.fullMarks[i],
            'avg': ach * cfg.fullMarks[i],
            'ach': ach,
            'weight': w,
          });
        }
        objectives.add({
          'objective': i + 1,
          'weight': _objectiveWeights[i],
          'indicator': cfg.indicators[i],
          'description': cfg.descriptions[i],
          'assess_content': cfg.assessContents[i],
          'full_mark': cfg.fullMarks[i],
          'achievement': _objectiveAchievements[i],
          'avgScore': _objectiveAchievements[i] * 100,
          'envs': envs,
        });
      }

      // 从 config（含大纲导入的 course_objectives）构建 syllabus，
      // 修复此前传空 {} 导致 docx 一/二/三表表头空白的 bug。
      final syllabus = <String, dynamic>{
        'info': <String, String>{
          '英文名称': (batch['course_name'] ?? '移动应用开发').toString(),
          '考核方式': '考查',
          '开课学期': (batch['semester'] ?? '').toString(),
        },
        'objectives': [
          for (final i in activeObjectiveIndexes)
            {
              'num': i + 1,
              'objective': cfg.descriptions[i],
              'requirement': cfg.indicators[i],
            }
        ],
        'weights': [
          for (final i in activeObjectiveIndexes)
            {
              'objective': i + 1,
              'weight': _objectiveWeights[i],
              'pingshi_full': cfg.fullMarks[i].toInt(),
              'experiment_full': (envWeightAt(i)['experiment'] ?? 0) > 0
                  ? cfg.fullMarks[i].toInt()
                  : 0,
              'exam_full': cfg.fullMarks[i].toInt(),
              'pingshi_ratio': envWeightAt(i)['pingshi'] ?? 0,
              'experiment_ratio': envWeightAt(i)['experiment'] ?? 0,
              'exam_ratio': envWeightAt(i)['exam'] ?? 0,
            }
        ],
      };

      final path = await AchievementDocxService.instance.generateReport(
        batchName: batch['batch_name'] ?? '达成评价',
        courseName: batch['course_name'] ?? '移动应用开发',
        className: batch['class_name'] ?? '班级',
        semester: batch['semester'] ?? DateTime.now().year.toString(),
        teacherName: teacherName,
        syllabus: syllabus,
        objectives: objectives,
        qualitativeText: _qualitativeFromSurvey(),
        classStats: {
          'studentCount': scores.length,
          'avgTotal': _weightedAchievement * 100,
          'maxTotal': _maxOf(scores, (s) => (s['total_score'] as double?) ?? 0),
          'minTotal': _minOf(scores, (s) => (s['total_score'] as double?) ?? 0),
          'stdDev':
              _stdDevOf(scores, (s) => (s['total_score'] as double?) ?? 0),
        },
        students: scores,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Word 报告已保存: $path'),
              duration: const Duration(seconds: 4)),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ReportTab.exportDocx', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出Word失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 把问卷满意度汇总转成 Word 报告「定性评价」段文字；无问卷数据返回 null
  /// 由 docx 服务回退到通用模板文案。
  String? _qualitativeFromSurvey() {
    if (_surveySummary?['hasSurveyData'] != true) return null;
    final totalResp = _surveySummary!['totalResponses'] as int? ?? 0;
    final overallSat = (_surveySummary!['overallSatisfaction'] as double?) ?? 0;
    return '共回收有效问卷 $totalResp 份，综合满意度为 '
        '${(overallSat * 100).toStringAsFixed(1)}%。问卷结果与定量评价结果基本一致，'
        '表明学生自我评价与实际能力达成情况基本相符。';
  }

  /// 导出 Excel 报告（对齐计科22模板：平时/实验/期末明细 + 个体达成度 + 目标点达成度 + 图表数据页）。
  Future<void> _exportExcel() async {
    if (_calcResults == null || _selectedBatchId == null) return;
    try {
      final batch = _batches.firstWhere((b) => b['id'] == _selectedBatchId,
          orElse: () => <String, dynamic>{});
      final courseName = (batch['course_name'] ?? '移动应用开发').toString();
      final className = (batch['class_name'] ?? '班级').toString();
      final semester = (batch['semester'] ?? '').toString();
      final scores = await widget.achievementDao.getScores(_selectedBatchId!);
      final comb = await widget.achievementDao
          .calculateCombinedAchievement(_selectedBatchId!);
      final pingshi =
          await widget.achievementDao.getPingshiScores(_selectedBatchId!);
      final experiment =
          await widget.achievementDao.getExperimentScores(_selectedBatchId!);
      final exam = await widget.achievementDao.getExamScores(_selectedBatchId!);
      final cf = _config;
      final fullMarks = cf.fullMarks;
      final ps = comb['pingshi'] as Map? ?? {};
      final es = comb['experiment'] as Map? ?? {};
      final xs = comb['exam'] as Map? ?? {};
      final envWeightsByObjective = ((comb['weightsByObjective'] as List?) ??
              const [])
          .map((w) =>
              (w as Map?)?.map(
                (key, value) =>
                    MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0),
              ) ??
              <String, double>{})
          .toList();
      bool defaultLike(Map<String, double> w) =>
          ((w['pingshi'] ?? 0) - 0.2).abs() < 0.0001 &&
          ((w['experiment'] ?? 0) - 0.3).abs() < 0.0001 &&
          ((w['exam'] ?? 0) - 0.5).abs() < 0.0001;
      final activeObjectives = _activeObjectiveIndexesFor(cf);
      final standardThreePart = activeObjectives.length == 4 &&
          envWeightsByObjective.length >= 4 &&
          activeObjectives.every((i) => defaultLike(envWeightsByObjective[i]));
      final pById = {for (final r in pingshi) '${r['student_id']}': r};
      final eById = {for (final r in experiment) '${r['student_id']}': r};
      final xById = {for (final r in exam) '${r['student_id']}': r};

      Map<String, double> avgMap(Map source) => {
            for (int i = 1; i <= 4; i++)
              'obj$i': (source['obj$i'] as num?)?.toDouble() ?? 0,
          };

      final dir = await OutputPathService.getOutputDirectory();
      final safeName = '$className《$courseName》课程达成度评价表格.xlsx';
      final file = File('${dir.path}/$safeName');
      if (!standardThreePart) {
        await _exportDynamicExcelReport(
          file: file,
          courseName: courseName,
          className: className,
          semester: semester,
          scores: scores,
          combined: comb,
          config: cf,
        );
        return;
      }
      final templateFile =
          await AchievementTemplateExcelService.instance.findTemplateForCourse(
        courseName,
      );
      if (templateFile != null) {
        final payload = AchievementExcelTemplatePayload(
          courseName: courseName,
          className: className,
          semester: semester,
          objectiveWeights: _objectiveWeights,
          objectiveAchievements: _objectiveAchievements,
          objectiveNames: cf.objectiveNames,
          indicators: cf.indicators,
          scores: scores,
          pingshi: pingshi,
          experiment: experiment,
          exam: exam,
          pingshiAverage: avgMap(ps),
          experimentAverage: avgMap(es),
          examAverage: avgMap(xs),
          weightedAchievement: _weightedAchievement,
        );
        final bytes = AchievementTemplateExcelService.instance.fillTemplate(
          Uint8List.fromList(await templateFile.readAsBytes()),
          payload,
        );
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Excel模板已填充:${file.path}'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                  label: '打开', onPressed: () => OpenFilex.open(file.path))));
        }
        return;
      }

      final excel = xl.Excel.createExcel();
      for (final n in excel.tables.keys.toList()) {
        excel.delete(n);
      }

      xl.TextCellValue t(Object? v) => xl.TextCellValue(v?.toString() ?? '');
      xl.DoubleCellValue n(num? v, [int digits = 4]) {
        final d = (v ?? 0).toDouble();
        return xl.DoubleCellValue(double.parse(d.toStringAsFixed(digits)));
      }

      double val(Map? r, String key) => (r?[key] as num?)?.toDouble() ?? 0;
      double mapVal(Map m, int objectiveIndex) =>
          (m['obj${objectiveIndex + 1}'] as num?)?.toDouble() ?? 0;
      double experimentTarget4Score(Map? row) {
        final exp7 = val(row, 'exp7_score');
        if (exp7 > 0) return exp7;
        final obj4 = val(row, 'obj4_achievement');
        return obj4 > 0 ? obj4 * 100 : 0;
      }

      List<xl.CellValue?> rowOf(int len) =>
          List<xl.CellValue?>.filled(len, null);

      final s1 = excel['平时成绩'];
      s1.appendRow([t('$semester$className《$courseName》课程目标达成度计算表（平时）')]);
      var r = rowOf(39);
      r[0] = t('班级：$className');
      r[2] = t('评价方式:平时');
      r[38] = t('满分值：100分');
      s1.appendRow(r);
      r = rowOf(39);
      r[0] = t('课程目标');
      r[2] = t('1');
      r[15] = t('2');
      r[27] = t('4');
      r[38] = t('总评');
      s1.appendRow(r);
      r = rowOf(39);
      r[0] = t('学号');
      r[1] = t('姓名');
      r[2] = t('课堂表现 满分20');
      r[15] = t('期间测验 满分30');
      r[27] = t('课外学习 满分50');
      s1.appendRow(r);
      r = rowOf(39);
      r[13] = t('最后得分');
      r[14] = t('指标点达成度');
      r[25] = t('平均分');
      r[26] = t('指标点达成度');
      r[36] = t('平均分');
      r[37] = t('指标点达成度');
      r[38] = t('得分');
      s1.appendRow(r);
      for (final row in pingshi) {
        r = rowOf(39);
        final classActivity = val(row, 'class_activity_score');
        final quizHomework = val(row, 'quiz_homework_score');
        final extraLearning = val(row, 'extra_learning_score');
        r[0] = t(row['student_id']);
        r[1] = t(row['student_name']);
        r[2] = n(classActivity, 1);
        r[13] = n(classActivity, 1);
        r[14] = n(val(row, 'class_activity_achievement'), 4);
        r[15] = n(quizHomework, 1);
        r[25] = n(quizHomework, 1);
        r[26] = n(val(row, 'quiz_homework_achievement'), 4);
        r[27] = n(extraLearning, 1);
        r[36] = n(extraLearning, 1);
        r[37] = n(val(row, 'extra_learning_achievement'), 4);
        r[38] = n(val(row, 'total_score'), 1);
        s1.appendRow(r);
      }

      final s2 = excel['实验成绩'];
      s2.appendRow([t('$semester$className《$courseName》课程目标达成度计算表（实验）')]);
      r = rowOf(14);
      r[0] = t('班级：$className');
      r[2] = t('评价方式:实验');
      r[13] = t('满分值：100分');
      s2.appendRow(r);
      r = rowOf(14);
      r[0] = t('课程目标');
      r[2] = t('1');
      r[5] = t('2');
      r[8] = t('3');
      r[11] = t('4');
      r[13] = t('总评');
      s2.appendRow(r);
      r = rowOf(14);
      r[0] = t('学号');
      r[1] = t('姓名');
      r[2] = t('满分${fullMarks[0].toInt()}');
      r[5] = t('满分${fullMarks[1].toInt()}');
      r[8] = t('满分${fullMarks[2].toInt()}');
      r[11] = t('满分${fullMarks[3].toInt()}');
      s2.appendRow(r);
      r = rowOf(14);
      r[2] = t('实验1得分（满分5分）');
      r[3] = t('实验2得分（满分5分）');
      r[4] = t('指标点达成度');
      r[5] = t('实验3得分（满分10分）');
      r[6] = t('实验4得分（满分10分）');
      r[7] = t('指标点达成度');
      r[8] = t('实验5得分（满分15分）');
      r[9] = t('实验6得分（满分15分）');
      r[10] = t('指标点达成度');
      r[11] = t('实验7得分（满分40分）');
      r[12] = t('指标点达成度');
      r[13] = t('得分');
      s2.appendRow(r);
      for (final row in experiment) {
        r = rowOf(14);
        r[0] = t(row['student_id']);
        r[1] = t(row['student_name']);
        r[2] = n(val(row, 'exp1_score'), 1);
        r[3] = n(val(row, 'exp2_score'), 1);
        r[4] = n(val(row, 'obj1_achievement'), 4);
        r[5] = n(val(row, 'exp3_score'), 1);
        r[6] = n(val(row, 'exp4_score'), 1);
        r[7] = n(val(row, 'obj2_achievement'), 4);
        r[8] = n(val(row, 'exp5_score'), 1);
        r[9] = n(val(row, 'exp6_score'), 1);
        r[10] = n(val(row, 'obj3_achievement'), 4);
        r[11] = n(experimentTarget4Score(row), 1);
        r[12] = n(val(row, 'obj4_achievement'), 4);
        r[13] = n(val(row, 'total_score'), 1);
        s2.appendRow(r);
      }

      final s3 = excel['期末成绩'];
      s3.appendRow([t('$semester$className《$courseName》课程目标达成度计算表（期末考核）')]);
      r = rowOf(11);
      r[0] = t('班级：$className');
      r[2] = t('评价方式:期末考核（大作业）');
      r[10] = t('满分值：100分');
      s3.appendRow(r);
      r = rowOf(11);
      r[0] = t('课程目标');
      r[2] = t('1');
      r[4] = t('2');
      r[6] = t('3');
      r[8] = t('4');
      r[10] = t('总评');
      s3.appendRow(r);
      r = rowOf(11);
      r[0] = t('学号');
      r[1] = t('姓名');
      r[2] = t('满分${fullMarks[0].toInt()}');
      r[4] = t('满分${fullMarks[1].toInt()}');
      r[6] = t('满分${fullMarks[2].toInt()}');
      r[8] = t('满分${fullMarks[3].toInt()}');
      s3.appendRow(r);
      r = rowOf(11);
      r[2] = t('项目（30%）');
      r[3] = t('指标点达成度');
      r[4] = t('小组（20%）');
      r[5] = t('指标点达成度');
      r[6] = t('个人（20%）');
      r[7] = t('指标点达成度');
      r[8] = t('答辩（30%）');
      r[9] = t('指标点达成度');
      r[10] = t('得分');
      s3.appendRow(r);
      for (final row in exam) {
        r = rowOf(11);
        r[0] = t(row['student_id']);
        r[1] = t(row['student_name']);
        r[2] = n(val(row, 'project_score'), 1);
        r[3] = n(val(row, 'obj1_achievement'), 4);
        r[4] = n(val(row, 'group_score'), 1);
        r[5] = n(val(row, 'obj2_achievement'), 4);
        r[6] = n(val(row, 'individual_score'), 1);
        r[7] = n(val(row, 'obj3_achievement'), 4);
        r[8] = n(val(row, 'defense_score'), 1);
        r[9] = n(val(row, 'obj4_achievement'), 4);
        r[10] = n(val(row, 'total_score'), 1);
        s3.appendRow(r);
      }

      final s4 = excel['学生个体课程目标达成度'];
      s4.appendRow([t('$semester$className《$courseName》学生个体课程目标达成度计算表')]);
      s4.appendRow([t('班级：$className')]);
      r = rowOf(18);
      r[0] = t('课程目标');
      r[2] = t('1');
      r[6] = t('2');
      r[10] = t('3');
      r[14] = t('4');
      s4.appendRow(r);
      r = rowOf(18);
      r[0] = t('支撑的毕业要求指标点');
      r[2] = t(cf.indicators[0]);
      r[6] = t(cf.indicators[1]);
      r[10] = t(cf.indicators[2]);
      r[14] = t(cf.indicators[3]);
      s4.appendRow(r);
      r = rowOf(18);
      r[0] = t('权重');
      for (final offset in [2, 6, 10, 14]) {
        r[offset] = n(0.2, 1);
        r[offset + 1] = n(0.3, 1);
        r[offset + 2] = n(0.5, 1);
        r[offset + 3] = n(1, 0);
      }
      s4.appendRow(r);
      r = rowOf(18);
      r[0] = t('学号');
      r[1] = t('姓名');
      for (final offset in [2, 6, 10, 14]) {
        r[offset] = t('平时评价达成度');
        r[offset + 1] = t('实验评价达成度');
        r[offset + 2] = t('期末考核评价达成度');
        r[offset + 3] = t('课程目标达成度');
      }
      s4.appendRow(r);
      for (final s in scores) {
        final sid = '${s['student_id'] ?? ''}';
        final p = pById[sid], e = eById[sid], x = xById[sid];
        r = rowOf(18);
        r[0] = t(sid);
        r[1] = t(s['student_name']);
        for (int i = 0; i < 4; i++) {
          final offset = 2 + i * 4;
          final pAch = i == 0
              ? val(p, 'class_activity_achievement')
              : i == 1
                  ? val(p, 'quiz_homework_achievement')
                  : i == 2
                      ? 0.0
                      : val(p, 'extra_learning_achievement');
          final eAch = val(e, 'obj${i + 1}_achievement');
          final xAch = val(x, 'obj${i + 1}_achievement');
          final objAch =
              (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
          r[offset] = n(pAch, 4);
          r[offset + 1] = n(eAch, 4);
          r[offset + 2] = n(xAch, 4);
          r[offset + 3] = n(objAch, 4);
        }
        s4.appendRow(r);
      }

      final s5 = excel['课程目标点达成度'];
      s5.appendRow([t('$semester$className《$courseName》课程目标达成度计算表')]);
      s5.appendRow([
        t('课程目标及权重'),
        null,
        t('评价方式'),
        null,
        null,
        null,
        null,
        t('课成目标达成度'),
        t('毕业要求指标点达成度')
      ]);
      s5.appendRow([
        t('课程目标i'),
        t('权重'),
        t('评价环节j'),
        t('满分'),
        t('平均分'),
        t('达成度'),
        t('权重'),
        t('课程目标达成度'),
        t('指标点'),
        t('达成度')
      ]);
      const envNames = ['平时', '实验', '期末考试'];
      const envWeights = [0.2, 0.3, 0.5];
      const envFull = [20.0, 30.0, 50.0];
      for (int i = 0; i < 4; i++) {
        final envAch = [mapVal(ps, i), mapVal(es, i), mapVal(xs, i)];
        for (int j = 0; j < 3; j++) {
          r = rowOf(10);
          if (j == 0) {
            r[0] = t('目标${i + 1}');
            r[1] = n(_objectiveWeights[i], 2);
            r[7] = n(_objectiveAchievements[i], 4);
            r[8] = t(cf.indicators[i]);
            r[9] = n(_objectiveAchievements[i], 4);
          }
          r[2] = t(envNames[j]);
          r[3] = n(envFull[j], 0);
          r[4] = n(envAch[j] * envFull[j], 2);
          r[5] = n(envAch[j], 4);
          r[6] = n(envWeights[j], 1);
          s5.appendRow(r);
        }
      }
      s5.appendRow([
        t('课程总体目标期望值'),
        n(0.6, 1),
        null,
        null,
        null,
        null,
        t('课程总体目标达成度(cc)'),
        n(_weightedAchievement, 4),
        null,
        null
      ]);

      // 条形图 + 4 张散点趋势图数据页（对齐模板的 课程目标条形图 / 目标N散点趋势图）
      // 数值列用 DoubleCellValue，否则注入的图表无法把文本当数据绘制。
      final bar = excel['课程目标条形图'];
      for (int i = 0; i < 4; i++) {
        bar.appendRow([
          t(cf.objectiveNames[i]),
          xl.DoubleCellValue(
              double.parse(_objectiveAchievements[i].toStringAsFixed(4))),
        ]);
      }
      for (int i = 0; i < 4; i++) {
        final sh = excel['目标${i + 1}散点趋势图'];
        for (int k = 0; k < scores.length; k++) {
          final a =
              (scores[k]['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
          sh.appendRow([
            xl.DoubleCellValue((k + 1).toDouble()),
            xl.DoubleCellValue(double.parse(a.toStringAsFixed(4))),
            xl.DoubleCellValue(
                double.parse(_objectiveAchievements[i].toStringAsFixed(4))),
            xl.DoubleCellValue(0.6),
          ]);
        }
      }

      var bytes = excel.save();
      if (bytes == null) throw StateError('Excel生成失败');
      // 注入原生 OOXML 图表：条形图(4目标) + 每目标散点+趋势线+参考线
      final specs = <ChartSpec>[
        ChartSpec.bar(sheetName: '课程目标条形图', title: '课程目标达成度', rowCount: 4),
        for (int i = 0; i < 4; i++)
          ChartSpec.scatter(
              sheetName: '目标${i + 1}散点趋势图',
              title: '学生个体课程目标${i + 1}达成评价结果',
              rowCount: scores.length),
      ];
      bytes = ExcelChartInjector.inject(Uint8List.fromList(bytes), specs);
      await file.writeAsBytes(bytes);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Excel已导出:${file.path}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
                label: '打开', onPressed: () => OpenFilex.open(file.path))));
    } catch (e, st) {
      swallowDebug(e, tag: 'ReportTab.exportExcel', stack: st);
    }
  }

  Future<void> _exportDynamicExcelReport({
    required File file,
    required String courseName,
    required String className,
    required String semester,
    required List<Map<String, dynamic>> scores,
    required Map<String, dynamic> combined,
    required AchievementConfig config,
  }) async {
    final excel = xl.Excel.createExcel();
    for (final n in excel.tables.keys.toList()) {
      excel.delete(n);
    }

    xl.TextCellValue t(Object? v) => xl.TextCellValue(v?.toString() ?? '');
    xl.DoubleCellValue n(num? v, [int digits = 4]) {
      final d = (v ?? 0).toDouble();
      return xl.DoubleCellValue(double.parse(d.toStringAsFixed(digits)));
    }

    final activeObjectives = [
      for (var i = 0; i < 4; i++)
        if (_objectiveWeights[i] > 0 || config.fullMarks[i] > 0) i
    ];
    final rawWeights = ((combined['weightsByObjective'] as List?) ?? const [])
        .map((w) =>
            (w as Map?)?.map(
              (key, value) =>
                  MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0),
            ) ??
            <String, double>{})
        .toList();
    Map<String, double> weightsFor(int i) =>
        i < rawWeights.length ? rawWeights[i] : const {};
    final envSources = {
      'pingshi': combined['pingshi'] as Map? ?? {},
      'experiment': combined['experiment'] as Map? ?? {},
      'exam': combined['exam'] as Map? ?? {},
    };
    final envLabels = {
      'pingshi': '平时成绩',
      'experiment': '实验成绩',
      'exam': '考核成绩',
    };
    final activeEnvKeys = [
      for (final env in ['pingshi', 'experiment', 'exam'])
        if (activeObjectives.any((i) => (weightsFor(i)[env] ?? 0) > 0)) env
    ];

    final matrix = excel['课程目标达成度'];
    matrix.appendRow([
      t('$semester$className《$courseName》课程目标达成度计算表'),
    ]);
    matrix.appendRow([
      t('课程目标'),
      t('目标权重'),
      t('指标点'),
      t('评价环节'),
      t('环节比例'),
      t('目标满分'),
      t('班级平均达成度'),
      t('课程目标达成度'),
    ]);
    for (final i in activeObjectives) {
      final weights = weightsFor(i);
      var first = true;
      for (final env in ['pingshi', 'experiment', 'exam']) {
        final w = weights[env] ?? 0;
        if (w <= 0) continue;
        final ach = (envSources[env]?['obj${i + 1}'] as num?)?.toDouble() ?? 0;
        matrix.appendRow([
          t(first ? '课程目标${i + 1}' : ''),
          first ? n(_objectiveWeights[i], 2) : t(''),
          t(first ? config.indicators[i] : ''),
          t(envLabels[env]),
          n(w, 2),
          n(config.fullMarks[i], 0),
          n(ach, 4),
          first ? n(_objectiveAchievements[i], 4) : t(''),
        ]);
        first = false;
      }
    }
    matrix.appendRow([
      t('课程总体目标达成度'),
      n(_weightedAchievement, 4),
    ]);

    final students = excel['学生个体达成度'];
    students.appendRow([
      t('学号'),
      t('姓名'),
      for (final i in activeObjectives) t('课程目标${i + 1}达成度'),
      t('综合达成度'),
    ]);
    for (final s in scores) {
      var weighted = 0.0;
      final row = <xl.CellValue?>[
        t(s['student_id']),
        t(s['student_name']),
      ];
      for (final i in activeObjectives) {
        final ach = (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
        weighted += ach * _objectiveWeights[i];
        row.add(n(ach, 4));
      }
      row.add(n(weighted, 4));
      students.appendRow(row);
    }

    final syllabus = excel['大纲对照表'];
    syllabus.appendRow([
      t('课程目标'),
      t('指标点'),
      t('目标权重'),
      t('目标满分'),
      for (final env in activeEnvKeys) t('${envLabels[env]}比例'),
      t('考核内容'),
    ]);
    for (final i in activeObjectives) {
      final weights = weightsFor(i);
      syllabus.appendRow([
        t('课程目标${i + 1}'),
        t(config.indicators[i]),
        n(_objectiveWeights[i], 2),
        n(config.fullMarks[i], 0),
        for (final env in activeEnvKeys) n(weights[env] ?? 0, 2),
        t(config.assessContents[i]),
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) throw StateError('Excel生成失败');
    await file.writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Excel已按大纲动态导出:${file.path}'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
              label: '打开', onPressed: () => OpenFilex.open(file.path))));
    }
  }

  double _maxOf(List<Map<String, dynamic>> items,
      double Function(Map<String, dynamic>) getter) {
    if (items.isEmpty) return 0;
    return items.map(getter).reduce((a, b) => a > b ? a : b);
  }

  double _minOf(List<Map<String, dynamic>> items,
      double Function(Map<String, dynamic>) getter) {
    if (items.isEmpty) return 0;
    return items.map(getter).reduce((a, b) => a < b ? a : b);
  }

  double _stdDevOf(List<Map<String, dynamic>> items,
      double Function(Map<String, dynamic>) getter) {
    if (items.isEmpty) return 0;
    final values = items.map(getter).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return sqrt(variance);
  }

  Future<void> _exportReport() async {
    if (_calcResults == null) return;

    setState(() => _generatingReport = true);

    try {
      final batch = _batches.firstWhere(
        (b) => b['id'] == _selectedBatchId,
        orElse: () => <String, dynamic>{},
      );
      final scores =
          await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      final courseName = batch['course_name'] ?? '移动应用开发';
      final className = batch['class_name'] ?? '软件23';
      final semester = batch['semester'] ?? '-';
      final teacherId = batch['teacher_id'] ?? '';
      final dateStr = DateTime.now().toString().substring(0, 10);
      final cfg = _config;
      final objIndicators = cfg.indicators;
      final objDescShort = cfg.descriptions;
      final objMarks = cfg.fullMarks.map((m) => m.toInt()).toList();

      // 获取三类评价分项达成度
      final combined = await widget.achievementDao
          .calculateCombinedAchievement(_selectedBatchId!);
      final pingshiAvg = combined['pingshi'] as Map<String, double>;
      final experimentAvg = combined['experiment'] as Map<String, double>;
      final examAvg = combined['exam'] as Map<String, double>;
      final combinedAvg = combined['combined'] as Map<String, double>;
      final envWeightsByObjective =
          ((combined['weightsByObjective'] as List?) ?? const [])
              .map((w) =>
                  (w as Map?)?.map(
                    (key, value) => MapEntry(
                        key.toString(), (value as num?)?.toDouble() ?? 0),
                  ) ??
                  <String, double>{})
              .toList();
      bool defaultLike(Map<String, double> w) =>
          ((w['pingshi'] ?? 0) - 0.2).abs() < 0.0001 &&
          ((w['experiment'] ?? 0) - 0.3).abs() < 0.0001 &&
          ((w['exam'] ?? 0) - 0.5).abs() < 0.0001;
      final activeObjectiveIndexes = _activeObjectiveIndexesFor(cfg);
      final standardThreePart = activeObjectiveIndexes.length == 4 &&
          envWeightsByObjective.length >= 4 &&
          activeObjectiveIndexes
              .every((i) => defaultLike(envWeightsByObjective[i]));
      if (!standardThreePart) {
        await _exportDynamicPdfReport(
          courseName: courseName.toString(),
          className: className.toString(),
          semester: semester.toString(),
          dateStr: dateStr,
          scores: scores,
          config: cfg,
          combined: combined,
          envWeightsByObjective: envWeightsByObjective,
        );
        if (mounted) setState(() => _generatingReport = false);
        return;
      }

      // 加载中文字体：优先 Google Fonts（可靠），回退本地 TTC
      pw.Font? chineseFont;
      pw.Font? chineseBoldFont;
      try {
        chineseFont = await PdfGoogleFonts.notoSansSCRegular();
        chineseBoldFont = await PdfGoogleFonts.notoSansSCBold();
      } catch (e, st) {
        // 离线回退到本地字体
        swallowDebug(e, tag: 'ReportTab.googleFonts', stack: st);
        try {
          final fontData = await rootBundle.load('assets/fonts/msyh.ttc');
          chineseFont = pw.Font.ttf(fontData);
        } catch (e2) {
          swallow(e2, tag: 'ReportTab.localFontRegular');
        }
        try {
          final boldData = await rootBundle.load('assets/fonts/msyhbd.ttc');
          chineseBoldFont = pw.Font.ttf(boldData);
        } catch (e2) {
          swallow(e2, tag: 'ReportTab.localFontBold');
          chineseBoldFont = chineseFont;
        }
      }

      final theme = chineseFont != null
          ? pw.ThemeData.withFont(
              base: chineseFont, bold: chineseBoldFont ?? chineseFont)
          : null;
      final pdf = pw.Document(theme: theme);

      final baseStyle = chineseFont != null
          ? pw.TextStyle(font: chineseFont, fontSize: 10)
          : const pw.TextStyle(fontSize: 10);
      final titleStyle = baseStyle.copyWith(
          fontSize: 18, font: chineseBoldFont, fontWeight: pw.FontWeight.bold);
      final headerStyle = baseStyle.copyWith(
          fontSize: 14, font: chineseBoldFont, fontWeight: pw.FontWeight.bold);
      final subHeaderStyle = baseStyle.copyWith(
          fontSize: 12, font: chineseBoldFont, fontWeight: pw.FontWeight.bold);
      final boldStyle = baseStyle.copyWith(
          font: chineseBoldFont, fontWeight: pw.FontWeight.bold);

      // 满意度数据
      final hasSurvey = _surveySummary?['hasSurveyData'] == true;
      final overallSat =
          (_surveySummary?['overallSatisfaction'] as double?) ?? 0;
      final totalResp = _surveySummary?['totalResponses'] as int? ?? 0;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            // 标题
            pw.Center(
                child: pw.Text(
              '$className《$courseName》课程目标达成评价报告',
              style: titleStyle,
            )),
            pw.SizedBox(height: 16),

            // ═══ 一、基本信息（对齐 DOCX 表0 + 表1）═══
            pw.Text('一、基本信息', style: headerStyle),
            pw.SizedBox(height: 8),

            pw.Text('1. 课程基本信息', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['项目', '内容', '项目', '内容'],
              data: [
                ['课程名称', courseName, '授课班级', className],
                if (teacherId.isNotEmpty)
                  ['授课教师', teacherId, '学生人数', '${scores.length}']
                else
                  ['学生人数', '${scores.length}', '评价日期', dateStr],
                ['课程性质', '考查（大作业）', '评价方式', '定量+定性'],
                ['开课学期', semester, '达成度预期阈值', '0.60'],
              ],
            ),
            pw.SizedBox(height: 12),

            pw.Text('2. 课程支撑毕业要求与课程目标对应关系', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle.copyWith(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['毕业要求指标点', '课程目标', '权重', '课程目标描述'],
              data: [
                for (int i = 0; i < 4; i++)
                  [
                    '指标点${objIndicators[i]}',
                    kObjectiveNames[i],
                    _objectiveWeights[i].toStringAsFixed(2),
                    objDescShort[i],
                  ],
              ],
            ),
            pw.SizedBox(height: 12),

            pw.Text('3. 评价方式及成绩评定对照表', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: [
                '课程目标',
                '权重',
                '支撑指标点',
                '平时成绩(20分)',
                '实验成绩(30分)',
                '期末成绩(50分)'
              ],
              data: [
                for (int i = 0; i < 4; i++)
                  [
                    kObjectiveNames[i],
                    _objectiveWeights[i].toStringAsFixed(2),
                    '指标点${objIndicators[i]}',
                    '${objMarks[i]}',
                    '${objMarks[i]}',
                    '${objMarks[i]}',
                  ],
                ['合计', '1.00', '—', '20', '30', '50'],
              ],
            ),
            pw.SizedBox(height: 16),

            // ═══ 二、课程考核标准（对齐 DOCX 表2 + 表3 + 表4）═══
            pw.Text('二、课程考核标准', style: headerStyle),
            pw.SizedBox(height: 8),

            pw.Text('1. 平时成绩评价标准（满分20分）', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle.copyWith(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: [
                '课程目标',
                '考核内容',
                '优秀(90-100%)',
                '良好(70-89%)',
                '合格(60-69%)',
                '不合格(0-59%)'
              ],
              data: [
                [
                  '课程目标1',
                  '课堂表现',
                  '全面掌握，表现突出',
                  '较好掌握，表现良好',
                  '基本掌握，表现一般',
                  '未能掌握，需要改进'
                ],
                [
                  '课程目标2',
                  '期间测验',
                  '全面掌握，表现突出',
                  '较好掌握，表现良好',
                  '基本掌握，表现一般',
                  '未能掌握，需要改进'
                ],
                [
                  '课程目标4',
                  '课外学习',
                  '全面掌握，表现突出',
                  '较好掌握，表现良好',
                  '基本掌握，表现一般',
                  '未能掌握，需要改进'
                ],
              ],
            ),
            pw.SizedBox(height: 10),

            pw.Text('2. 实验成绩评价标准（满分30分）', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle.copyWith(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: [
                '课程目标',
                '考核内容',
                '优秀(90-100%)',
                '良好(70-89%)',
                '合格(60-69%)',
                '不合格(0-59%)'
              ],
              data: [
                [
                  '课程目标1',
                  '实验1-2',
                  '独立完成，结果正确',
                  '基本完成，结果较好',
                  '能够完成，有少量错误',
                  '无法完成或错误较多'
                ],
                [
                  '课程目标2',
                  '实验3-4',
                  '独立完成，结果正确',
                  '基本完成，结果较好',
                  '能够完成，有少量错误',
                  '无法完成或错误较多'
                ],
                [
                  '课程目标3',
                  '实验5-6',
                  '独立完成，结果正确',
                  '基本完成，结果较好',
                  '能够完成，有少量错误',
                  '无法完成或错误较多'
                ],
                [
                  '课程目标4',
                  '实验7',
                  '独立完成，结果正确',
                  '基本完成，结果较好',
                  '能够完成，有少量错误',
                  '无法完成或错误较多'
                ],
              ],
            ),
            pw.SizedBox(height: 10),

            pw.Text('3. 期末考核评价内容（满分50分）', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['课程目标', '考核内容', '分值'],
              data: [
                ['课程目标1', '期末项目', '10'],
                ['课程目标2', '小组评价', '20'],
                ['课程目标3', '个人考核', '30'],
                ['课程目标4', '答辩', '40'],
                ['合计', '—', '50'],
              ],
            ),
            pw.SizedBox(height: 16),

            // ═══ 三、达成度计算（对齐 DOCX 表5）═══
            pw.Text('三、达成度计算（定量评价）', style: headerStyle),
            pw.SizedBox(height: 4),
            pw.Text('计算公式：达成度 = 班级平均分 ÷ 满分；课程目标达成度 = Σ(达成度 × 环节权重)',
                style:
                    baseStyle.copyWith(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),

            pw.Text('1. 课程目标达成度计算', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            // 达成度计算表（4目标 × 3环节 = 12行）
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle.copyWith(fontSize: 7),
              cellStyle: baseStyle.copyWith(fontSize: 7),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: [
                '课程目标',
                '权重',
                '评价环节',
                '满分',
                '平均分',
                '达成度',
                '环节权重',
                '目标达成度',
                '指标点',
                '指标点达成度'
              ],
              data: [
                for (int i = 0; i < 4; i++)
                  for (int j = 0; j < 3; j++) ...[
                    [
                      j == 0 ? '课程目标${i + 1}' : '',
                      j == 0 ? _objectiveWeights[i].toStringAsFixed(2) : '',
                      ['平时成绩', '实验成绩', '期末成绩'][j],
                      ['20', '30', '50'][j],
                      (i == 2 && j == 0)
                          ? '—'
                          : (([pingshiAvg, experimentAvg, examAvg][j]
                                          ['obj${i + 1}'] ??
                                      0.0) *
                                  [20, 30, 50][j])
                              .toDouble()
                              .toStringAsFixed(2),
                      (i == 2 && j == 0)
                          ? '—'
                          : ([pingshiAvg, experimentAvg, examAvg][j]
                                      ['obj${i + 1}'] ??
                                  0.0)
                              .toStringAsFixed(4),
                      ['0.2', '0.3', '0.5'][j],
                      j == 0
                          ? (combinedAvg['obj${i + 1}'] ?? 0).toStringAsFixed(4)
                          : '',
                      j == 0 ? '指标点${['1.4', '3.2', '4.2', '5.1'][i]}' : '',
                      j == 0
                          ? (combinedAvg['obj${i + 1}'] ?? 0).toStringAsFixed(4)
                          : '',
                    ],
                  ],
              ],
            ),
            pw.SizedBox(height: 10),

            // 达成度汇总
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['项目', '达成度', '预期阈值', '是否达成'],
              data: [
                for (int i = 0; i < 4; i++)
                  [
                    '课程目标${i + 1}（权重${(_objectiveWeights[i] * 100).toStringAsFixed(0)}%）',
                    _objectiveAchievements[i].toStringAsFixed(4),
                    '0.60',
                    _objectiveAchievements[i] >= 0.60 ? '达成' : '未达成',
                  ],
                [
                  '课程总体达成度',
                  _weightedAchievement.toStringAsFixed(4),
                  '0.60',
                  _weightedAchievement >= 0.60 ? '达成' : '未达成'
                ],
              ],
            ),
            pw.SizedBox(height: 12),

            // 成绩统计
            pw.Text('2. 成绩统计', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            if (_statistics.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headerStyle: boldStyle,
                cellStyle: baseStyle,
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                headers: ['统计指标', '目标1', '目标2', '目标3', '目标4'],
                data: ['平均分', '最高分', '最低分', '标准差'].asMap().entries.map((e) {
                  return [
                    e.value,
                    for (int i = 0; i < 4; i++)
                      (_statistics['objective${i + 1}']?[e.key] ?? 0)
                          .toStringAsFixed(2),
                  ];
                }).toList(),
              ),
            pw.SizedBox(height: 12),

            // 学生个体达成
            pw.Text('3. 学生个体达成情况', style: subHeaderStyle),
            pw.SizedBox(height: 4),
            pw.Text('共有 ${scores.length} 名学生参与评价。', style: baseStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle.copyWith(fontSize: 7),
              cellStyle: baseStyle.copyWith(fontSize: 7),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headers: [
                '序号',
                '学号',
                '姓名',
                '目标1达成度',
                '目标2达成度',
                '目标3达成度',
                '目标4达成度',
                '综合达成度'
              ],
              data: scores.asMap().entries.map((e) {
                final s = e.value;
                final a1 = (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
                final a2 = (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
                final a3 = (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
                final a4 = (s['obj4_achievement'] as num?)?.toDouble() ?? 0;
                final wt = a1 * _objectiveWeights[0] +
                    a2 * _objectiveWeights[1] +
                    a3 * _objectiveWeights[2] +
                    a4 * _objectiveWeights[3];
                return [
                  '${e.key + 1}',
                  s['student_id']?.toString() ?? '',
                  s['student_name']?.toString() ?? '',
                  a1.toStringAsFixed(4),
                  a2.toStringAsFixed(4),
                  a3.toStringAsFixed(4),
                  a4.toStringAsFixed(4),
                  wt.toStringAsFixed(4),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 16),

            // ═══ 四、达成结果分析（对齐 DOCX 表6）═══
            pw.Text('四、达成结果分析', style: headerStyle),
            pw.SizedBox(height: 8),

            pw.Text('1. 定量评价情况分析', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            ...List.generate(4, (i) {
              final a = _objectiveAchievements[i];
              final pA = pingshiAvg['obj${i + 1}'] ?? 0;
              final eA = experimentAvg['obj${i + 1}'] ?? 0;
              final xA = examAvg['obj${i + 1}'] ?? 0;
              final perf = a >= 0.85
                  ? '优秀，学生整体掌握良好'
                  : a >= 0.70
                      ? '良好，大部分学生达到预期'
                      : a >= 0.60
                          ? '达标但有提升空间'
                          : '未达标，需要重点关注和改进';
              final lowCount = scores.where((s) {
                final ach =
                    (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
                return ach < 0.6;
              }).length;
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('课程目标${i + 1}（达成度：${a.toStringAsFixed(4)}，$perf）',
                      style: boldStyle),
                  pw.SizedBox(height: 3),
                  if (i != 2)
                    pw.Text('  平时环节达成度：${pA.toStringAsFixed(4)}',
                        style: baseStyle),
                  pw.Text('  实验环节达成度：${eA.toStringAsFixed(4)}',
                      style: baseStyle),
                  pw.Text('  期末环节达成度：${xA.toStringAsFixed(4)}',
                      style: baseStyle),
                  if (a < 0.60)
                    pw.Text('  低于预期阈值0.60，建议增加该方向的教学课时和实践练习。',
                        style: baseStyle.copyWith(color: PdfColors.red)),
                  if (lowCount > 0)
                    pw.Text('  有 $lowCount 名学生该目标达成度低于0.60，需个别辅导。',
                        style: baseStyle),
                  pw.SizedBox(height: 6),
                ],
              );
            }),
            pw.SizedBox(height: 8),

            pw.Text('2. 定性评价情况分析', style: subHeaderStyle),
            pw.SizedBox(height: 4),
            if (hasSurvey)
              pw.Text(
                '共回收有效问卷 $totalResp 份，综合满意度为 ${(overallSat * 100).toStringAsFixed(1)}%。',
                style: baseStyle,
              )
            else ...[
              pw.Text('从评价结果可以看出：', style: baseStyle),
              pw.SizedBox(height: 2),
              pw.Text('1. 混合开发框架版本更新较快，学生对新特性掌握不及时', style: baseStyle),
              pw.Text('2. 华为多端开发工具操作复杂度较高，实验课时不足导致实操能力薄弱', style: baseStyle),
              pw.Text('3. 期末项目考核中跨设备适配场景设计占比过高，学生在多终端兼容性调试方面失分较多',
                  style: baseStyle),
              pw.Text('4. 本课程在过程性考核中增加了AI工具应用能力的评分项，标准较上届更为严格',
                  style: baseStyle),
            ],
            pw.SizedBox(height: 12),

            pw.Text('3. 教学持续改进', style: subHeaderStyle),
            pw.SizedBox(height: 4),
            pw.Text('本轮教学改进措施执行情况：', style: boldStyle),
            pw.SizedBox(height: 2),
            pw.Text('(1) 在平时作业中加大与课程目标相关的分析应用问题的题目训练', style: baseStyle),
            pw.Text('(2) 在每一章结束后增加知识图谱创建和英文文献阅读培训', style: baseStyle),
            pw.Text('(3) 调整平时、实验以及期末的课程成绩比例，增加实验成绩比例', style: baseStyle),
            pw.SizedBox(height: 6),
            pw.Text('后续教学持续改进措施：', style: boldStyle),
            pw.SizedBox(height: 2),
            ...List.generate(4, (i) {
              final a = _objectiveAchievements[i];
              String suggestion;
              if (a < 0.60) {
                suggestion = '大幅增加相关课时和实践环节，增设单元测验，对低分学生进行一对一辅导。';
              } else if (a < 0.70) {
                suggestion = '加大跨平台开发方案的对比分析训练，增加知识图谱创建，补充测验题目。';
              } else {
                suggestion = '保持现有教学节奏，适当提高考核难度，培养学生创新能力。';
              }
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(
                  '${i + 1}. 课程目标${i + 1}（${a.toStringAsFixed(4)}）：$suggestion',
                  style: baseStyle,
                ),
              );
            }),
            pw.SizedBox(height: 30),

            // 签字栏
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('评价教师签字：____________', style: baseStyle),
                pw.Text('日期：$dateStr', style: baseStyle),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('教研室主任签字：____________', style: baseStyle),
                pw.Text('日期：____________', style: baseStyle),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 4),
            pw.Text('报告由知识图谱教学系统自动生成  $dateStr',
                style:
                    baseStyle.copyWith(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      );

      // 使用 printing 包进行分享/打印/保存
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: '$className《$courseName》课程达成度评价报告.pdf',
      );

      if (mounted) {
        setState(() => _generatingReport = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generatingReport = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出PDF失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportDynamicPdfReport({
    required String courseName,
    required String className,
    required String semester,
    required String dateStr,
    required List<Map<String, dynamic>> scores,
    required AchievementConfig config,
    required Map<String, dynamic> combined,
    required List<Map<String, double>> envWeightsByObjective,
  }) async {
    pw.Font? chineseFont;
    pw.Font? chineseBoldFont;
    try {
      chineseFont = await PdfGoogleFonts.notoSansSCRegular();
      chineseBoldFont = await PdfGoogleFonts.notoSansSCBold();
    } catch (e, st) {
      swallowDebug(e, tag: 'ReportTab.dynamicPdfFonts', stack: st);
      try {
        final fontData = await rootBundle.load('assets/fonts/msyh.ttc');
        chineseFont = pw.Font.ttf(fontData);
        chineseBoldFont = chineseFont;
      } catch (_) {}
    }
    final theme = chineseFont != null
        ? pw.ThemeData.withFont(
            base: chineseFont, bold: chineseBoldFont ?? chineseFont)
        : null;
    final pdf = pw.Document(theme: theme);
    final base = chineseFont != null
        ? pw.TextStyle(font: chineseFont, fontSize: 10)
        : const pw.TextStyle(fontSize: 10);
    final bold =
        base.copyWith(font: chineseBoldFont, fontWeight: pw.FontWeight.bold);
    final header = bold.copyWith(fontSize: 14);
    final title = bold.copyWith(fontSize: 18);
    final activeObjectives = [
      for (var i = 0; i < 4; i++)
        if (_objectiveWeights[i] > 0 || config.fullMarks[i] > 0) i
    ];
    final envLabels = {
      'pingshi': '平时成绩',
      'experiment': '实验成绩',
      'exam': '考核成绩',
    };
    final envSources = {
      'pingshi': combined['pingshi'] as Map? ?? {},
      'experiment': combined['experiment'] as Map? ?? {},
      'exam': combined['exam'] as Map? ?? {},
    };
    Map<String, double> weightsFor(int i) =>
        i < envWeightsByObjective.length ? envWeightsByObjective[i] : const {};

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Center(
            child: pw.Text('$className《$courseName》课程目标达成评价报告', style: title)),
        pw.SizedBox(height: 12),
        pw.Text('一、基本信息', style: header),
        pw.TableHelper.fromTextArray(
          headerStyle: bold,
          cellStyle: base,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headers: ['项目', '内容', '项目', '内容'],
          data: [
            ['课程名称', courseName, '授课班级', className],
            ['开课学期', semester, '评价日期', dateStr],
            ['学生人数', '${scores.length}', '达成阈值', '0.60'],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('二、课程目标与考核项', style: header),
        pw.TableHelper.fromTextArray(
          headerStyle: bold.copyWith(fontSize: 8),
          cellStyle: base.copyWith(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headers: ['课程目标', '指标点', '权重', '满分', '考核项'],
          data: [
            for (final i in activeObjectives)
              [
                '课程目标${i + 1}',
                config.indicators[i],
                _objectiveWeights[i].toStringAsFixed(2),
                config.fullMarks[i].toStringAsFixed(0),
                [
                  for (final env in ['pingshi', 'experiment', 'exam'])
                    if ((weightsFor(i)[env] ?? 0) > 0)
                      '${envLabels[env]} ${(weightsFor(i)[env]! * 100).toStringAsFixed(0)}%'
                ].join('；'),
              ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('三、课程目标达成度', style: header),
        pw.TableHelper.fromTextArray(
          headerStyle: bold.copyWith(fontSize: 8),
          cellStyle: base.copyWith(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headers: ['课程目标', '评价环节', '比例', '环节达成度', '目标达成度'],
          data: [
            for (final i in activeObjectives)
              for (final env in ['pingshi', 'experiment', 'exam'])
                if ((weightsFor(i)[env] ?? 0) > 0)
                  [
                    '课程目标${i + 1}',
                    envLabels[env],
                    '${((weightsFor(i)[env] ?? 0) * 100).toStringAsFixed(0)}%',
                    ((envSources[env]?['obj${i + 1}'] as num?)?.toDouble() ?? 0)
                        .toStringAsFixed(4),
                    _objectiveAchievements[i].toStringAsFixed(4),
                  ],
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text('课程总体目标达成度：${_weightedAchievement.toStringAsFixed(4)}',
            style: bold),
        pw.SizedBox(height: 12),
        pw.Text('四、学生个体达成度', style: header),
        pw.TableHelper.fromTextArray(
          headerStyle: bold.copyWith(fontSize: 7),
          cellStyle: base.copyWith(fontSize: 7),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headers: [
            '序号',
            '学号',
            '姓名',
            for (final i in activeObjectives) '目标${i + 1}',
            '综合',
          ],
          data: scores.asMap().entries.map((entry) {
            final s = entry.value;
            var weighted = 0.0;
            final values = <String>[];
            for (final i in activeObjectives) {
              final ach =
                  (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
              weighted += ach * _objectiveWeights[i];
              values.add(ach.toStringAsFixed(4));
            }
            return [
              '${entry.key + 1}',
              s['student_id']?.toString() ?? '',
              s['student_name']?.toString() ?? '',
              ...values,
              weighted.toStringAsFixed(4),
            ];
          }).toList(),
        ),
      ],
    ));

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '$className《$courseName》课程达成度评价报告.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBatches) {
      return const Center(child: CircularProgressIndicator());
    }

    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 批次选择
          _buildBatchSelector(primary),
          const SizedBox(height: 16),

          // 操作按钮组
          _buildActionButtons(primary),
          const SizedBox(height: 16),

          // 计算中提示
          if (_calculating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在计算达成度...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),

          // 计算结果面板
          if (_calcResults != null && !_calculating) ...[
            _buildResultsPanel(primary),
            const SizedBox(height: 16),
            _buildStatisticsTable(primary),
          ],

          // 空状态
          if (_calcResults == null && !_calculating)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bar_chart,
                        size: 80, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text(
                      '选择批次后点击"生成报告"查看结果',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBatchSelector(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: _selectedBatchId,
          hint: const Text('选择批次'),
          items: _batches.map((b) {
            return DropdownMenuItem<int>(
              value: b['id'] as int,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor(b['status'] as String?),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(b['batch_name'] ?? '未命名'),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            setState(() {
              _selectedBatchId = v;
              _calcResults = null;
            });
            // 切换批次时重新加载该课程的配置
            if (v != null) {
              final batch =
                  _batches.firstWhere((b) => b['id'] == v, orElse: () => {});
              final cn = batch['course_name']?.toString();
              if (cn != null && cn.isNotEmpty) _loadConfig(cn);
            }
          },
        ),
      ),
    );
  }

  Widget _buildActionButtons(Color primary) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _calculating ? null : _calculateAchievement,
          icon: _calculating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(_calculating ? '生成中...' : '生成报告'),
        ),
        OutlinedButton.icon(
          onPressed: (_calcResults != null && !_generatingReport)
              ? _generateMarkdownReport
              : null,
          icon: _generatingReport
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.description_outlined, size: 18),
          label: const Text('生成Markdown报告'),
        ),
        OutlinedButton.icon(
          onPressed: (_calcResults != null && !_generatingReport)
              ? _exportReport
              : null,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('导出PDF报告'),
        ),
        OutlinedButton.icon(
          onPressed:
              (_calcResults != null && !_generatingReport) ? _exportDocx : null,
          icon: const Icon(Icons.description, size: 18),
          label: const Text('导出Word报告'),
        ),
        OutlinedButton.icon(
          onPressed: (_calcResults != null && !_generatingReport)
              ? _exportExcel
              : null,
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('导出Excel结果'),
        ),
      ],
    );
  }

  Widget _buildResultsPanel(Color primary) {
    final activeObjectives = _activeObjectiveIndexes;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  '达成度计算结果',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_calcResults!['student_count']}人',
                    style: TextStyle(
                        fontSize: 12,
                        color: primary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            for (final i in activeObjectives)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildAchievementBar(
                  label: kObjectiveNames[i],
                  value: _objectiveAchievements[i],
                  weight: _objectiveWeights[i],
                  color: kObjectiveColors[i],
                ),
              ),

            // 分割线
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              height: 1,
              color: Colors.grey.withValues(alpha: 0.2),
            ),

            // 加权总达成度
            _buildAchievementBar(
              label: '加权总达成度',
              value: _weightedAchievement,
              weight: 1.0,
              color: primary,
              isBold: true,
            ),

            const SizedBox(height: 16),

            // 达成等级徽章
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      achievementLevelColor(_weightedAchievement)
                          .withValues(alpha: 0.15),
                      achievementLevelColor(_weightedAchievement)
                          .withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: achievementLevelColor(_weightedAchievement)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _weightedAchievement >= 0.7
                          ? Icons.emoji_events
                          : Icons.info_outline,
                      color: achievementLevelColor(_weightedAchievement),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '达成等级：${achievementLevel(_weightedAchievement)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: achievementLevelColor(_weightedAchievement),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${(_weightedAchievement * 100).toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontSize: 14,
                        color: achievementLevelColor(_weightedAchievement),
                      ),
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

  Widget _buildAchievementBar({
    required String label,
    required double value,
    required double weight,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isBold ? 14 : 13,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (!isBold) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '权重${(weight * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        height: isBold ? 24 : 20,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(isBold ? 6 : 4),
                        ),
                      ),
                      Container(
                        height: isBold ? 24 : 20,
                        width: constraints.maxWidth * value.clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.8),
                              color.withValues(alpha: 0.5),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(isBold ? 6 : 4),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 55,
              child: Text(
                '${(value * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: isBold ? 15 : 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatisticsTable(Color primary) {
    if (_statistics.isEmpty) return const SizedBox.shrink();
    final activeObjectives = _activeObjectiveIndexes;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart, color: primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  '成绩统计分析',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 表头
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: const Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text('课程目标',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13))),
                  Expanded(
                      flex: 2,
                      child: Text('平均分',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text('最高分',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text('最低分',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text('标准差',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                          textAlign: TextAlign.center)),
                ],
              ),
            ),
            // 数据行
            for (final i in activeObjectives)
              if (_statistics['objective${i + 1}'] != null)
                _buildStatisticsRow(
                  i,
                  _statistics['objective${i + 1}']!,
                  i == activeObjectives.last,
                ),

            // 底部圆角
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.04),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
            ),

            const SizedBox(height: 16),

            // 各目标达成度对比迷你图
            const Text(
              '目标达成度对比',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: activeObjectives.map((i) {
                final achievement = _objectiveAchievements[i];
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                        right: i == activeObjectives.last ? 0 : 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kObjectiveColors[i].withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: kObjectiveColors[i].withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '目标${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: kObjectiveColors[i],
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: achievement.clamp(0.0, 1.0),
                                strokeWidth: 4,
                                backgroundColor: Colors.grey.withValues(alpha: 0.15),
                                color: kObjectiveColors[i],
                              ),
                              Text(
                                '${(achievement * 100).toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: kObjectiveColors[i],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: achievementLevelColor(achievement)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            achievementLevel(achievement),
                            style: TextStyle(
                              fontSize: 9,
                              color: achievementLevelColor(achievement),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsRow(int i, List<double> s, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: i.isEven ? Colors.transparent : Colors.grey.withValues(alpha: 0.04),
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: kObjectiveColors[i],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(kObjectiveNames[i], style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              s[0].toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              s[1].toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.green),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              s[2].toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.red),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              s[3].toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 报告预览对话框
// ══════════════════════════════════════════════════════════════════════════════

class ReportPreviewDialog extends StatefulWidget {
  final String reportText;
  const ReportPreviewDialog({super.key, required this.reportText});

  @override
  State<ReportPreviewDialog> createState() => _ReportPreviewDialogState();
}

class _ReportPreviewDialogState extends State<ReportPreviewDialog> {
  bool _showSource = false;
  bool _exporting = false;
  late final TextEditingController _editCtrl =
      TextEditingController(text: widget.reportText);

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportEditedDocx() async {
    setState(() => _exporting = true);
    try {
      final bytes = NativeDocxService.instance.markdownToDocx(_editCtrl.text);
      final dir = await OutputPathService.getOutputDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-')
          .substring(0, 19);
      final file = File('${dir.path}/达成度报告_$ts.docx');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Word 已导出：${file.path}'),
              duration: const Duration(seconds: 4)),
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ReportPreview.exportDocx', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出 Word 失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.description, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('课程达成度评价报告',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  // 渲染/编辑切换
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false,
                          label: Text('预览'),
                          icon: Icon(Icons.visibility, size: 16)),
                      ButtonSegment(
                          value: true,
                          label: Text('编辑'),
                          icon: Icon(Icons.edit, size: 16)),
                    ],
                    selected: {_showSource},
                    onSelectionChanged: (v) =>
                        setState(() => _showSource = v.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: '复制到剪贴板',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _editCtrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('报告已复制到剪贴板'),
                            backgroundColor: Colors.green),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            // 内容区域：编辑模式可改 markdown，预览模式渲染编辑后的文本
            Expanded(
              child: _showSource
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _editCtrl,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                            fontSize: 13, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey.withValues(alpha: 0.06),
                          hintText: '编辑 Markdown 源码，切回「预览」查看效果，导出 Word 使用此处内容',
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: MarkdownBubble(content: _editCtrl.text),
                    ),
            ),
            // 底部操作栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _editCtrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('报告已复制到剪贴板'),
                            backgroundColor: Colors.green),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _exporting ? null : _exportEditedDocx,
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_download, size: 16),
                    label: const Text('导出 Word'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
