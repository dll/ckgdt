import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'achievement_config.dart';

/// 达成度模块共享常量与工具函数

const kObjectiveColors = [Colors.red, Colors.blue, Colors.green, Colors.orange];
List<String> get kObjectiveNames => AchievementConfig.defaults.objectiveNames;
List<double> get kDefaultWeights => AchievementConfig.defaults.weights;

Color statusColor(String? status) {
  switch (status) {
    case 'completed':
      return Colors.green;
    case 'in_progress':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}

String statusLabel(String? status) {
  switch (status) {
    case 'completed':
      return '已完成';
    case 'in_progress':
      return '进行中';
    default:
      return '草稿';
  }
}

String achievementLevel(double value) {
  if (value >= 0.85) return '优秀';
  if (value >= 0.70) return '良好';
  if (value >= 0.60) return '中等';
  return '未达成';
}

Color achievementLevelColor(double value) {
  if (value >= 0.85) return Colors.green;
  if (value >= 0.70) return Colors.blue;
  if (value >= 0.60) return Colors.orange;
  return Colors.red;
}

/// 学生成绩排序方式（三个达成 tab 与成绩管理共用）。
enum ScoreSort { idAsc, totalDesc, totalAsc }

String scoreSortLabel(ScoreSort s) {
  switch (s) {
    case ScoreSort.idAsc:
      return '按学号';
    case ScoreSort.totalDesc:
      return '总评降序';
    case ScoreSort.totalAsc:
      return '总评升序';
  }
}

/// 对成绩列表按 [sort] 原地排序。totalKey 默认 'total_score'。
void sortScoresInPlace(List<Map<String, dynamic>> scores, ScoreSort sort,
    {String totalKey = 'total_score'}) {
  double t(Map<String, dynamic> s) => (s[totalKey] as num?)?.toDouble() ?? 0;
  String id(Map<String, dynamic> s) => (s['student_id'] ?? '').toString();
  switch (sort) {
    case ScoreSort.idAsc:
      scores.sort((a, b) => id(a).compareTo(id(b)));
      break;
    case ScoreSort.totalDesc:
      scores.sort((a, b) => t(b).compareTo(t(a)));
      break;
    case ScoreSort.totalAsc:
      scores.sort((a, b) => t(a).compareTo(t(b)));
      break;
  }
}

/// 4 个课程目标达成度雷达图。[values] 为 obj1..4 达成度（0..1）。
/// 三个达成 tab（平时/实验/考核）共用，避免重复构建。
Widget objectiveRadarChart(List<double> values, Color color, {double size = 180}) {
  final v = List<double>.generate(4, (i) => i < values.length ? values[i].clamp(0.0, 1.0) : 0.0);
  return SizedBox(
    height: size,
    child: RadarChart(
      RadarChartData(
        radarShape: RadarShape.polygon,
        tickCount: 4,
        ticksTextStyle: const TextStyle(fontSize: 0, color: Colors.transparent),
        radarBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        gridBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        tickBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        titlePositionPercentageOffset: 0.15,
        getTitle: (index, angle) => RadarChartTitle(
          text: index < kObjectiveNames.length ? kObjectiveNames[index] : '目标${index + 1}',
        ),
        dataSets: [
          RadarDataSet(
            fillColor: color.withValues(alpha: 0.2),
            borderColor: color,
            borderWidth: 2,
            entryRadius: 3,
            dataEntries: [for (final x in v) RadarEntry(value: x)],
          ),
        ],
      ),
    ),
  );
}
