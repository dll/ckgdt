import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../presentation/pages/achievement/achievement_shared.dart';

/// 达成度图表生成服务：fl_chart → PNG bytes。
///
/// 用于嵌入 Word 报告和 Excel 模板。所有图表在内存中渲染，
/// 不依赖持久化文件。
class AchievementChartService {
  static final AchievementChartService instance =
      AchievementChartService._();
  AchievementChartService._();

  /// 课程目标达成度条形图（4 根柱子）。
  Future<Uint8List> generateBarChart(
    BuildContext context, {
    required List<String> objectiveNames,
    required List<double> achievements,
    required List<double> expectationLine,
    double width = 600,
    double height = 400,
  }) async {
    final spots = <BarChartGroupData>[];
    for (var i = 0; i < 4 && i < achievements.length; i++) {
      spots.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: achievements[i],
            color: kObjectiveColors[i],
            width: 40,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ));
    }

    final chart = BarChart(
      BarChartData(
        barGroups: spots,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 0.2,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= objectiveNames.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '目标${idx + 1}',
                    style: const TextStyle(fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.2,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: 1.0,
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (expectationLine.isNotEmpty)
              HorizontalLine(
                y: expectationLine.first,
                color: Colors.red.withValues(alpha: 0.6),
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: TextStyle(
                      fontSize: 10, color: Colors.red.withValues(alpha: 0.8)),
                  labelResolver: (_) => '期望值',
                ),
              ),
          ],
        ),
      ),
    );

    return _renderToPng(context, chart, width: width, height: height);
  }

  /// 单个目标的散点趋势图。
  Future<Uint8List> generateScatterChart(
    BuildContext context, {
    required int objectiveIndex,
    required List<double> studentAchievements,
    required double classAverage,
    required double expectation,
    double width = 600,
    double height = 300,
  }) async {
    final color = kObjectiveColors[objectiveIndex];
    final spots = <FlSpot>[
      for (var i = 0; i < studentAchievements.length; i++)
        FlSpot(i + 1.0, studentAchievements[i]),
    ];

    final chart = LineChart(
      LineChartData(
        minY: 0,
        maxY: 1.0,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 0.2,
            ),
          ),
          bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.2,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 0,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                radius: 3,
                color: color,
                strokeColor: color,
              ),
            ),
          ),
        ],
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: classAverage,
              color: Colors.blue.withValues(alpha: 0.6),
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topLeft,
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.blue.withValues(alpha: 0.8)),
                labelResolver: (_) => '班级平均',
              ),
            ),
            HorizontalLine(
              y: expectation,
              color: Colors.red.withValues(alpha: 0.5),
              strokeWidth: 1,
              dashArray: [4, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.red.withValues(alpha: 0.7)),
                labelResolver: (_) => '期望值',
              ),
            ),
          ],
        ),
      ),
    );

    return _renderToPng(context, chart, width: width, height: height);
  }

  /// 将 fl_chart Widget 渲染为 PNG bytes。
  ///
  /// [context] 用于获取 Overlay；调用方应传入已 mount 的BuildContext。
  Future<Uint8List> _renderToPng(
    BuildContext context,
    Widget chart, {
    required double width,
    required double height,
  }) async {
    final GlobalKey key = GlobalKey();
    final overlay = OverlayEntry(
      builder: (_) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: -width,
              top: -height,
              child: SizedBox(
                width: width,
                height: height,
                child: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: Colors.white,
                    child: chart,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(context).insert(overlay);
    // 等待至少 2 帧渲染完成
    await Future.delayed(const Duration(milliseconds: 50));
    await Future.delayed(const Duration(milliseconds: 50));

    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      overlay.remove();
      throw StateError('无法获取 RepaintBoundary');
    }

    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    overlay.remove();
    image.dispose();

    if (byteData == null) {
      throw StateError('图表 PNG 编码失败');
    }
    return byteData.buffer.asUint8List();
  }
}
