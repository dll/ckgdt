import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import 'achievement/achievement_excel_service.dart';
import 'archive/archive_template_source_service.dart';
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
    final template = _templateMetadata(package);

    final summary = CoursePackageImportResult(
      courseId: courseId,
      packageVersion: packageVersion,
      manifestHash: manifestHash,
      templateId: template['id']?.toString() ?? 'unknown',
      templateVersion: template['version']?.toString() ?? 'unknown',
      templateProfile: template['profile']?.toString() ?? 'unknown',
      profileTemplateId:
          template['profile_template_id']?.toString() ?? 'unknown',
      profileTemplateVersion:
          template['profile_template_version']?.toString() ?? 'unknown',
    );

    try {
      await db.transaction((txn) async {
        summary.courseUpdated = await _syncCourse(txn, package);
        summary.objectivesImported = await _syncCourseObjectives(txn, package);
        summary.labTasksImported = await _syncLabTasks(txn, package);
        summary.homeworksImported = await _syncHomeworks(txn, package);
        summary.graphsImported = await _syncGraphs(txn, package);
        summary.resourcesImported = await _syncResourceFiles(txn, package);
        summary.usersImported = await _syncMockUsers(txn, package);
        summary.classesImported = await _syncMockClasses(txn, package);
        await _recordVersion(
          txn,
          courseId: courseId,
          packageVersion: packageVersion,
          manifestHash: manifestHash,
          template: template,
          status: 'imported',
          message: summary.message,
        );
      });
      _registerArchiveTemplateRoot(package);
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
        template: template,
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
        template_id TEXT,
        template_version TEXT,
        template_profile TEXT,
        profile_template_id TEXT,
        profile_template_name TEXT,
        profile_template_version TEXT,
        status TEXT,
        message TEXT
      )
    ''');
    await _ensureColumn(db, 'course_package_versions', 'template_id', 'TEXT');
    await _ensureColumn(
      db,
      'course_package_versions',
      'template_version',
      'TEXT',
    );
    await _ensureColumn(
      db,
      'course_package_versions',
      'template_profile',
      'TEXT',
    );
    await _ensureColumn(
      db,
      'course_package_versions',
      'profile_template_id',
      'TEXT',
    );
    await _ensureColumn(
      db,
      'course_package_versions',
      'profile_template_name',
      'TEXT',
    );
    await _ensureColumn(
      db,
      'course_package_versions',
      'profile_template_version',
      'TEXT',
    );
  }

  Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
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

  Future<int> _syncLabTasks(
    DatabaseExecutor txn,
    CourseDataPackage package,
  ) async {
    final courseId = package.courseId;
    final tasks = await _loadPackageJsonList(package, 'lab_tasks.json');
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

  Future<int> _syncCourseObjectives(
    DatabaseExecutor txn,
    CourseDataPackage package,
  ) async {
    final courseId = package.courseId;
    final manifest = package.manifest ?? {};
    final courseName =
        manifest['course_name']?.toString().trim().isNotEmpty == true
            ? manifest['course_name'].toString().trim()
            : courseId;

    var rows = <Map<String, dynamic>>[];
    var syllabusVersion = '未标注版本';
    final syllabusText = await _loadPackageSyllabusText(package);
    if (syllabusText.trim().isNotEmpty) {
      final excel = AchievementExcelService.instance;
      rows = excel.deterministicSyllabusRowsFromRawText(syllabusText);
      syllabusVersion = excel.syllabusVersionFromText(syllabusText);
    }
    if (rows.isEmpty) {
      rows = await _objectiveRowsFromAchievementConfig(package);
      syllabusVersion = '资源包配置版';
    }
    if (rows.isEmpty) return 0;

    await txn.delete(
      'course_objectives',
      where: 'course_name = ?',
      whereArgs: [courseName],
    );
    final now = DateTime.now().toIso8601String();
    var count = 0;
    for (final raw in rows) {
      final idx = _asInt(raw['idx'] ?? raw['id'], fallback: count + 1);
      if (idx <= 0) continue;
      await txn.insert(
        'course_objectives',
        {
          'course_name': courseName,
          'idx': idx,
          'name': raw['name']?.toString().trim().isNotEmpty == true
              ? raw['name'].toString()
              : '课程目标$idx',
          'indicator': raw['indicator']?.toString() ?? '',
          'weight': _asRatio(raw['weight']),
          'full_mark': _asDouble(
            raw['full_mark'],
            fallback: _asRatio(raw['weight']) * 100,
          ),
          'pingshi_ratio': _asRatio(raw['pingshi_ratio'], fallback: 0.20),
          'experiment_ratio': _asRatio(raw['experiment_ratio'], fallback: 0.30),
          'exam_ratio': _asRatio(raw['exam_ratio'], fallback: 0.50),
          'chapters': raw['chapters']?.toString() ?? '',
          'description': raw['description']?.toString() ?? '',
          'assess_content': raw['assess_content']?.toString() ?? '',
          'experiments': raw['experiments']?.toString() ?? '',
          'pingshi_standard': raw['pingshi_standard']?.toString() ?? '',
          'experiment_standard': raw['experiment_standard']?.toString() ?? '',
          'assessment_items_json':
              raw['assessment_items_json']?.toString() ?? '',
          'extra_columns_json': raw['extra_columns_json']?.toString() ?? '',
          'syllabus_version':
              raw['syllabus_version']?.toString() ?? syllabusVersion,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;
    }
    return count;
  }

  Future<String> _loadPackageSyllabusText(CourseDataPackage package) async {
    final paths = await _coursePackagePaths(package);
    final syllabusPaths = paths
        .where((path) =>
            path.replaceAll('\\', '/').contains('/大纲/') &&
            path.toLowerCase().endsWith('.md') &&
            path.contains('教学大纲'))
        .toList()
      ..sort();
    for (final path in syllabusPaths) {
      try {
        final text = path.startsWith('data/')
            ? await rootBundle.loadString(path)
            : await File(path).readAsString(encoding: utf8);
        if (text.trim().isNotEmpty) return text;
      } catch (e, st) {
        swallowDebug(e, tag: 'CoursePackageLoader.syllabus', stack: st);
      }
    }
    return '';
  }

  Future<List<Map<String, dynamic>>> _objectiveRowsFromAchievementConfig(
      CourseDataPackage package) async {
    final config = await _loadPackageJson(package, 'achievement_calc.json');
    final objectiveWeights = (config['objective_weights'] as List?)
            ?.whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList() ??
        (config['objectives'] as List?)
            ?.whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList() ??
        const <Map<String, dynamic>>[];
    if (objectiveWeights.isEmpty) return const [];

    final requirements = <int, String>{};
    for (final raw
        in (config['graduation_requirements'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final objectiveId = _asInt(raw['objective_id'], fallback: 0);
      if (objectiveId <= 0) continue;
      requirements[objectiveId] = raw['requirement']?.toString() ?? '';
    }

    final ratiosByObjective = <int, Map<String, double>>{};
    for (final source in (config['data_sources'] as List? ?? const [])) {
      if (source is! Map) continue;
      final env = _envKey(source['component']?.toString() ??
          source['source_name']?.toString() ??
          '');
      final componentWeight = _asRatio(source['component_weight']);
      if (componentWeight <= 0) continue;
      for (final contribution
          in (source['objective_contribution'] as List? ?? const [])) {
        if (contribution is! Map) continue;
        final objectiveId = _asInt(contribution['objective_id'], fallback: 0);
        if (objectiveId <= 0) continue;
        final contributionRatio =
            _asRatio(contribution['contribution'], fallback: 1.0);
        final target = ratiosByObjective.putIfAbsent(
          objectiveId,
          () => {'pingshi': 0, 'experiment': 0, 'exam': 0},
        );
        target[env] = (target[env] ?? 0) + componentWeight * contributionRatio;
      }
      for (final item in (source['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final itemWeight = _asRatio(item['weight']);
        for (final contribution
            in (item['objective_mapping'] as List? ?? const [])) {
          if (contribution is! Map) continue;
          final objectiveId = _asInt(contribution['objective_id'], fallback: 0);
          if (objectiveId <= 0) continue;
          final contributionRatio =
              _asRatio(contribution['contribution'], fallback: 1.0);
          final target = ratiosByObjective.putIfAbsent(
            objectiveId,
            () => {'pingshi': 0, 'experiment': 0, 'exam': 0},
          );
          target[env] = (target[env] ?? 0) + itemWeight * contributionRatio;
        }
      }
    }

    return objectiveWeights.map((obj) {
      final idx =
          _asInt(obj['id'], fallback: objectiveWeights.indexOf(obj) + 1);
      final ratio = _normalizeEnvRatios(ratiosByObjective[idx]);
      final weight = _asRatio(obj['weight']);
      return {
        'idx': idx,
        'name': obj['name']?.toString() ?? '课程目标$idx',
        'description': obj['name']?.toString() ?? '课程目标$idx',
        'indicator': requirements[idx] ?? '',
        'weight': weight,
        'full_mark': weight > 0 ? weight * 100 : 100,
        'pingshi_ratio': ratio['pingshi'],
        'experiment_ratio': ratio['experiment'],
        'exam_ratio': ratio['exam'],
        'assess_content': '依据资源包 achievement_calc.json 自动同步',
      };
    }).toList();
  }

  Future<int> _syncHomeworks(
    DatabaseExecutor txn,
    CourseDataPackage package,
  ) async {
    final courseId = package.courseId;
    final homeworkList = await _loadPackageJsonList(package, 'homework.json');
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

      // 添加作业概念到知识图谱
      try {
        final conceptName = '$chapterTitle - 作业';
        final conceptDesc = items
            .map((item) => item['question']?.toString() ?? '')
            .where((q) => q.isNotEmpty)
            .join('\n');
        await txn.insert(
            'knowledge_concepts',
            {
              'concept_name': conceptName,
              'concept_type': 'homework',
              'chapter': chapter.replaceAll(RegExp(r'[^0-9]'), ''),
              'description': conceptDesc,
              'importance': 'important',
              'course_id': courseId,
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (e) {
        // 忽略概念添加失败
      }

      count++;
    }
    return count;
  }

  Future<int> _syncResourceFiles(
    DatabaseExecutor txn,
    CourseDataPackage package,
  ) async {
    final courseId = package.courseId;
    final paths = await _coursePackagePaths(package);
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

  Future<int> _syncGraphs(
    DatabaseExecutor txn,
    CourseDataPackage package,
  ) async {
    final courseId = package.courseId;
    final graphFiles = await _loadPackageGraphFiles(package);
    if (graphFiles.isEmpty) return 0;

    final existingGraphs = await txn.query(
      'graphs',
      columns: ['id'],
      where: 'course_id = ?',
      whereArgs: [courseId],
    );
    final graphIds = existingGraphs
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    for (final graphId in graphIds) {
      await txn.delete('edges', where: 'graph_id = ?', whereArgs: [graphId]);
      await txn.delete('nodes', where: 'graph_id = ?', whereArgs: [graphId]);
    }
    await txn.delete('graphs', where: 'course_id = ?', whereArgs: [courseId]);

    var count = 0;
    for (var i = 0; i < graphFiles.length; i++) {
      final graph = graphFiles[i];
      final category = graph['category']?.toString().trim().isNotEmpty == true
          ? graph['category'].toString().trim()
          : '课程图谱';
      final slug = graph['slug']?.toString().trim().isNotEmpty == true
          ? graph['slug'].toString().trim()
          : _slug(category);
      final graphId = '${courseId}_$slug';
      await txn.insert(
        'graphs',
        {
          'id': graphId,
          'title': category,
          'course_id': courseId,
          'graph_type': category.contains('课程') ? 'course' : slug,
          'layout': 'tree',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final nodeIdMap = <String, String>{};
      final rawNodes = (graph['nodes'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      for (var n = 0; n < rawNodes.length; n++) {
        final node = rawNodes[n];
        final rawId = node['id']?.toString().trim().isNotEmpty == true
            ? node['id'].toString().trim()
            : 'node_${n + 1}';
        final dbNodeId = '${graphId}_$rawId';
        nodeIdMap[rawId] = dbNodeId;
      }
      for (var n = 0; n < rawNodes.length; n++) {
        final node = rawNodes[n];
        final rawId = node['id']?.toString().trim().isNotEmpty == true
            ? node['id'].toString().trim()
            : 'node_${n + 1}';
        final parentRaw = node['parent_id']?.toString();
        await txn.insert(
          'nodes',
          {
            'id': nodeIdMap[rawId],
            'graph_id': graphId,
            'title': node['label']?.toString() ??
                node['title']?.toString() ??
                '节点${n + 1}',
            'content': node['content']?.toString() ??
                node['description']?.toString() ??
                '',
            'node_type': node['type']?.toString() ??
                node['node_type']?.toString() ??
                'knowledge',
            'level': _asInt(node['level'], fallback: 0),
            'x': _asDouble(node['x'], fallback: 0),
            'y': _asDouble(node['y'], fallback: 0),
            'color': node['color']?.toString() ??
                graph['color']?.toString() ??
                '#1677FF',
            'parent_id': parentRaw == null ? null : nodeIdMap[parentRaw],
            'visible': 1,
            'metadata_json': jsonEncode({
              'course_id': courseId,
              'source': _packageOwner,
              'raw_id': rawId,
              'category': category,
            }),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final rawEdges = (graph['edges'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      for (var e = 0; e < rawEdges.length; e++) {
        final edge = rawEdges[e];
        final sourceRaw = edge['source']?.toString() ??
            edge['source_id']?.toString() ??
            edge['from']?.toString();
        final targetRaw = edge['target']?.toString() ??
            edge['target_id']?.toString() ??
            edge['to']?.toString();
        final sourceId = sourceRaw == null ? null : nodeIdMap[sourceRaw];
        final targetId = targetRaw == null ? null : nodeIdMap[targetRaw];
        if (sourceId == null || targetId == null) continue;
        await txn.insert(
          'edges',
          {
            'id': '${graphId}_edge_${e + 1}',
            'graph_id': graphId,
            'source_id': sourceId,
            'target_id': targetId,
            'edge_type': edge['type']?.toString() ??
                edge['edge_type']?.toString() ??
                'related',
            'label': edge['label']?.toString() ?? '',
            'weight': _asDouble(edge['weight'], fallback: 1),
            'color': edge['color']?.toString() ?? '#94A3B8',
            'width': _asDouble(edge['width'], fallback: 1),
            'style': edge['style']?.toString() ?? 'solid',
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      count++;
    }
    return count;
  }

  Future<int> _syncMockUsers(
    DatabaseExecutor txn,
    CourseDataPackage package,
  ) async {
    final mock = await _loadPackageJson(package, 'mock_data.json');
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

  Future<int> _syncMockClasses(
    DatabaseExecutor txn,
    CourseDataPackage package,
  ) async {
    final courseId = package.courseId;
    final mock = await _loadPackageJson(package, 'mock_data.json');
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
    required Map<String, dynamic> template,
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
        'template_id': template['id']?.toString() ?? 'unknown',
        'template_version': template['version']?.toString() ?? 'unknown',
        'template_profile': template['profile']?.toString() ?? 'unknown',
        'profile_template_id':
            template['profile_template_id']?.toString() ?? 'unknown',
        'profile_template_name':
            template['profile_template_name']?.toString() ?? 'unknown',
        'profile_template_version':
            template['profile_template_version']?.toString() ?? 'unknown',
        'status': status,
        'message': message,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  void _registerArchiveTemplateRoot(CourseDataPackage package) {
    if (package.source != CourseSource.localDir ||
        package.packageRootPath == null) {
      return;
    }
    final archiveRoot = '${package.packageRootPath}/归档';
    if (!Directory(archiveRoot).existsSync()) return;
    ArchiveTemplateSourceService.registerCourseArchiveRoot(
      courseId: package.courseId,
      archiveRoot: archiveRoot,
    );
  }

  Future<Map<String, dynamic>> _loadJson(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e, st) {
      swallowDebug(e, tag: 'CoursePackageLoader', stack: st);
    }
    return {};
  }

  Future<Map<String, dynamic>> _loadPackageJson(
    CourseDataPackage package,
    String fileName,
  ) async {
    final embedded = package.configFiles[fileName];
    if (embedded is Map) return Map<String, dynamic>.from(embedded);
    if (package.source == CourseSource.localDir &&
        package.packageRootPath != null) {
      final file = File('${package.packageRootPath}/配置/$fileName');
      try {
        if (!await file.exists()) return {};
        final raw = await file.readAsString(encoding: utf8);
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (e, st) {
        swallowDebug(e,
            tag: 'CoursePackageLoader.localJson.$fileName', stack: st);
      }
      return {};
    }
    return _loadJson('data/${package.courseId}/配置/$fileName');
  }

  Future<List<Map<String, dynamic>>> _loadJsonList(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'CoursePackageLoader', stack: st);
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _loadPackageJsonList(
    CourseDataPackage package,
    String fileName,
  ) async {
    final embedded = package.configFiles[fileName];
    if (embedded is List) {
      return embedded.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    if (package.source == CourseSource.localDir &&
        package.packageRootPath != null) {
      final file = File('${package.packageRootPath}/配置/$fileName');
      try {
        if (!await file.exists()) return const [];
        final raw = await file.readAsString(encoding: utf8);
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
        }
      } catch (e, st) {
        swallowDebug(e,
            tag: 'CoursePackageLoader.localJsonList.$fileName', stack: st);
      }
      return const [];
    }
    return _loadJsonList('data/${package.courseId}/配置/$fileName');
  }

  Future<List<String>> _coursePackagePaths(CourseDataPackage package) async {
    if (package.source == CourseSource.localDir &&
        package.packageRootPath != null) {
      final root = Directory(package.packageRootPath!);
      if (!await root.exists()) return const [];
      final paths = <String>[];
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        if (!RegExp(r'\.(md|json|puml|pdf|pptx|docx|xlsx|mp4|lazy\.json)$',
                caseSensitive: false)
            .hasMatch(entity.path)) {
          continue;
        }
        paths.add(entity.path);
      }
      return paths..sort();
    }
    if (package.source == CourseSource.gitee) {
      final paths = <String>[];
      for (final fileName in package.configFiles.keys) {
        paths.add('gitee://${package.courseId}/配置/$fileName');
      }
      return paths..sort();
    }
    return _courseAssetPaths(package.courseId);
  }

  Future<List<Map<String, dynamic>>> _loadPackageGraphFiles(
    CourseDataPackage package,
  ) async {
    final embedded = package.configFiles['graphs'];
    if (embedded is List) {
      return embedded.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    final paths = await _coursePackagePaths(package);
    final graphPaths = paths.where((path) {
      final normalized = path.replaceAll('\\', '/');
      return normalized.contains('/图谱/') &&
          normalized.toLowerCase().endsWith('.json');
    }).toList()
      ..sort();
    final graphs = <Map<String, dynamic>>[];
    for (final path in graphPaths) {
      try {
        final raw = path.startsWith('data/')
            ? await rootBundle.loadString(path)
            : await File(path).readAsString(encoding: utf8);
        final decoded = jsonDecode(raw);
        if (decoded is Map) graphs.add(Map<String, dynamic>.from(decoded));
      } catch (e, st) {
        swallowDebug(e, tag: 'CoursePackageLoader.graph.$path', stack: st);
      }
    }
    return graphs;
  }

  Future<List<String>> _courseAssetPaths(String courseId) async {
    try {
      final raw = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final prefix = 'data/$courseId/';
      final allowed = <String>{
        '大纲',
        '配置',
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
    } catch (e, st) {
      swallowDebug(e, tag: 'CoursePackageLoader', stack: st);
    }
    return [];
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
      'course_template.json',
      'graph_categories.json',
      'homework.json',
      'lab_tasks.json',
      'lazy_generation.json',
      'manifest.json',
      'mock_data.json',
      'platform_readiness.json',
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
    } catch (_) {
      // Optional package files are discovered opportunistically.
    }
  }

  String _cnChapter(int value) {
    const nums = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    if (value > 0 && value < nums.length) return '第${nums[value]}章';
    return '第$value章';
  }

  String _slug(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'graph' : normalized;
  }

  String _hashJson(Map<String, dynamic> value) {
    final raw = const JsonEncoder.withIndent('  ').convert(value);
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> _templateMetadata(CourseDataPackage package) {
    if (package.courseTemplate.isNotEmpty) return package.courseTemplate;
    final template = package.manifest?['template'];
    if (template is Map && template.isNotEmpty) {
      return Map<String, dynamic>.from(template);
    }
    return const {
      'id': 'unknown',
      'version': 'unknown',
      'profile': 'unknown',
      'profile_template_id': 'unknown',
      'profile_template_name': 'unknown',
      'profile_template_version': 'unknown',
    };
  }

  int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(
            value?.toString().replaceAll('%', '').trim() ?? '') ??
        fallback;
  }

  double _asRatio(dynamic value, {double fallback = 0}) {
    final parsed = _asDouble(value, fallback: fallback);
    return parsed > 1 ? parsed / 100 : parsed;
  }

  String _envKey(String text) {
    if (text.contains('实验') || text.contains('实践') || text.contains('实训')) {
      return 'experiment';
    }
    if (text.contains('平时') ||
        text.contains('过程') ||
        text.contains('作业') ||
        text.contains('课堂') ||
        text.contains('测验')) {
      return 'pingshi';
    }
    return 'exam';
  }

  Map<String, double> _normalizeEnvRatios(Map<String, double>? raw) {
    final p = raw?['pingshi'] ?? 0;
    final e = raw?['experiment'] ?? 0;
    final x = raw?['exam'] ?? 0;
    final sum = p + e + x;
    if (sum <= 0) {
      return {'pingshi': 0.20, 'experiment': 0.30, 'exam': 0.50};
    }
    return {'pingshi': p / sum, 'experiment': e / sum, 'exam': x / sum};
  }

  String? _dueDateFromOffset(dynamic raw) {
    final offset = _asInt(raw, fallback: 0);
    if (offset <= 0) return null;
    return DateTime.now().add(Duration(days: offset)).toIso8601String();
  }

  String _categoryFromPath(String courseId, String path) {
    final decoded = _safeDecode(path);
    final assetPrefix = 'data/$courseId/';
    if (decoded.startsWith(assetPrefix)) {
      final rest = decoded.substring(assetPrefix.length);
      return rest.split('/').first;
    }
    final normalized = decoded.replaceAll('\\', '/');
    final marker = '/courses/$courseId/';
    if (normalized.contains(marker)) {
      final rest =
          normalized.substring(normalized.indexOf(marker) + marker.length);
      return rest.split('/').first;
    }
    if (normalized.startsWith('gitee://$courseId/')) {
      final rest = normalized.substring('gitee://$courseId/'.length);
      return rest.split('/').first;
    }
    final parts = normalized.split('/');
    if (parts.length > 1) return parts[parts.length - 2];
    return '课程资源';
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
      // AssetManifest keys are paths and may contain literal percent signs.
    }
    return value;
  }
}

class CoursePackageImportResult {
  final String courseId;
  final String packageVersion;
  final String manifestHash;
  final String templateId;
  final String templateVersion;
  final String templateProfile;
  final String profileTemplateId;
  final String profileTemplateVersion;
  final bool skipped;
  final bool failed;
  final String? reason;
  bool courseUpdated = false;
  int objectivesImported = 0;
  int labTasksImported = 0;
  int homeworksImported = 0;
  int graphsImported = 0;
  int resourcesImported = 0;
  int usersImported = 0;
  int classesImported = 0;

  CoursePackageImportResult({
    required this.courseId,
    required this.packageVersion,
    required this.manifestHash,
    this.templateId = 'unknown',
    this.templateVersion = 'unknown',
    this.templateProfile = 'unknown',
    this.profileTemplateId = 'unknown',
    this.profileTemplateVersion = 'unknown',
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
        'template=$templateId@$templateVersion/$templateProfile '
        'profileTemplate=$profileTemplateId@$profileTemplateVersion '
        'courseUpdated=$courseUpdated objectives=$objectivesImported '
        'labs=$labTasksImported '
        'homeworks=$homeworksImported '
        'graphs=$graphsImported '
        'resources=$resourcesImported users=$usersImported '
        'classes=$classesImported';
  }
}
