import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import 'course_context_service.dart';
import 'course_data_service.dart';

/// Unified loader for course packages under data/{courseId}.
///
/// It imports package-owned rows idempotently and leaves teacher-created rows
/// untouched. Package-owned rows use source_type/creator_id = course_package.
class CoursePackageLoader {
  static final CoursePackageLoader instance = CoursePackageLoader._();
  CoursePackageLoader._();

  static const _packageOwner = 'course_package';

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  Future<CoursePackageImportResult> importActiveCourse({
    bool force = false,
  }) async {
    final course = await _courseContext.getActiveCourse();
    return importCourse(course.id, force: force);
  }

  Future<CoursePackageImportResult> importCourse(
    String courseId, {
    bool force = false,
  }) async {
    final db = await _dbHelper.database;
    await _ensureVersionTable(db);

    final package = await CourseDataService.instance.getPackage(courseId);
    final manifest = package.manifest;
    if (manifest == null || manifest.isEmpty) {
      return CoursePackageImportResult.skipped(
        courseId,
        'manifest not found',
      );
    }

    final manifestHash = _hashJson(manifest);
    final packageVersion = manifest['package_version']?.toString() ??
        manifest['version']?.toString() ??
        'unknown';

    final summary = CoursePackageImportResult(
      courseId: courseId,
      packageVersion: packageVersion,
      manifestHash: manifestHash,
    );

    try {
      await db.transaction((txn) async {
        summary.courseUpdated = await _syncCourse(txn, package);
        summary.labTasksImported = await _syncLabTasks(txn, courseId);
        summary.homeworksImported = await _syncHomeworks(txn, courseId);
        summary.resourcesImported = await _syncResourceFiles(txn, courseId);
        summary.usersImported = await _syncMockUsers(txn, courseId);
        summary.classesImported = await _syncMockClasses(txn, courseId);
        await _recordVersion(
          txn,
          courseId: courseId,
          packageVersion: packageVersion,
          manifestHash: manifestHash,
          status: 'imported',
          message: summary.message,
        );
      });
      debugPrint('=== CoursePackageLoader: ${summary.message}');
      return summary;
    } catch (e, st) {
      swallowDebug(e,
          tag: 'CoursePackageLoader.importCourse.$courseId', stack: st);
      await _recordVersion(
        db,
        courseId: courseId,
        packageVersion: packageVersion,
        manifestHash: manifestHash,
        status: 'failed',
        message: e.toString(),
      );
      return CoursePackageImportResult.failed(
        courseId,
        packageVersion,
        manifestHash,
        e.toString(),
      );
    }
  }

  Future<void> _ensureVersionTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_package_versions(
        course_id TEXT PRIMARY KEY,
        package_version TEXT,
        imported_at TEXT,
        manifest_hash TEXT,
        status TEXT,
        message TEXT
      )
    ''');
  }

  Future<bool> _syncCourse(
    DatabaseExecutor txn,
    CourseDataPackage package,
  ) async {
    final manifest = package.manifest ?? {};
    final courseId = package.courseId;
    final courseName =
        manifest['course_name']?.toString().trim().isNotEmpty == true
            ? manifest['course_name'].toString().trim()
            : courseId;
    final description = manifest['description']?.toString() ?? '';
    final chapters = package.chapterTitles;
    final chapterCount = chapters.isNotEmpty ? chapters.length : 1;

    final activeRows = await txn.query(
      'courses',
      where: 'is_active = ?',
      whereArgs: [1],
      limit: 1,
    );
    final rows = await txn.query(
      'courses',
      where: 'id = ?',
      whereArgs: [courseId],
      limit: 1,
    );

    final data = {
      'id': courseId,
      'name': courseName,
      'description': description,
      'chapter_count': chapterCount,
      'chapters': jsonEncode(chapters),
      'is_active': rows.isEmpty && activeRows.isEmpty
          ? 1
          : rows.isEmpty
              ? 0
              : rows.first['is_active'],
      'created_at': rows.isEmpty
          ? DateTime.now().toIso8601String()
          : rows.first['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
    };

    if (rows.isEmpty) {
      await txn.insert('courses', data);
      return true;
    }

    final current = rows.first;
    final needsUpdate = current['name'] != courseName ||
        current['description'] != description ||
        current['chapter_count'] != chapterCount ||
        current['chapters'] != jsonEncode(chapters);
    if (!needsUpdate) return false;

    await txn.update(
      'courses',
      data,
      where: 'id = ?',
      whereArgs: [courseId],
    );
    return true;
  }

  Future<int> _syncLabTasks(DatabaseExecutor txn, String courseId) async {
    final tasks = await _loadJsonList('data/$courseId/配置/lab_tasks.json');
    if (tasks.isEmpty) return 0;

    await txn.delete(
      'lab_tasks',
      where: 'course_id = ? AND creator_id = ?',
      whereArgs: [courseId, _packageOwner],
    );

    var count = 0;
    final now = DateTime.now().toIso8601String();
    for (final task in tasks) {
      await txn.insert('lab_tasks', {
        'course_id': courseId,
        'title': task['title']?.toString() ?? '',
        'chapter': task['chapter']?.toString(),
        'description': task['description']?.toString(),
        'requirements': task['requirements']?.toString(),
        'deliverables': task['deliverables']?.toString(),
        'due_date': _dueDateFromOffset(task['due_days_offset']),
        'difficulty': task['difficulty']?.toString() ?? '中等',
        'max_score': _asInt(task['max_score'], fallback: 100),
        'status': 'active',
        'creator_id': _packageOwner,
        'created_at': now,
        'updated_at': now,
      });
      count++;
    }
    return count;
  }

  Future<int> _syncHomeworks(DatabaseExecutor txn, String courseId) async {
    final homeworkList = await _loadJsonList('data/$courseId/配置/homework.json');
    if (homeworkList.isEmpty) return 0;

    var count = 0;
    final now = DateTime.now().toIso8601String();
    for (final raw in homeworkList) {
      final chapter = raw['chapter']?.toString() ?? '';
      final chapterTitle = raw['chapter_title']?.toString() ?? '';
      final title = '$chapterTitle作业';
      final items = (raw['items'] as List?)?.whereType<Map>().toList() ??
          const <Map<dynamic, dynamic>>[];
      if (title.trim().isEmpty || items.isEmpty) continue;

      final totalScore = items.fold<int>(
        0,
        (sum, item) => sum + _asInt(item['max_score'], fallback: 100),
      );
      final existing = await txn.query(
        'homeworks',
        where: 'course_id = ? AND title = ?',
        whereArgs: [courseId, title],
        limit: 1,
      );

      int homeworkId;
      final data = {
        'course_id': courseId,
        'title': title,
        'description': raw['description']?.toString() ?? '',
        'chapter': chapter,
        'chapter_title': chapterTitle,
        'course_objective': raw['course_objective']?.toString() ?? '',
        'total_score': totalScore == 0 ? 100 : totalScore,
        'deadline': raw['deadline']?.toString(),
        'status': 'published',
        'created_at': existing.isEmpty
            ? now
            : existing.first['created_at']?.toString() ?? now,
      };

      if (existing.isEmpty) {
        homeworkId = await txn.insert('homeworks', data);
      } else {
        homeworkId = existing.first['id'] as int;
        await txn.update(
          'homeworks',
          data,
          where: 'id = ?',
          whereArgs: [homeworkId],
        );
        await txn.delete(
          'homework_items',
          where: 'homework_id = ?',
          whereArgs: [homeworkId],
        );
      }

      for (var i = 0; i < items.length; i++) {
        final item = Map<String, dynamic>.from(items[i]);
        await txn.insert('homework_items', {
          'homework_id': homeworkId,
          'item_index': i + 1,
          'type': item['type_code']?.toString() ?? 'basic',
          'type_label': item['type']?.toString() ?? '基础题',
          'question': item['question']?.toString() ?? '',
          'reference_answer': item['reference_answer']?.toString(),
          'max_score': _asInt(item['max_score'], fallback: 100),
          'objective_mapping': jsonEncode(item['objective_mapping'] ?? []),
        });
      }
      count++;
    }
    return count;
  }

  Future<int> _syncResourceFiles(DatabaseExecutor txn, String courseId) async {
    final paths = await _courseAssetPaths(courseId);
    if (paths.isEmpty) return 0;

    await txn.delete(
      'resource_files',
      where: 'course_id = ? AND source_type = ?',
      whereArgs: [courseId, _packageOwner],
    );

    var count = 0;
    for (final path in paths) {
      final fileName = path.split('/').last;
      final category = _categoryFromPath(courseId, path);
      await txn.insert('resource_files', {
        'course_id': courseId,
        'file_name': fileName,
        'file_path': path,
        'file_type': _fileType(fileName, category),
        'chapter': _chapterFromFileName(fileName),
        'description': _displayName(fileName),
        'source_type': _packageOwner,
      });
      count++;
    }
    return count;
  }

  Future<int> _syncMockUsers(DatabaseExecutor txn, String courseId) async {
    final mock = await _loadJson('data/$courseId/配置/mock_data.json');
    final testUsers = mock['test_users'];
    if (testUsers is! Map) return 0;

    final users = <Map<String, dynamic>>[];
    final admin = testUsers['admin'];
    if (admin is Map) users.add(Map<String, dynamic>.from(admin));
    final teachers = testUsers['teachers'];
    if (teachers is List) {
      users.addAll(teachers.whereType<Map>().map(Map<String, dynamic>.from));
    }
    final students = testUsers['students'];
    if (students is List) {
      users.addAll(students.whereType<Map>().map(Map<String, dynamic>.from));
    }

    var count = 0;
    final now = DateTime.now().toIso8601String();
    for (final user in users) {
      final userId = user['user_id']?.toString() ?? '';
      if (userId.isEmpty) continue;
      final existing = await txn.query(
        'users',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      final data = {
        'user_id': userId,
        'real_name': user['real_name']?.toString() ?? userId,
        'role': user['role']?.toString() ?? 'student',
        'created_at': existing.isEmpty
            ? now
            : existing.first['created_at']?.toString() ?? now,
        'is_active': 1,
      };
      await txn.insert(
        'users',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;
    }
    return count;
  }

  Future<int> _syncMockClasses(DatabaseExecutor txn, String courseId) async {
    final mock = await _loadJson('data/$courseId/配置/mock_data.json');
    final classes = mock['test_classes'];
    if (classes is! List) return 0;

    var count = 0;
    final now = DateTime.now().toIso8601String();
    for (final raw in classes.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final className = item['class_name']?.toString() ?? '';
      if (className.isEmpty) continue;
      final semester = item['semester']?.toString();
      final teacherId = item['teacher_id']?.toString();
      final existing = await txn.query(
        'classes',
        where: 'name = ? AND IFNULL(semester, "") = IFNULL(?, "")',
        whereArgs: [className, semester],
        limit: 1,
      );
      final studentIds = (item['student_ids'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];

      int classId;
      final data = {
        'name': className,
        'semester': semester,
        'teacher_id': teacherId,
        'description': '$courseId course package demo class',
        'student_count': studentIds.length,
        'is_archived': 0,
        'updated_at': now,
      };
      if (existing.isEmpty) {
        classId = await txn.insert('classes', {
          ...data,
          'created_at': now,
        });
      } else {
        classId = existing.first['id'] as int;
        await txn
            .update('classes', data, where: 'id = ?', whereArgs: [classId]);
      }

      await txn.delete(
        'class_members',
        where: 'class_id = ?',
        whereArgs: [classId],
      );
      if (teacherId != null && teacherId.isNotEmpty) {
        await txn.insert(
          'class_members',
          {
            'class_id': classId,
            'user_id': teacherId,
            'role': 'teacher',
            'joined_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final studentId in studentIds) {
        await txn.insert(
          'class_members',
          {
            'class_id': classId,
            'user_id': studentId,
            'role': 'student',
            'joined_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      count++;
    }
    return count;
  }

  Future<void> _recordVersion(
    DatabaseExecutor db, {
    required String courseId,
    required String packageVersion,
    required String manifestHash,
    required String status,
    required String message,
  }) async {
    await _ensureVersionTable(db);
    await db.insert(
      'course_package_versions',
      {
        'course_id': courseId,
        'package_version': packageVersion,
        'imported_at': DateTime.now().toIso8601String(),
        'manifest_hash': manifestHash,
        'status': status,
        'message': message,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>> _loadJson(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> _loadJsonList(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<String>> _courseAssetPaths(String courseId) async {
    try {
      final raw = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final prefix = 'data/$courseId/';
      final allowed = <String>{
        '大纲',
        '进度',
        '理论',
        '课件',
        '视频',
        '作业',
        '实验',
        '考核',
        '达成',
        '归档',
        '图谱',
        '项目',
        '文档',
        '推荐',
      };
      final manifestPaths = decoded.keys.map((e) => e.toString()).where((path) {
        final decodedPath = _safeDecode(path);
        if (!decodedPath.startsWith(prefix)) return false;
        final rest = decodedPath.substring(prefix.length);
        final top = rest.split('/').first;
        if (!allowed.contains(top)) return false;
        return RegExp(r'\.(md|json|puml|pdf|pptx|docx|xlsx|mp4)$',
                caseSensitive: false)
            .hasMatch(decodedPath);
      }).toList()
        ..sort();
      if (manifestPaths.isNotEmpty) {
        final knownPaths = await _knownCourseAssetPaths(courseId);
        return {...manifestPaths, ...knownPaths}.toList()..sort();
      }
      return _knownCourseAssetPaths(courseId);
    } catch (_) {
      return _knownCourseAssetPaths(courseId);
    }
  }

  Future<List<String>> _knownCourseAssetPaths(String courseId) async {
    final paths = <String>[];
    final chapters = await _loadJsonList('data/$courseId/配置/chapters.json');
    final labs = await _loadJsonList('data/$courseId/配置/lab_tasks.json');
    const configs = [
      'achievement_calc.json',
      'assessment.json',
      'chapters.json',
      'course_gen_input.json',
      'course_settings.json',
      'graph_categories.json',
      'homework.json',
      'lab_tasks.json',
      'manifest.json',
      'mock_data.json',
      'quiz_config.json',
      'report_templates.json',
      'roles.json',
      'score_aggregator.json',
    ];
    for (final file in configs) {
      await _addIfAssetExists(paths, 'data/$courseId/配置/$file');
    }

    for (var i = 0; i < chapters.length; i++) {
      final number = _asInt(chapters[i]['number'], fallback: i + 1);
      final title = chapters[i]['title']?.toString() ?? '';
      await _addIfAssetExists(paths, 'data/$courseId/理论/第$number章 $title.md');
      await _addIfAssetExists(
          paths, 'data/$courseId/理论/第$number章 $title-测验.md');
      await _addIfAssetExists(
          paths, 'data/$courseId/理论/第$number章 $title-作业.md');
      await _addIfAssetExists(
          paths, 'data/$courseId/作业/第$number章 $title-作业.md');
      await _addIfAssetExists(paths, 'data/$courseId/课件/第$number章 $title.md');
      await _addIfAssetExists(
          paths, 'data/$courseId/视频/${_cnChapter(number)} $title-视频脚本.md');
    }

    for (final lab in labs) {
      final title = lab['title']?.toString() ?? '';
      if (title.isEmpty) continue;
      await _addIfAssetExists(paths, 'data/$courseId/实验/实验教程/$title教程.md');
      await _addIfAssetExists(paths, 'data/$courseId/实验/报告模板/$title报告模板.md');
    }

    await _addIfAssetExists(paths, 'data/$courseId/实验/实验指导/README.md');
    await _addIfAssetExists(paths, 'data/$courseId/实验/平台技术栈/README.md');
    await _addIfAssetExists(paths, 'data/$courseId/文档/数智课程特色设计.md');
    await _addIfAssetExists(paths, 'data/$courseId/文档/知识图谱与数字孪生闭环.md');
    await _addIfAssetExists(paths, 'data/$courseId/文档/智慧课程审核清单.md');
    return paths..sort();
  }

  Future<void> _addIfAssetExists(List<String> paths, String path) async {
    try {
      await rootBundle.loadString(path);
      paths.add(path);
    } catch (_) {}
  }

  String _cnChapter(int value) {
    const nums = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (value > 0 && value < nums.length) return '第${nums[value]}章';
    return '第$value章';
  }

  String _hashJson(Map<String, dynamic> value) {
    final raw = const JsonEncoder.withIndent('  ').convert(value);
    return sha256.convert(utf8.encode(raw)).toString();
  }

  int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String? _dueDateFromOffset(dynamic raw) {
    final offset = _asInt(raw, fallback: 0);
    if (offset <= 0) return null;
    return DateTime.now().add(Duration(days: offset)).toIso8601String();
  }

  String _categoryFromPath(String courseId, String path) {
    final decoded = _safeDecode(path);
    final rest = decoded.substring('data/$courseId/'.length);
    return rest.split('/').first;
  }

  String _fileType(String fileName, String category) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video';
    if (lower.endsWith('.pptx')) return 'ppt';
    if (lower.endsWith('.pdf')) return 'pdf';
    if (lower.endsWith('.docx')) return 'docx';
    if (lower.endsWith('.xlsx')) return 'xlsx';
    if (lower.endsWith('.puml')) return 'puml';
    if (category == '视频') return 'video';
    if (category == '课件') return 'ppt';
    if (category == '作业') return 'homework';
    if (category == '实验') return 'lab';
    if (category == '归档') return 'archive';
    if (category == '达成') return 'achievement';
    if (category == '考核') return 'assessment';
    if (category == '图谱') return 'graph';
    return 'md';
  }

  String _displayName(String fileName) {
    return fileName
        .replaceAll('_new.md', '')
        .replaceAll('.md', '')
        .replaceAll('.json', '')
        .replaceAll('.puml', '')
        .replaceAll('.pdf', '')
        .replaceAll('.pptx', '')
        .replaceAll('.docx', '')
        .replaceAll('.xlsx', '');
  }

  String _chapterFromFileName(String fileName) {
    final digit = RegExp(r'第\s*(\d+)\s*章').firstMatch(fileName);
    if (digit != null) return '第${digit.group(1)}章';
    final cn = RegExp(r'第\s*([一二三四五六七八九十]+)\s*章').firstMatch(fileName);
    if (cn != null) return '第${cn.group(1)}章';
    final lab = RegExp(r'实验\s*([一二三四五六七八九十\d]+)').firstMatch(fileName);
    if (lab != null) return '实验${lab.group(1)}';
    return '课程资源';
  }

  String _safeDecode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }
}

class CoursePackageImportResult {
  final String courseId;
  final String packageVersion;
  final String manifestHash;
  final bool skipped;
  final bool failed;
  final String? reason;
  bool courseUpdated = false;
  int labTasksImported = 0;
  int homeworksImported = 0;
  int resourcesImported = 0;
  int usersImported = 0;
  int classesImported = 0;

  CoursePackageImportResult({
    required this.courseId,
    required this.packageVersion,
    required this.manifestHash,
    this.skipped = false,
    this.failed = false,
    this.reason,
  });

  factory CoursePackageImportResult.skipped(String courseId, String reason) =>
      CoursePackageImportResult(
        courseId: courseId,
        packageVersion: 'unknown',
        manifestHash: '',
        skipped: true,
        reason: reason,
      );

  factory CoursePackageImportResult.failed(
    String courseId,
    String packageVersion,
    String manifestHash,
    String reason,
  ) =>
      CoursePackageImportResult(
        courseId: courseId,
        packageVersion: packageVersion,
        manifestHash: manifestHash,
        failed: true,
        reason: reason,
      );

  String get message {
    if (skipped) return 'course=$courseId skipped: $reason';
    if (failed) return 'course=$courseId failed: $reason';
    return 'course=$courseId version=$packageVersion '
        'courseUpdated=$courseUpdated labs=$labTasksImported '
        'homeworks=$homeworksImported '
        'resources=$resourcesImported users=$usersImported '
        'classes=$classesImported';
  }
}
