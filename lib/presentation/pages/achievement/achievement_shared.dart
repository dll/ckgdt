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

/// 达成 tab 表格的一列规格。
/// [label] 表头文字；[get] 从一行取显示值；[isAchievement] 为真则按达成度等级着色，
/// [bold] 加粗（总评列），[headerColor] 表头文字颜色（目标列用对应目标色）。
class ScoreColumn {
  final String label;
  final double Function(Map<String, dynamic> row) get;
  final bool isAchievement;
  final bool bold;
  final int digits;
  final Color? headerColor;
  const ScoreColumn(
    this.label,
    this.get, {
    this.isAchievement = false,
    this.bold = false,
    this.digits = 1,
    this.headerColor,
  });
}

/// 平时/实验/考核三个达成 tab 共用的成绩表，样式对齐「成绩管理」：
/// 圆角描边卡片 + 干净表头 + 隔行底色 + 等宽数字。横向可滚动以容纳多列。
Widget achievementScoreTable(
  BuildContext context, {
  required List<Map<String, dynamic>> rows,
  required List<ScoreColumn> columns,
  Future<void> Function()? onRefresh,
  void Function(Map<String, dynamic> row)? onEdit,
}) {
  final cs = Theme.of(context).colorScheme;
  final onSurface = cs.onSurface;
  final surface = cs.surface;
  final hairline = cs.outline.withValues(alpha: 0.4);
  final primary = cs.primary;

  final headerStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: onSurface,
    letterSpacing: 0.3,
  );
  final cellStyle = TextStyle(
    fontSize: 13,
    color: onSurface.withValues(alpha: 0.85),
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  const idW = 110.0, nameW = 72.0, colW = 78.0, opW = 52.0;

  Widget headerCell(String text, double w, {Color? color}) => SizedBox(
        width: w,
        child: Text(text,
            style: color != null ? headerStyle.copyWith(color: color) : headerStyle,
            textAlign: TextAlign.center),
      );

  final table = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        color: primary.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          SizedBox(width: idW, child: Text('学号', style: headerStyle)),
          SizedBox(width: nameW, child: Text('姓名', style: headerStyle)),
          for (final c in columns) headerCell(c.label, colW, color: c.headerColor),
          if (onEdit != null) SizedBox(width: opW, child: Text('操作', style: headerStyle, textAlign: TextAlign.center)),
        ]),
      ),
      Divider(height: 1, color: hairline),
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: rows.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: hairline.withValues(alpha: 0.5)),
          itemBuilder: (context, index) {
            final r = rows[index];
            return Container(
              color: index.isEven ? surface : primary.withValues(alpha: 0.025),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                SizedBox(width: idW, child: Text(r['student_id']?.toString() ?? '', style: cellStyle)),
                SizedBox(width: nameW, child: Text(r['student_name']?.toString() ?? '', style: cellStyle, overflow: TextOverflow.ellipsis)),
                for (final c in columns)
                  SizedBox(
                    width: colW,
                    child: Text(
                      c.get(r).toStringAsFixed(c.digits),
                      textAlign: TextAlign.center,
                      style: cellStyle.copyWith(
                        color: c.isAchievement ? achievementLevelColor(c.get(r)) : (c.bold ? onSurface : null),
                        fontWeight: (c.bold || c.isAchievement) ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                if (onEdit != null)
                  SizedBox(
                    width: opW,
                    child: IconButton(
                      icon: Icon(Icons.edit_rounded, size: 16, color: primary),
                      onPressed: () => onEdit(r),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: '编辑',
                    ),
                  ),
              ]),
            );
          },
        ),
      ),
    ],
  );

  final card = Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: hairline),
    ),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: idW + nameW + colW * columns.length + (onEdit != null ? opW : 0),
        ),
        child: table,
      ),
    ),
  );

  return onRefresh == null ? card : RefreshIndicator(onRefresh: onRefresh, child: ListView(children: [card]));
}
