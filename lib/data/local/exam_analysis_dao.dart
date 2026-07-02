import 'dart:convert';
import 'dart:io';
import 'dart:math' show sqrt;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../../core/error_handler.dart';

class ExamAnalysisDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  Future<String> getSignatureDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final sigDir = Directory('${dir.path}/exam_signatures');
    if (!await sigDir.exists()) await sigDir.create(recursive: true);
    return sigDir.path;
  }

  Future<List<Map<String, dynamic>>> getAll({String? courseId}) async {
    final db = await _db;
    final where = courseId != null ? 'WHERE course_id = ?' : '';
    final whereArgs = courseId != null ? [courseId] : [];
    return db.query('exam_analysis',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'updated_at DESC');
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows =
        await db.query('exam_analysis', where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> save(Map<String, dynamic> data) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    data['updated_at'] = now;

    if (data['grades_json'] is List) {
      data['grades_json'] = jsonEncode(data['grades_json']);
    }
    if (data['distribution_json'] is Map) {
      data['distribution_json'] = jsonEncode(data['distribution_json']);
    }

    if (data['id'] != null && (data['id'] as int) > 0) {
      await db.update(
          'exam_analysis', data, where: 'id = ?', whereArgs: [data['id']]);
      return data['id'] as int;
    } else {
      data['created_at'] = now;
      return db.insert('exam_analysis', data);
    }
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('exam_analysis', where: 'id = ?', whereArgs: [id]);
  }

  List<List<double>> parseGrades(String? gradesJson) {
    if (gradesJson == null || gradesJson.isEmpty) return [];
    try {
      final raw = jsonDecode(gradesJson);
      if (raw is! List) return [];
      return [
        for (final row in raw)
          if (row is List)
            [for (final cell in row) (cell as num?)?.toDouble() ?? 0.0],
      ];
    } catch (e, st) {
      swallowDebug(e, tag: 'ExamAnalysisDao.parseGrades', stack: st);
      return [];
    }
  }

  static String encodeGrades(List<List<double>> grades) {
    return jsonEncode(grades);
  }

  static double _stdDev(List<double> values, double mean) {
    if (values.length < 2) return 0;
    final sumSq =
        values.fold<double>(0, (a, b) => a + (b - mean) * (b - mean));
    return sqrt(sumSq / (values.length - 1));
  }

  static Map<String, dynamic> computeStatistics(List<List<double>> grades) {
    if (grades.isEmpty || grades[0].isEmpty) {
      return {
        'studentCount': 0,
        'itemCount': 0,
        'totalScore': 0,
        'avg': 0.0,
        'max': 0,
        'min': 0,
        'stdDev': 0.0,
        'median': 0.0,
        'passCount': 0,
        'passRate': 0.0,
        'goodCount': 0,
        'goodRate': 0.0,
        'excellentCount': 0,
        'excellentRate': 0.0,
        'failCount': 0,
        'difficulty': 0.0,
        'distribution': [0, 0, 0, 0, 0, 0, 0],
        'distributionPct': [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        'itemStats': [],
      };
    }

    final studentCount = grades.length;
    final itemCount = grades[0].length;

    // 每题满分 = 实际出现的最高分
    final itemMaxScores = List<double>.generate(itemCount, (i) {
      double max = 0;
      for (final row in grades) {
        if (i < row.length && row[i] > max) max = row[i];
      }
      return max;
    });

    // 每题平均分 & 标准差
    final itemAverages = List<double>.generate(itemCount, (i) {
      double sum = 0;
      int count = 0;
      for (final row in grades) {
        if (i < row.length) {
          sum += row[i];
          count++;
        }
      }
      return count > 0 ? sum / count : 0.0;
    });

    final itemStdDevs = List<double>.generate(itemCount, (i) {
      final scores = <double>[];
      for (final row in grades) {
        if (i < row.length) scores.add(row[i]);
      }
      return scores.length > 1 ? _stdDev(scores, itemAverages[i]) : 0.0;
    });

    // 总分计算
    final totals = <double>[];
    double totalMax = 0;
    for (final row in grades) {
      double t = 0;
      for (var i = 0; i < row.length; i++) {
        t += row[i];
      }
      totals.add(t);
    }
    if (grades.isNotEmpty) {
      totalMax = itemMaxScores.fold<double>(0, (a, b) => a + b);
    }

    final max = totals.isEmpty ? 0.0 : totals.reduce((a, b) => a > b ? a : b);
    final min = totals.isEmpty ? 0.0 : totals.reduce((a, b) => a < b ? a : b);
    final avg =
        totals.isEmpty ? 0.0 : totals.reduce((a, b) => a + b) / totals.length;
    final stdDev = totals.length > 1 ? _stdDev(totals, avg) : 0.0;

    // 中位数
    final sorted = List<double>.from(totals)..sort();
    final median = sorted.isEmpty
        ? 0.0
        : sorted.length % 2 == 0
            ? (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2
            : sorted[sorted.length ~/ 2];

    // 难度（整卷）
    final difficulty = totalMax > 0 ? avg / totalMax : 0.0;

    // 及格/良好/优秀
    final passThreshold = totalMax * 0.6;
    final goodThreshold = totalMax * 0.8;
    final excellentThreshold = totalMax * 0.9;

    final passCount = totals.where((t) => t >= passThreshold).length;
    final goodCount = totals.where((t) => t >= goodThreshold).length;
    final excellentCount = totals.where((t) => t >= excellentThreshold).length;

    // 分数段分布 (7 ranges: 0-40, 40-50, 50-60, 60-70, 70-80, 80-90, 90-100)
    final dist = [0, 0, 0, 0, 0, 0, 0];
    if (totalMax > 0) {
      for (final t in totals) {
        if (t < 40) {
          dist[0]++;
        } else if (t < 50) {
          dist[1]++;
        } else if (t < 60) {
          dist[2]++;
        } else if (t < 70) {
          dist[3]++;
        } else if (t < 80) {
          dist[4]++;
        } else if (t < 90) {
          dist[5]++;
        } else {
          dist[6]++;
        }
      }
    }
    final distPct = dist
        .map((c) => studentCount > 0 ? (c / studentCount * 100) : 0.0)
        .toList();

    // 各题区分度（简单：高分组前27% vs 低分组后27% 的平均分差/满分）
    final itemDiscriminations = List<double>.generate(itemCount, (i) {
      if (studentCount < 4) return 0.0;
      final groupSize = (studentCount * 0.27).round().clamp(1, studentCount ~/ 2);
      final indexed = <_IndexedScore>[];
      for (var r = 0; r < studentCount; r++) {
        indexed.add(_IndexedScore(totals[r], r));
      }
      indexed.sort((a, b) => b.total.compareTo(a.total));
      final highIdx = indexed.take(groupSize).map((e) => e.index).toSet();
      final lowIdx = indexed.skip(studentCount - groupSize).map((e) => e.index).toSet();

      double highSum = 0, lowSum = 0;
      int highCount = 0, lowCount = 0;
      for (var r = 0; r < studentCount; r++) {
        if (i < grades[r].length) {
          if (highIdx.contains(r)) {
            highSum += grades[r][i];
            highCount++;
          } else if (lowIdx.contains(r)) {
            lowSum += grades[r][i];
            lowCount++;
          }
        }
      }
      final highAvg = highCount > 0 ? highSum / highCount : 0.0;
      final lowAvg = lowCount > 0 ? lowSum / lowCount : 0.0;
      final maxScore = itemMaxScores[i];
      return maxScore > 0 ? (highAvg - lowAvg) / maxScore : 0.0;
    });

    // 各题难度
    final itemDifficulties = List<double>.generate(itemCount, (i) {
      final maxScore = itemMaxScores[i];
      return maxScore > 0 ? (itemAverages[i] / maxScore) : 0.0;
    });

    // 考试效度：各题区分度的平均值（反映试卷整体区分能力）
    final avgDiscrimination = itemDiscriminations.isEmpty
        ? 0.0
        : itemDiscriminations.reduce((a, b) => a + b) / itemDiscriminations.length;

    // 考试信度：KR-20 公式简化版（内部一致性）
    // α = (n / (n-1)) * (1 - Σ(p_i * q_i) / σ²)
    double examReliability = 0.0;
    if (studentCount > 1 && totalMax > 0) {
      final n = itemCount;
      double sumPQ = 0;
      for (var i = 0; i < itemCount; i++) {
        final p = itemMaxScores[i] > 0 ? itemAverages[i] / itemMaxScores[i] : 0.0;
        final q = 1.0 - p;
        sumPQ += p * q;
      }
      final variance = stdDev * stdDev;
      if (variance > 0 && n > 1) {
        examReliability = (n / (n - 1)) * (1 - sumPQ / variance);
        examReliability = examReliability.clamp(0.0, 1.0);
      }
    }

    final itemStats = List.generate(itemCount, (i) {
      final scores = <double>[];
      for (final row in grades) {
        if (i < row.length) scores.add(row[i]);
      }
      final itemMin = scores.isEmpty ? 0.0 : scores.reduce((a, b) => a < b ? a : b);
      return {
        'index': i,
        'fullMark': itemMaxScores[i],
        'max': itemMaxScores[i],
        'min': itemMin,
        'avg': double.parse(itemAverages[i].toStringAsFixed(2)),
        'stdDev': double.parse(itemStdDevs[i].toStringAsFixed(2)),
        'difficulty': double.parse(itemDifficulties[i].toStringAsFixed(3)),
        'discrimination': double.parse(itemDiscriminations[i].toStringAsFixed(3)),
        'label': '题${i + 1}',
      };
    });

    return {
      'studentCount': studentCount,
      'itemCount': itemCount,
      'totalScore': double.parse(totalMax.toStringAsFixed(1)),
      'avg': double.parse(avg.toStringAsFixed(2)),
      'max': double.parse(max.toStringAsFixed(1)),
      'min': double.parse(min.toStringAsFixed(1)),
      'stdDev': double.parse(stdDev.toStringAsFixed(2)),
      'median': double.parse(median.toStringAsFixed(1)),
      'passCount': passCount,
      'passRate': double.parse((passCount / studentCount * 100).toStringAsFixed(1)),
      'goodCount': goodCount,
      'goodRate': double.parse((goodCount / studentCount * 100).toStringAsFixed(1)),
      'excellentCount': excellentCount,
      'excellentRate': double.parse((excellentCount / studentCount * 100).toStringAsFixed(1)),
      'failCount': studentCount - passCount,
      'difficulty': double.parse(difficulty.toStringAsFixed(3)),
      'distribution': dist,
      'distributionPct': distPct.map((v) => double.parse(v.toStringAsFixed(1))).toList(),
      'itemStats': itemStats,
      'examValidity': double.parse(avgDiscrimination.toStringAsFixed(3)),
      'examReliability': double.parse(examReliability.toStringAsFixed(3)),
    };
  }
}

class _IndexedScore {
  final double total;
  final int index;
  const _IndexedScore(this.total, this.index);
}
