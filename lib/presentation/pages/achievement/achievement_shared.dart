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

/// 达成 tab 顶部头部：居中标题 + 左右两张卡片（说明卡片 + 班级平均达成度）。
/// 三个达成 tab（平时/实验/考核）共用。左右水平排布以给下方数据表让出垂直空间。
/// [infoCard] 已构建好的说明卡片（含底色）；[classAvg] 为空则只显示说明卡片占满整行。
Widget achievementTabHeader(
  BuildContext context, {
  required String title,
  required Widget infoCard,
  required Map<String, double> classAvg,
}) {
  final primary = Theme.of(context).colorScheme.primary;

  final avgCard = Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('班级平均指标点达成度',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < 4; i++)
                Expanded(
                  child: Column(
                    children: [
                      Text('目标${i + 1}', style: TextStyle(fontSize: 11, color: kObjectiveColors[i])),
                      const SizedBox(height: 4),
                      Text(
                        (classAvg['obj${i + 1}'] ?? 0).toStringAsFixed(2),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: achievementLevelColor(classAvg['obj${i + 1}'] ?? 0)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          objectiveRadarChart(
            [for (int i = 0; i < 4; i++) classAvg['obj${i + 1}'] ?? 0],
            primary,
            size: 150,
          ),
        ],
      ),
    ),
  );

  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(title,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: infoCard),
              if (classAvg.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(child: avgCard),
              ],
            ],
          ),
        ),
      ],
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

  // 列最小宽度；实际宽度由 LayoutBuilder 按可用宽度等比放大以铺满整行。
  const idMin = 96.0, nameMin = 64.0, colMin = 64.0, opW = 48.0;

  final card = LayoutBuilder(builder: (context, constraints) {
    // 卡片左右各 12 margin + 行内左右 padding 12。
    final avail = constraints.maxWidth - 24 - 24;
    final fixedMin = idMin + nameMin + colMin * columns.length + (onEdit != null ? opW : 0);
    // 可用宽度有余则把多出的宽度按比例分给「学号/姓名/数据列」，铺满整行。
    final extra = (avail - fixedMin).clamp(0.0, double.infinity);
    final flexUnits = idMin + nameMin + colMin * columns.length; // 操作列不拉伸
    final scale = flexUnits > 0 ? extra / flexUnits : 0.0;
    final idW = idMin + idMin * scale;
    final nameW = nameMin + nameMin * scale;
    final colW = colMin + colMin * scale;
    final totalW = idW + nameW + colW * columns.length + (onEdit != null ? opW : 0);

    final header = Container(
      color: primary.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        SizedBox(width: idW, child: Text('学号', style: headerStyle, textAlign: TextAlign.center)),
        SizedBox(width: nameW, child: Text('姓名', style: headerStyle, textAlign: TextAlign.center)),
        for (final c in columns)
          SizedBox(
            width: colW,
            child: Text(c.label,
                style: c.headerColor != null ? headerStyle.copyWith(color: c.headerColor) : headerStyle,
                textAlign: TextAlign.center),
          ),
        if (onEdit != null) SizedBox(width: opW, child: Text('操作', style: headerStyle, textAlign: TextAlign.center)),
      ]),
    );

    final body = ListView.separated(
      shrinkWrap: true,
      itemCount: rows.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: hairline.withValues(alpha: 0.5)),
      itemBuilder: (context, index) {
        final r = rows[index];
        return Container(
          color: index.isEven ? surface : primary.withValues(alpha: 0.025),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            SizedBox(width: idW, child: Text(r['student_id']?.toString() ?? '', style: cellStyle, textAlign: TextAlign.center)),
            SizedBox(width: nameW, child: Text(r['student_name']?.toString() ?? '', style: cellStyle, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
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
    );

    final table = Column(
      mainAxisSize: MainAxisSize.min,
      children: [header, Divider(height: 1, color: hairline), Flexible(child: body)],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      // 列已铺满时不需要横向滚动；列过多导致超宽时才横向滚动。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: totalW <= avail ? const NeverScrollableScrollPhysics() : null,
        child: SizedBox(width: totalW < avail ? avail : totalW, child: table),
      ),
    );
  });

  return onRefresh == null ? card : RefreshIndicator(onRefresh: onRefresh, child: ListView(children: [card]));
}
