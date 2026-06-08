import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../data/local/achievement_dao.dart';
import '../../../../services/achievement/achievement_docx_service.dart';
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
  double _weightedAchievement = 0.0;
  Map<String, List<double>> _statistics = {}; // objectiveKey -> [mean, max, min, std]
  Map<String, dynamic>? _surveySummary;

  @override
  void initState() {
    super.initState();
    _loadBatches();
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
      final scores = await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
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

      // 使用与 DAO addScore() 一致的满分比计算达成度
      const fullMarks = [15.0, 25.0, 30.0, 30.0];
      final objAchievements = List<double>.generate(4, (i) {
        final values = objScores[i];
        final mean = values.reduce((a, b) => a + b) / values.length;
        return (mean / fullMarks[i]).clamp(0.0, 1.0);
      });

      // 加权达成度
      double weighted = 0;
      for (int i = 0; i < 4; i++) {
        weighted += objAchievements[i] * kDefaultWeights[i];
      }

      // 统计数据：mean, max, min, std
      final stats = <String, List<double>>{};
      for (int i = 0; i < 4; i++) {
        final List<double> values = objScores[i];
        final mean = values.reduce((a, b) => a + b) / values.length;
        final maxVal = values.reduce(max<double>);
        final minVal = values.reduce(min<double>);
        final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
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
      await widget.achievementDao.updateBatchStatus(_selectedBatchId!, 'completed');

      // 加载问卷满意度数据
      Map<String, dynamic>? surveyData;
      try {
        surveyData =
            await widget.achievementDao.getSurveySatisfactionSummary();
      } catch (e, st) {
        swallowDebug(e, tag: 'ReportTab.surveySatisfaction', stack: st);
      }

      if (mounted) {
        setState(() {
          _objectiveAchievements = objAchievements;
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
        const SnackBar(content: Text('请先计算达成度')),
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
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final courseName = batch['course_name'] ?? '移动应用开发';
      final className = batch['class_name'] ?? '软件23';
      final semester = batch['semester'] ?? '-';
      final teacherId = batch['teacher_id'] ?? '';

      // 获取三类评价分项达成度（班级平均）
      final combined = await widget.achievementDao.calculateCombinedAchievement(_selectedBatchId!);
      final pingshiAvg = combined['pingshi'] as Map<String, double>;
      final experimentAvg = combined['experiment'] as Map<String, double>;
      final examAvg = combined['exam'] as Map<String, double>;
      final combinedAvg = combined['combined'] as Map<String, double>;

      // 获取学生个体成绩
      final scores = await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      final studentCount = scores.length;

      final buffer = StringBuffer();
      const objDescFull = [
        '掌握移动应用开发技术体系及主流平台特性，理解技术选型逻辑，熟悉跨平台开发框架和AI编程工具的基本使用',
        '运用跨平台开发框架及小程序技术，结合AI编程工具与后端API交互，设计实现跨平台应用，具备需求建模与创新应用能力',
        '调研对比多端开发方案，分析不同技术栈在跨设备适配场景中的优劣，具备技术方案评估与选型能力',
        '遵循软件工程规范，使用现代开发工具完成应用测试与优化，具备工程实践能力',
      ];
      const objIndicators = ['1.4', '3.2', '4.2', '5.1'];
      const objAssessContent = [
        '课堂表现、实验1-2、期末项目',
        '期间测验、实验3-4、小组评价',
        '实验5-6、个人考核',
        '课外学习、实验7、答辩',
      ];
      const objMarks = [10, 20, 30, 40];
      // 各评价环节满分与权重（对齐 DOCX 表5）
      const assessNames = ['平时成绩', '实验成绩', '期末成绩'];
      const assessFullMarks = [20, 30, 50];
      const assessWeights = [0.2, 0.3, 0.5];

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
      for (int i = 0; i < 4; i++) {
        buffer.writeln('| 指标点${objIndicators[i]} | ${kObjectiveNames[i]} | ${kDefaultWeights[i].toStringAsFixed(2)} | ${objDescFull[i]} |');
      }
      buffer.writeln();

      buffer.writeln('### 3. 评价方式及成绩评定对照表');
      buffer.writeln();
      buffer.writeln('| 课程目标 | 权重 | 支撑指标点 | 平时成绩（${assessFullMarks[0]}分） | 实验成绩（${assessFullMarks[1]}分） | 期末成绩（${assessFullMarks[2]}分） |');
      buffer.writeln('|----------|------|-----------|-----------------|-----------------|-----------------|');
      for (int i = 0; i < 4; i++) {
        buffer.writeln('| ${kObjectiveNames[i]} | ${kDefaultWeights[i].toStringAsFixed(2)} | 指标点${objIndicators[i]} | ${objMarks[i]} | ${objMarks[i]} | ${objMarks[i]} |');
      }
      buffer.writeln('| **合计** | **1.00** | — | **${assessFullMarks[0]}** | **${assessFullMarks[1]}** | **${assessFullMarks[2]}** |');
      buffer.writeln();

      // ══════════════════════════════════════════════════
      // 二、课程考核标准（对齐 DOCX 表2 + 表3 + 表4）
      // ══════════════════════════════════════════════════
      buffer.writeln('## 二、课程考核标准');
      buffer.writeln();

      buffer.writeln('### 1. 平时成绩评价标准（满分${assessFullMarks[0]}分）');
      buffer.writeln();
      buffer.writeln('| 课程目标 | 考核内容 | 优秀（90-100%） | 良好（70-89%） | 合格（60-69%） | 不合格（0-59%） |');
      buffer.writeln('|----------|---------|----------------|---------------|---------------|----------------|');
      for (int i = 0; i < 4; i++) {
        if (i == 2) continue; // 课程目标3无平时考核
        final content = objAssessContent[i].split('、').first;
        buffer.writeln('| ${kObjectiveNames[i]} | $content | 全面掌握，表现突出 | 较好掌握，表现良好 | 基本掌握，表现一般 | 未能掌握，需要改进 |');
      }
      buffer.writeln();

      buffer.writeln('### 2. 实验成绩评价标准（满分${assessFullMarks[1]}分）');
      buffer.writeln();
      buffer.writeln('| 课程目标 | 考核内容 | 优秀（90-100%） | 良好（70-89%） | 合格（60-69%） | 不合格（0-59%） |');
      buffer.writeln('|----------|---------|----------------|---------------|---------------|----------------|');
      for (int i = 0; i < 4; i++) {
        final parts = objAssessContent[i].split('、');
        final expItem = parts.length > 1 ? parts[1] : parts[0];
        buffer.writeln('| ${kObjectiveNames[i]} | $expItem | 独立完成，结果正确 | 基本完成，结果较好 | 能够完成，有少量错误 | 无法完成或错误较多 |');
      }
      buffer.writeln();

      buffer.writeln('### 3. 期末考核评价内容（满分${assessFullMarks[2]}分）');
      buffer.writeln();
      buffer.writeln('| 课程目标 | 考核内容 | 分值 |');
      buffer.writeln('|----------|---------|------|');
      for (int i = 0; i < 4; i++) {
        final examContent = objAssessContent[i].split('、').last;
        buffer.writeln('| ${kObjectiveNames[i]} | $examContent | ${objMarks[i]} |');
      }
      buffer.writeln('| **合计** | — | **${assessFullMarks[2]}** |');
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
      buffer.writeln('| 课程目标 | 权重 | 评价环节 | 满分 | 班级平均分 | 达成度 | 环节权重 | 课程目标达成度 | 支撑指标点 | 指标点达成度 |');
      buffer.writeln('|----------|------|---------|------|-----------|--------|---------|--------------|-----------|------------|');

      final assessMaps = [pingshiAvg, experimentAvg, examAvg];
      for (int i = 0; i < 4; i++) {
        final objCombined = combinedAvg['obj${i + 1}'] ?? 0;
        for (int j = 0; j < 3; j++) {
          final isFirstRow = j == 0;
          if (i == 2 && j == 0) {
            // 课程目标3无平时成绩
            buffer.writeln('| ${isFirstRow ? kObjectiveNames[i] : ''} | ${isFirstRow ? kDefaultWeights[i].toStringAsFixed(2) : ''} | ${assessNames[j]} | ${assessFullMarks[j]} | — | — | ${assessWeights[j]} | ${isFirstRow ? objCombined.toStringAsFixed(4) : ''} | ${isFirstRow ? '指标点${objIndicators[i]}' : ''} | ${isFirstRow ? objCombined.toStringAsFixed(4) : ''} |');
            continue;
          }
          final ach = assessMaps[j]['obj${i + 1}'] ?? 0.0;
          final avgScore = ach * assessFullMarks[j];
          buffer.writeln('| ${isFirstRow ? kObjectiveNames[i] : ''} | ${isFirstRow ? kDefaultWeights[i].toStringAsFixed(2) : ''} | ${assessNames[j]} | ${assessFullMarks[j]} | ${avgScore.toStringAsFixed(2)} | ${ach.toStringAsFixed(4)} | ${assessWeights[j]} | ${isFirstRow ? objCombined.toStringAsFixed(4) : ''} | ${isFirstRow ? '指标点${objIndicators[i]}' : ''} | ${isFirstRow ? objCombined.toStringAsFixed(4) : ''} |');
        }
      }
      buffer.writeln();

      // 达成度汇总
      buffer.writeln('| 项目 | 达成度 | 预期阈值 | 是否达成 |');
      buffer.writeln('|------|--------|---------|---------|');
      for (int i = 0; i < 4; i++) {
        final a = _objectiveAchievements[i];
        buffer.writeln('| ${kObjectiveNames[i]}（权重${(kDefaultWeights[i] * 100).toStringAsFixed(0)}%） | ${a.toStringAsFixed(4)} | 0.60 | ${a >= 0.60 ? '达成' : '未达成'} |');
      }
      buffer.writeln('| **课程总体达成度** | **${_weightedAchievement.toStringAsFixed(4)}** | **0.60** | **${_weightedAchievement >= 0.60 ? '达成' : '未达成'}** |');
      buffer.writeln();

      // 成绩统计
      buffer.writeln('### 2. 成绩统计');
      buffer.writeln();
      buffer.writeln('| 统计指标 | 目标1 | 目标2 | 目标3 | 目标4 |');
      buffer.writeln('|----------|-------|-------|-------|-------|');
      for (int idx = 0; idx < 4; idx++) {
        final label = ['平均分', '最高分', '最低分', '标准差'][idx];
        buffer.write('| $label ');
        for (int i = 0; i < 4; i++) {
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
      buffer.writeln('| 序号 | 学号 | 姓名 | 目标1达成度 | 目标2达成度 | 目标3达成度 | 目标4达成度 | 综合达成度 |');
      buffer.writeln('|------|------|------|-----------|-----------|-----------|-----------|-----------|');
      for (int idx = 0; idx < scores.length; idx++) {
        final s = scores[idx];
        final sid = s['student_id']?.toString() ?? '';
        final sname = s['student_name']?.toString() ?? '';
        final a1 = (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
        final a2 = (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
        final a3 = (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
        final a4 = (s['obj4_achievement'] as num?)?.toDouble() ?? 0;
        final wt = a1 * kDefaultWeights[0] + a2 * kDefaultWeights[1] + a3 * kDefaultWeights[2] + a4 * kDefaultWeights[3];
        buffer.writeln('| ${idx + 1} | $sid | $sname | ${a1.toStringAsFixed(4)} | ${a2.toStringAsFixed(4)} | ${a3.toStringAsFixed(4)} | ${a4.toStringAsFixed(4)} | ${wt.toStringAsFixed(4)} |');
      }
      buffer.writeln();

      // ══════════════════════════════════════════════════
      // 四、达成结果分析（对齐 DOCX 表6）
      // ══════════════════════════════════════════════════
      buffer.writeln('## 四、达成结果分析');
      buffer.writeln();

      buffer.writeln('### 1. 定量评价情况分析');
      buffer.writeln();

      const objAnalysisDesc = [
        '课程目标1主要考核学生掌握移动应用开发技术体系（原生/混合/跨平台）及主流平台特性，理解技术选型逻辑。'
            '该目标通过平时课堂表现（20%）、实验1-2（30%）、期末项目（50%）三个环节综合评定。',
        '课程目标2主要考核学生运用跨平台开发框架及小程序技术，结合AI编程工具与后端API交互，设计实现跨平台应用。'
            '该目标通过平时测验（20%）、实验3-4（30%）、期末小组评价（50%）三个环节综合评定。',
        '课程目标3主要考核学生调研对比多端开发方案，分析不同技术栈在跨设备适配场景中的优劣，具备技术方案评估与选型能力。'
            '该目标通过实验5-6（30%）和期末个人考核（50%）两个环节评定（平时无该目标考核项）。',
        '课程目标4主要考核学生遵循软件工程规范，使用现代开发工具完成应用测试与优化，具备工程实践能力。'
            '该目标通过平时课外学习（20%）、实验7（30%）、期末答辩（50%）三个环节综合评定。',
      ];

      for (int i = 0; i < 4; i++) {
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
        buffer.writeln('**${kObjectiveNames[i]}**（达成度：${a.toStringAsFixed(4)}，$perf）');
        buffer.writeln();
        buffer.writeln(objAnalysisDesc[i]);
        buffer.writeln();
        if (i != 2) {
          buffer.writeln('- 平时环节达成度：${pA.toStringAsFixed(4)}');
        }
        buffer.writeln('- 实验环节达成度：${eA.toStringAsFixed(4)}');
        buffer.writeln('- 期末环节达成度：${xA.toStringAsFixed(4)}');
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
        final overallSat = (_surveySummary!['overallSatisfaction'] as double?) ?? 0;
        buffer.writeln('共回收有效问卷 **$totalResp** 份，综合满意度为 **${(overallSat * 100).toStringAsFixed(1)}%**。');
        buffer.writeln();
        final qStats = (_surveySummary!['questionStats'] as List<Map<String, dynamic>>?) ?? [];
        for (final qs in qStats) {
          final question = qs['question'] as String? ?? '';
          buffer.writeln('**$question**');
          if (qs['type'] == 'single_choice') {
            final counts = qs['counts'] as Map<String, int>? ?? {};
            final total = (qs['total'] as int?) ?? 1;
            for (final entry in counts.entries) {
              final pct = total > 0 ? (entry.value / total * 100).toStringAsFixed(1) : '0';
              buffer.writeln('- ${entry.key}：${entry.value}人（$pct%）');
            }
          } else if (qs['type'] == 'rating') {
            buffer.writeln('- 平均评分：${(qs['average'] as double? ?? 0).toStringAsFixed(2)} / 5.0');
          }
          buffer.writeln();
        }
      } else {
        final sortedIdx = List.generate(4, (i) => i)
          ..sort((a, b) => _objectiveAchievements[b].compareTo(_objectiveAchievements[a]));
        buffer.writeln('从评价结果可以看出：');
        buffer.writeln();
        buffer.writeln('- 学生在${kObjectiveNames[sortedIdx[0]]}方面表现最好（${_objectiveAchievements[sortedIdx[0]].toStringAsFixed(4)}）');
        buffer.writeln('- ${kObjectiveNames[sortedIdx[3]]}方面相对较弱（${_objectiveAchievements[sortedIdx[3]].toStringAsFixed(4)}）');
        buffer.writeln();
        buffer.writeln('主要原因可能是：');
        buffer.writeln();
        buffer.writeln('1. 混合开发框架版本更新较快，学生对新特性掌握不及时');
        buffer.writeln('2. 华为多端开发工具（DevEco Studio）操作复杂度较高，实验课时不足导致实操能力薄弱');
        buffer.writeln('3. 期末项目考核中跨设备适配场景设计占比过高，学生在多终端兼容性调试方面失分较多');
        buffer.writeln('4. 本课程在过程性考核中增加了AI工具应用能力的评分项，标准较上届更为严格');
        buffer.writeln();
      }

      buffer.writeln('### 3. 教学持续改进');
      buffer.writeln();
      buffer.writeln('#### 本轮教学改进措施执行情况');
      buffer.writeln();
      buffer.writeln('针对上一轮该课程教学持续改进意见，在本轮教学中持续改进的措施执行情况如下：');
      buffer.writeln();
      buffer.writeln('1. 在平时作业中加大关于运用移动应用开发技术体系分析实际应用问题的题目训练，实现期末考核内容与平时训练内容相一致');
      buffer.writeln('2. 在每一章结束后，在作业中增加与该章知识点相关的英文期刊文献阅读培训，扩展学生的知识面并提高其英文文献的阅读与总结能力');
      buffer.writeln('3. 调整平时、实验以及期末的课程成绩比例，增加实验成绩比例，降低平时和期末的课程比例，注重学生的过程性考核');
      buffer.writeln();
      buffer.writeln('#### 后续教学持续改进措施');
      buffer.writeln();
      buffer.writeln('针对本次课程目标达成评价情况分析，今后教学中拟采取以下改进措施：');
      buffer.writeln();
      for (int i = 0; i < 4; i++) {
        final a = _objectiveAchievements[i];
        if (a < 0.60) {
          buffer.writeln('${i + 1}. **${kObjectiveNames[i]}（${a.toStringAsFixed(4)}，未达标）**：大幅增加相关课时和实践环节，增设单元测验，对低分学生进行一对一辅导');
        } else if (a < 0.70) {
          buffer.writeln('${i + 1}. ${kObjectiveNames[i]}（${a.toStringAsFixed(4)}）：加大跨平台开发方案的对比分析训练，增加知识图谱创建，补充测验题目');
        } else {
          buffer.writeln('${i + 1}. ${kObjectiveNames[i]}（${a.toStringAsFixed(4)}）：保持现有教学节奏，适当提高考核难度，培养学生创新能力');
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

      final objectives = <Map<String, dynamic>>[];
      for (int i = 0; i < 4; i++) {
        objectives.add({
          'objective': i + 1,
          'weight': kDefaultWeights[i],
          'achievement': _objectiveAchievements[i],
          'avgScore': _objectiveAchievements[i] * 100,
        });
      }

      // 从 config（含大纲导入的 course_objectives）构建 syllabus，
      // 修复此前传空 {} 导致 docx 一/二/三表表头空白的 bug。
      final cfg = AchievementConfig.defaults;
      final syllabus = <String, dynamic>{
        'info': <String, String>{
          '英文名称': (batch['course_name'] ?? '移动应用开发').toString(),
          '考核方式': '考查',
          '开课学期': (batch['semester'] ?? '').toString(),
        },
        'objectives': [
          for (int i = 0; i < cfg.objectiveNames.length; i++)
            {
              'num': i + 1,
              'objective': cfg.descriptions[i],
              'requirement': cfg.indicators[i],
            }
        ],
        'weights': [
          for (int i = 0; i < cfg.weights.length; i++)
            {
              'objective': i + 1,
              'weight': cfg.weights[i],
              'pingshi_full': cfg.fullMarks[i].toInt(),
              'experiment_full': cfg.fullMarks[i].toInt(),
              'exam_full': cfg.fullMarks[i].toInt(),
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
        classStats: {
          'studentCount': scores.length,
          'avgTotal': _weightedAchievement * 100,
          'maxTotal': _maxOf(scores, (s) => (s['total_score'] as double?) ?? 0),
          'minTotal': _minOf(scores, (s) => (s['total_score'] as double?) ?? 0),
          'stdDev': _stdDevOf(scores, (s) => (s['total_score'] as double?) ?? 0),
        },
        students: scores,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Word 报告已保存: $path'), duration: const Duration(seconds: 4)),
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

  double _maxOf(List<Map<String, dynamic>> items, double Function(Map<String, dynamic>) getter) {
    if (items.isEmpty) return 0;
    return items.map(getter).reduce((a, b) => a > b ? a : b);
  }

  double _minOf(List<Map<String, dynamic>> items, double Function(Map<String, dynamic>) getter) {
    if (items.isEmpty) return 0;
    return items.map(getter).reduce((a, b) => a < b ? a : b);
  }

  double _stdDevOf(List<Map<String, dynamic>> items, double Function(Map<String, dynamic>) getter) {
    if (items.isEmpty) return 0;
    final values = items.map(getter).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
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
      final scores = await widget.achievementDao.getScoresByBatch(_selectedBatchId!);
      final courseName = batch['course_name'] ?? '移动应用开发';
      final className = batch['class_name'] ?? '软件23';
      final semester = batch['semester'] ?? '-';
      final teacherId = batch['teacher_id'] ?? '';
      final dateStr = DateTime.now().toString().substring(0, 10);

      // 获取三类评价分项达成度
      final combined = await widget.achievementDao.calculateCombinedAchievement(_selectedBatchId!);
      final pingshiAvg = combined['pingshi'] as Map<String, double>;
      final experimentAvg = combined['experiment'] as Map<String, double>;
      final examAvg = combined['exam'] as Map<String, double>;
      final combinedAvg = combined['combined'] as Map<String, double>;

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
          ? pw.ThemeData.withFont(base: chineseFont, bold: chineseBoldFont ?? chineseFont)
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
      final overallSat = (_surveySummary?['overallSatisfaction'] as double?) ?? 0;
      final totalResp = _surveySummary?['totalResponses'] as int? ?? 0;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            // 标题
            pw.Center(child: pw.Text(
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
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
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
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['毕业要求指标点', '课程目标', '权重', '课程目标描述'],
              data: [
                ['指标点1.4', '课程目标1', '0.10', '掌握移动应用开发技术体系及主流平台特性，理解技术选型逻辑'],
                ['指标点3.2', '课程目标2', '0.20', '运用跨平台开发框架及小程序技术，结合AI编程工具设计实现跨平台应用'],
                ['指标点4.2', '课程目标3', '0.30', '调研对比多端开发方案，分析不同技术栈优劣，具备技术方案评估与选型能力'],
                ['指标点5.1', '课程目标4', '0.40', '遵循软件工程规范，使用现代开发工具完成应用测试与优化'],
              ],
            ),
            pw.SizedBox(height: 12),

            pw.Text('3. 评价方式及成绩评定对照表', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['课程目标', '权重', '支撑指标点', '平时成绩(20分)', '实验成绩(30分)', '期末成绩(50分)'],
              data: [
                ['课程目标1', '0.10', '指标点1.4', '10', '10', '10'],
                ['课程目标2', '0.20', '指标点3.2', '20', '20', '20'],
                ['课程目标3', '0.30', '指标点4.2', '30', '30', '30'],
                ['课程目标4', '0.40', '指标点5.1', '40', '40', '40'],
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
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['课程目标', '考核内容', '优秀(90-100%)', '良好(70-89%)', '合格(60-69%)', '不合格(0-59%)'],
              data: [
                ['课程目标1', '课堂表现', '全面掌握，表现突出', '较好掌握，表现良好', '基本掌握，表现一般', '未能掌握，需要改进'],
                ['课程目标2', '期间测验', '全面掌握，表现突出', '较好掌握，表现良好', '基本掌握，表现一般', '未能掌握，需要改进'],
                ['课程目标4', '课外学习', '全面掌握，表现突出', '较好掌握，表现良好', '基本掌握，表现一般', '未能掌握，需要改进'],
              ],
            ),
            pw.SizedBox(height: 10),

            pw.Text('2. 实验成绩评价标准（满分30分）', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle.copyWith(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['课程目标', '考核内容', '优秀(90-100%)', '良好(70-89%)', '合格(60-69%)', '不合格(0-59%)'],
              data: [
                ['课程目标1', '实验1-2', '独立完成，结果正确', '基本完成，结果较好', '能够完成，有少量错误', '无法完成或错误较多'],
                ['课程目标2', '实验3-4', '独立完成，结果正确', '基本完成，结果较好', '能够完成，有少量错误', '无法完成或错误较多'],
                ['课程目标3', '实验5-6', '独立完成，结果正确', '基本完成，结果较好', '能够完成，有少量错误', '无法完成或错误较多'],
                ['课程目标4', '实验7', '独立完成，结果正确', '基本完成，结果较好', '能够完成，有少量错误', '无法完成或错误较多'],
              ],
            ),
            pw.SizedBox(height: 10),

            pw.Text('3. 期末考核评价内容（满分50分）', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
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
                style: baseStyle.copyWith(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),

            pw.Text('1. 课程目标达成度计算', style: subHeaderStyle),
            pw.SizedBox(height: 6),
            // 达成度计算表（4目标 × 3环节 = 12行）
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle.copyWith(fontSize: 7),
              cellStyle: baseStyle.copyWith(fontSize: 7),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['课程目标', '权重', '评价环节', '满分', '平均分', '达成度', '环节权重', '目标达成度', '指标点', '指标点达成度'],
              data: [
                for (int i = 0; i < 4; i++)
                  for (int j = 0; j < 3; j++) ...[
                    [
                      j == 0 ? '课程目标${i + 1}' : '',
                      j == 0 ? kDefaultWeights[i].toStringAsFixed(2) : '',
                      ['平时成绩', '实验成绩', '期末成绩'][j],
                      ['20', '30', '50'][j],
                      (i == 2 && j == 0) ? '—' :
                          (([pingshiAvg, experimentAvg, examAvg][j]['obj${i + 1}'] ?? 0.0) * [20, 30, 50][j]).toDouble().toStringAsFixed(2),
                      (i == 2 && j == 0) ? '—' :
                          ([pingshiAvg, experimentAvg, examAvg][j]['obj${i + 1}'] ?? 0.0).toStringAsFixed(4),
                      ['0.2', '0.3', '0.5'][j],
                      j == 0 ? (combinedAvg['obj${i + 1}'] ?? 0).toStringAsFixed(4) : '',
                      j == 0 ? '指标点${['1.4', '3.2', '4.2', '5.1'][i]}' : '',
                      j == 0 ? (combinedAvg['obj${i + 1}'] ?? 0).toStringAsFixed(4) : '',
                    ],
                  ],
              ],
            ),
            pw.SizedBox(height: 10),

            // 达成度汇总
            pw.TableHelper.fromTextArray(
              headerStyle: boldStyle,
              cellStyle: baseStyle,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['项目', '达成度', '预期阈值', '是否达成'],
              data: [
                for (int i = 0; i < 4; i++) [
                  '课程目标${i + 1}（权重${(kDefaultWeights[i] * 100).toStringAsFixed(0)}%）',
                  _objectiveAchievements[i].toStringAsFixed(4),
                  '0.60',
                  _objectiveAchievements[i] >= 0.60 ? '达成' : '未达成',
                ],
                ['课程总体达成度', _weightedAchievement.toStringAsFixed(4), '0.60',
                  _weightedAchievement >= 0.60 ? '达成' : '未达成'],
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
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                headers: ['统计指标', '目标1', '目标2', '目标3', '目标4'],
                data: ['平均分', '最高分', '最低分', '标准差'].asMap().entries.map((e) {
                  return [
                    e.value,
                    for (int i = 0; i < 4; i++)
                      (_statistics['objective${i + 1}']?[e.key] ?? 0).toStringAsFixed(2),
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
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['序号', '学号', '姓名', '目标1达成度', '目标2达成度', '目标3达成度', '目标4达成度', '综合达成度'],
              data: scores.asMap().entries.map((e) {
                final s = e.value;
                final a1 = (s['obj1_achievement'] as num?)?.toDouble() ?? 0;
                final a2 = (s['obj2_achievement'] as num?)?.toDouble() ?? 0;
                final a3 = (s['obj3_achievement'] as num?)?.toDouble() ?? 0;
                final a4 = (s['obj4_achievement'] as num?)?.toDouble() ?? 0;
                final wt = a1 * kDefaultWeights[0] + a2 * kDefaultWeights[1] + a3 * kDefaultWeights[2] + a4 * kDefaultWeights[3];
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
              final perf = a >= 0.85 ? '优秀，学生整体掌握良好'
                  : a >= 0.70 ? '良好，大部分学生达到预期'
                  : a >= 0.60 ? '达标但有提升空间'
                  : '未达标，需要重点关注和改进';
              final lowCount = scores.where((s) {
                final ach = (s['obj${i + 1}_achievement'] as num?)?.toDouble() ?? 0;
                return ach < 0.6;
              }).length;
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('课程目标${i + 1}（达成度：${a.toStringAsFixed(4)}，$perf）', style: boldStyle),
                  pw.SizedBox(height: 3),
                  if (i != 2)
                    pw.Text('  平时环节达成度：${pA.toStringAsFixed(4)}', style: baseStyle),
                  pw.Text('  实验环节达成度：${eA.toStringAsFixed(4)}', style: baseStyle),
                  pw.Text('  期末环节达成度：${xA.toStringAsFixed(4)}', style: baseStyle),
                  if (a < 0.60)
                    pw.Text('  低于预期阈值0.60，建议增加该方向的教学课时和实践练习。',
                        style: baseStyle.copyWith(color: PdfColors.red)),
                  if (lowCount > 0)
                    pw.Text('  有 $lowCount 名学生该目标达成度低于0.60，需个别辅导。', style: baseStyle),
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
              pw.Text('3. 期末项目考核中跨设备适配场景设计占比过高，学生在多终端兼容性调试方面失分较多', style: baseStyle),
              pw.Text('4. 本课程在过程性考核中增加了AI工具应用能力的评分项，标准较上届更为严格', style: baseStyle),
            ],
            pw.SizedBox(height: 12),

            pw.Text('3. 教学持续改进', style: subHeaderStyle),
            pw.SizedBox(height: 4),
            pw.Text('本轮教学改进措施执行情况：', style: boldStyle),
            pw.SizedBox(height: 2),
            pw.Text('(1) 在平时作业中加大运用移动应用开发技术体系分析实际应用问题的题目训练', style: baseStyle),
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
            pw.Text('报告由知识图谱教学系统自动生成  $dateStr', style: baseStyle.copyWith(fontSize: 8, color: PdfColors.grey600)),
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
                    Icon(Icons.bar_chart, size: 80, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text(
                      '选择批次后点击"计算达成度"查看结果',
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.calculate, size: 18),
          label: Text(_calculating ? '计算中...' : '计算达成度'),
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
          onPressed: (_calcResults != null && !_generatingReport) ? _exportReport : null,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('导出PDF报告'),
        ),
        OutlinedButton.icon(
          onPressed: (_calcResults != null && !_generatingReport) ? _exportDocx : null,
          icon: const Icon(Icons.description, size: 18),
          label: const Text('导出Word报告'),
        ),
      ],
    );
  }

  Widget _buildResultsPanel(Color primary) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_calcResults!['student_count']}人',
                    style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 四个课程目标达成度
            ...List.generate(4, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildAchievementBar(
                  label: kObjectiveNames[i],
                  value: _objectiveAchievements[i],
                  weight: kDefaultWeights[i],
                  color: kObjectiveColors[i],
                ),
              );
            }),

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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      achievementLevelColor(_weightedAchievement).withValues(alpha: 0.15),
                      achievementLevelColor(_weightedAchievement).withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: achievementLevelColor(_weightedAchievement).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _weightedAchievement >= 0.7 ? Icons.emoji_events : Icons.info_outline,
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text('课程目标', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Expanded(flex: 2, child: Text('平均分', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('最高分', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('最低分', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('标准差', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                ],
              ),
            ),
            // 数据行
            ...List.generate(4, (i) {
              final s = _statistics['objective${i + 1}'];
              if (s == null) return const SizedBox.shrink();

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: i.isEven ? Colors.transparent : Colors.grey.withValues(alpha: 0.04),
                  border: i == 3
                      ? null
                      : Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
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
            }),

            // 底部圆角
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.04),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
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
              children: List.generate(4, (i) {
                final achievement = _objectiveAchievements[i];
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
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
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: achievementLevelColor(achievement).withValues(alpha: 0.15),
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
              }),
            ),
          ],
        ),
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
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  // 渲染/源码切换
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('预览'), icon: Icon(Icons.visibility, size: 16)),
                      ButtonSegment(value: true, label: Text('源码'), icon: Icon(Icons.code, size: 16)),
                    ],
                    selected: {_showSource},
                    onSelectionChanged: (v) => setState(() => _showSource = v.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: '复制到剪贴板',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.reportText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('报告已复制到剪贴板'), backgroundColor: Colors.green),
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
            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _showSource
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          widget.reportText,
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                        ),
                      )
                    : MarkdownBubble(content: widget.reportText),
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
                  FilledButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.reportText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('报告已复制到剪贴板'), backgroundColor: Colors.green),
                      );
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制并关闭'),
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
