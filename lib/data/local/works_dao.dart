import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import '../../services/course_context_service.dart';
import '../../services/notification_service.dart';

/// 作品管理 DAO — 每位同学一个作品（视频演示）/ 视频互动 / 多维排行
class WorksDao {
  final CourseContextService _courseContext = CourseContextService();

  // ══════════════════════════════════════════════════════════
  //  表结构保障（懒迁移，不修改 database_helper）
  // ══════════════════════════════════════════════════════════

  /// 暴露数据库实例（供视频上传等直接更新使用）
  Future<dynamic> getDatabase() async {
    await _ensureWorksTable();
    return DatabaseHelper.instance.database;
  }

  bool _tableEnsured = false;

  Future<void> _ensureWorksTable() async {
    if (_tableEnsured) return;
    final db = await DatabaseHelper.instance.database;

    // student_works 新增列（已存在则静默跳过）
    const newColumns = [
      'ALTER TABLE student_works ADD COLUMN course_id TEXT',
      'ALTER TABLE student_works ADD COLUMN project_id INTEGER',
      'ALTER TABLE student_works ADD COLUMN group_id INTEGER',
      'ALTER TABLE student_works ADD COLUMN video_url TEXT',
      'ALTER TABLE student_works ADD COLUMN thumbnail_url TEXT',
      'ALTER TABLE student_works ADD COLUMN video_duration TEXT',
      'ALTER TABLE student_works ADD COLUMN view_count INTEGER DEFAULT 0',
      'ALTER TABLE student_works ADD COLUMN like_count INTEGER DEFAULT 0',
      'ALTER TABLE student_works ADD COLUMN comment_count INTEGER DEFAULT 0',
      // 学生维度字段（用于多维过滤）
      'ALTER TABLE student_works ADD COLUMN repo TEXT',
      'ALTER TABLE student_works ADD COLUMN class_group TEXT',
      'ALTER TABLE student_works ADD COLUMN project TEXT',
      'ALTER TABLE student_works ADD COLUMN student_role TEXT',
      'ALTER TABLE student_works ADD COLUMN student_name TEXT',
    ];
    for (final sql in newColumns) {
      try {
        await db.execute(sql);
      } catch (_) {} // 列已存在则静默跳过
    }
    try {
      await db.update(
        'student_works',
        {'course_id': CourseContextService.defaultCourseId},
        where: "course_id IS NULL OR course_id = ''",
      );
    } catch (_) {}

    // 评论表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_comments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT,
        user_role TEXT DEFAULT 'student',
        content TEXT NOT NULL,
        parent_id INTEGER,
        created_at TEXT
      )
    ''');

    // 点赞表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_likes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        created_at TEXT,
        UNIQUE(work_id, user_id)
      )
    ''');

    // 观看记录表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_views(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        viewed_at TEXT
      )
    ''');

    _tableEnsured = true;
  }

  Future<({String where, List<Object?> args})> _studentWorksScope({
    String column = 'course_id',
    String? extraWhere,
    List<Object?> extraArgs = const [],
  }) {
    return _courseContext.scopedWhere(
      column: column,
      extraWhere: extraWhere,
      extraArgs: extraArgs,
    );
  }

  // ══════════════════════════════════════════════════════════
  //  作品 CRUD
  // ══════════════════════════════════════════════════════════

  /// 获取作品列表，支持多维排序
  /// [sortBy]: 'latest' / 'most_viewed' / 'most_liked' / 'hottest' / null
  Future<List<Map<String, dynamic>>> getWorks({
    String? workType,
    String? userId,
    String? sortBy,
  }) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final scope = await _studentWorksScope(column: 'w.course_id');
    // 教师评分优先展示；同时计算同学互评均分
    String sql = '''
      SELECT w.*,
             ts.total_score as score, ts.comment as score_comment,
             ts.scorer_name, ts.scored_at,
             ts.score_functionality, ts.score_tech_depth,
             ts.score_integration, ts.score_quality, ts.score_documentation,
             peer.peer_avg, peer.peer_count
      FROM student_works w
      LEFT JOIN (
        SELECT ws.* FROM work_scores ws
        INNER JOIN users u ON u.user_id = ws.scorer_id AND u.role IN ('teacher','admin')
        WHERE 1=1
      ) ts ON ts.work_id = w.id
      LEFT JOIN (
        SELECT work_id,
               ROUND(AVG(total_score), 1) as peer_avg,
               COUNT(*) as peer_count
        FROM work_scores ws2
        LEFT JOIN users u2 ON u2.user_id = ws2.scorer_id
        WHERE u2.role IS NULL OR u2.role = 'student'
        GROUP BY work_id
      ) peer ON peer.work_id = w.id
      WHERE ${scope.where}
    ''';
    final args = <Object?>[...scope.args];
    if (workType != null && workType != '全部') {
      sql += ' AND w.work_type = ?';
      args.add(workType);
    }
    if (userId != null) {
      sql += ' AND w.user_id = ?';
      args.add(userId);
    }
    final orderBy = switch (sortBy) {
      'most_viewed' => 'w.view_count DESC',
      'most_liked' => 'w.like_count DESC',
      'hottest' => '(w.like_count + w.comment_count) DESC',
      'score' => 'COALESCE(ts.total_score, 0) DESC',
      _ => 'w.created_at DESC',
    };
    sql += ' ORDER BY $orderBy';
    return db.rawQuery(sql, args);
  }

  Future<Map<String, dynamic>?> getWork(int id) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final scope = await _studentWorksScope(
      column: 'w.course_id',
      extraWhere: 'w.id = ?',
      extraArgs: [id],
    );
    final list = await db.rawQuery('''
      SELECT w.*,
             ts.total_score as score, ts.comment as score_comment,
             ts.scorer_name, ts.scored_at,
             ts.score_functionality, ts.score_tech_depth,
             ts.score_integration, ts.score_quality, ts.score_documentation,
             peer.peer_avg, peer.peer_count
      FROM student_works w
      LEFT JOIN (
        SELECT ws.* FROM work_scores ws
        INNER JOIN users u ON u.user_id = ws.scorer_id AND u.role IN ('teacher','admin')
      ) ts ON ts.work_id = w.id
      LEFT JOIN (
        SELECT work_id,
               ROUND(AVG(total_score), 1) as peer_avg,
               COUNT(*) as peer_count
        FROM work_scores ws2
        LEFT JOIN users u2 ON u2.user_id = ws2.scorer_id
        WHERE u2.role IS NULL OR u2.role = 'student'
        GROUP BY work_id
      ) peer ON peer.work_id = w.id
      WHERE ${scope.where}
    ''', scope.args);
    return list.isNotEmpty ? list.first : null;
  }

  Future<int> addWork({
    required String title,
    String? description,
    String? techStack,
    String workType = '综合项目',
    String? groupName,
    String? leaderName,
    String? userId,
    String? filePath,
    String? fileSize,
    String status = '待提交',
    List<String>? tags,
    int? projectId,
    int? groupId,
    String? videoUrl,
    String? thumbnailUrl,
    String? videoDuration,
    int viewCount = 0,
    int likeCount = 0,
    int commentCount = 0,
    // 学生维度字段
    String? repo,
    String? classGroup,
    String? project,
    String? studentRole,
    String? studentName,
  }) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final courseId = await _courseContext.activeCourseId();
    return db.insert('student_works', {
      'course_id': courseId,
      'title': title,
      'description': description,
      'tech_stack': techStack,
      'work_type': workType,
      'group_name': groupName,
      'leader_name': leaderName,
      'user_id': userId,
      'file_path': filePath,
      'file_size': fileSize,
      'status': status,
      'tags': tags != null ? jsonEncode(tags) : null,
      'project_id': projectId,
      'group_id': groupId,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'video_duration': videoDuration,
      'view_count': viewCount,
      'like_count': likeCount,
      'comment_count': commentCount,
      'repo': repo,
      'class_group': classGroup,
      'project': project,
      'student_role': studentRole,
      'student_name': studentName,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateWork(int id, Map<String, dynamic> data) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update('student_works', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> submitWork(int id) async {
    final result = updateWork(id, {
      'status': '已提交',
      'submit_time': DateTime.now().toIso8601String(),
    });
    // 通知教师
    try {
      final work = await getWork(id);
      if (work != null) {
        NotificationService().notifyWorkSubmission(
          studentId: work['user_id'] as String? ?? '',
          studentName: work['student_name'] as String? ??
              work['leader_name'] as String? ??
              '',
          workTitle: work['title'] as String? ?? '未命名作品',
        );
      }
    } catch (e) {
      debugPrint('WorksDao: 发送作品提交通知失败 — $e');
    }
    return result;
  }

  Future<int> deleteWork(int id) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    return db.delete('student_works', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════
  //  视频互动：播放 / 点赞 / 评论
  // ══════════════════════════════════════════════════════════

  /// 记录一次播放
  Future<void> recordView(int workId, String userId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    await db.insert('work_views', {
      'work_id': workId,
      'user_id': userId,
      'viewed_at': DateTime.now().toIso8601String(),
    });
    await db.rawUpdate(
      'UPDATE student_works SET view_count = view_count + 1 WHERE id = ?',
      [workId],
    );
  }

  /// 切换点赞状态，返回新的点赞状态
  Future<bool> toggleLike(int workId, String userId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query('work_likes',
        where: 'work_id = ? AND user_id = ?', whereArgs: [workId, userId]);
    if (existing.isNotEmpty) {
      // 取消点赞
      await db.delete('work_likes',
          where: 'work_id = ? AND user_id = ?', whereArgs: [workId, userId]);
      await db.rawUpdate(
        'UPDATE student_works SET like_count = MAX(0, like_count - 1) WHERE id = ?',
        [workId],
      );
      return false;
    } else {
      // 点赞
      await db.insert('work_likes', {
        'work_id': workId,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.rawUpdate(
        'UPDATE student_works SET like_count = like_count + 1 WHERE id = ?',
        [workId],
      );
      return true;
    }
  }

  /// 检查是否已点赞
  Future<bool> isLiked(int workId, String userId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final result = await db.query('work_likes',
        where: 'work_id = ? AND user_id = ?', whereArgs: [workId, userId]);
    return result.isNotEmpty;
  }

  /// 添加评论
  Future<int> addComment({
    required int workId,
    required String userId,
    String? userName,
    String userRole = 'student',
    required String content,
    int? parentId,
  }) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('work_comments', {
      'work_id': workId,
      'user_id': userId,
      'user_name': userName,
      'user_role': userRole,
      'content': content,
      'parent_id': parentId,
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.rawUpdate(
      'UPDATE student_works SET comment_count = comment_count + 1 WHERE id = ?',
      [workId],
    );
    return id;
  }

  /// 获取评论列表
  Future<List<Map<String, dynamic>>> getComments(int workId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    return db.query('work_comments',
        where: 'work_id = ?', whereArgs: [workId], orderBy: 'created_at ASC');
  }

  /// 删除评论
  Future<void> deleteComment(int commentId, int workId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    await db.delete('work_comments', where: 'id = ?', whereArgs: [commentId]);
    await db.rawUpdate(
      'UPDATE student_works SET comment_count = MAX(0, comment_count - 1) WHERE id = ?',
      [workId],
    );
  }

  // ══════════════════════════════════════════════════════════
  //  作品评分
  // ══════════════════════════════════════════════════════════

  Future<int> scoreWork({
    required int workId,
    String? scorerId,
    String? scorerName,
    required int functionality,
    required int techDepth,
    required int integration,
    required int quality,
    required int documentation,
    String? comment,
  }) async {
    final total =
        functionality + techDepth + integration + quality + documentation;
    final db = await DatabaseHelper.instance.database;

    // 先检查该评分人是否已为此作品评分
    final existing = await db.query('work_scores',
        where: 'work_id = ? AND scorer_id = ?', whereArgs: [workId, scorerId]);
    if (existing.isNotEmpty) {
      // 更新该评分人的评分
      await db.update(
          'work_scores',
          {
            'scorer_name': scorerName,
            'score_functionality': functionality,
            'score_tech_depth': techDepth,
            'score_integration': integration,
            'score_quality': quality,
            'score_documentation': documentation,
            'total_score': total,
            'comment': comment,
            'scored_at': DateTime.now().toIso8601String(),
          },
          where: 'work_id = ? AND scorer_id = ?',
          whereArgs: [workId, scorerId]);
      await updateWork(workId, {'status': '已评分'});
      return existing.first['id'] as int;
    }

    // 新增评分（该评分人首次评此作品）
    final result = await db.insert('work_scores', {
      'work_id': workId,
      'scorer_id': scorerId,
      'scorer_name': scorerName,
      'score_functionality': functionality,
      'score_tech_depth': techDepth,
      'score_integration': integration,
      'score_quality': quality,
      'score_documentation': documentation,
      'total_score': total,
      'comment': comment,
      'scored_at': DateTime.now().toIso8601String(),
    });
    await updateWork(workId, {'status': '已评分'});
    return result;
  }

  Future<List<Map<String, dynamic>>> getScoreRecords() async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _studentWorksScope(column: 'sw.course_id');
    return db.rawQuery('''
      SELECT ws.*, sw.title as work_title, sw.group_name, sw.work_type,
             sw.student_name, sw.repo
      FROM work_scores ws
      JOIN student_works sw ON ws.work_id = sw.id
      WHERE ${scope.where}
      ORDER BY ws.scored_at DESC
    ''', scope.args);
  }

  /// 获取某个作品的所有评分记录（教师 + 同学互评）
  Future<List<Map<String, dynamic>>> getWorkScores(int workId) async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT ws.*, COALESCE(u.role, 'student') as scorer_role
      FROM work_scores ws
      LEFT JOIN users u ON u.user_id = ws.scorer_id
      WHERE ws.work_id = ?
      ORDER BY ws.scored_at DESC
    ''', [workId]);
  }

  /// 检查某评分人是否已为指定作品评分
  Future<bool> hasScored(int workId, String scorerId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query('work_scores',
        where: 'work_id = ? AND scorer_id = ?', whereArgs: [workId, scorerId]);
    return result.isNotEmpty;
  }

  // ══════════════════════════════════════════════════════════
  //  多维排行榜
  // ══════════════════════════════════════════════════════════

  /// 获取排行榜
  /// [dimension]: 'comprehensive' / 'score' / 'views' / 'likes' / 'comments'
  Future<List<Map<String, dynamic>>> getLeaderboard({
    String dimension = 'comprehensive',
  }) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final scope = await _studentWorksScope(column: 'sw.course_id');

    if (dimension == 'score') {
      return db.rawQuery('''
        SELECT sw.*,
               ts.total_score as score, ts.comment,
               ts.scorer_name, sw.view_count, sw.like_count, sw.comment_count
        FROM student_works sw
        JOIN (
          SELECT ws.* FROM work_scores ws
          INNER JOIN users u ON u.user_id = ws.scorer_id AND u.role IN ('teacher','admin')
        ) ts ON ts.work_id = sw.id
        WHERE ${scope.where}
        ORDER BY ts.total_score DESC
      ''', scope.args);
    }

    if (dimension == 'views') {
      return db.rawQuery('''
        SELECT sw.*,
               ts.total_score as score, ts.comment,
               ts.scorer_name, sw.view_count, sw.like_count, sw.comment_count
        FROM student_works sw
        LEFT JOIN (
          SELECT ws.* FROM work_scores ws
          INNER JOIN users u ON u.user_id = ws.scorer_id AND u.role IN ('teacher','admin')
        ) ts ON ts.work_id = sw.id
        WHERE ${scope.where} AND sw.status IN ('已提交', '已评分')
        ORDER BY sw.view_count DESC
      ''', scope.args);
    }

    if (dimension == 'likes') {
      return db.rawQuery('''
        SELECT sw.*,
               ts.total_score as score, ts.comment,
               ts.scorer_name, sw.view_count, sw.like_count, sw.comment_count
        FROM student_works sw
        LEFT JOIN (
          SELECT ws.* FROM work_scores ws
          INNER JOIN users u ON u.user_id = ws.scorer_id AND u.role IN ('teacher','admin')
        ) ts ON ts.work_id = sw.id
        WHERE ${scope.where} AND sw.status IN ('已提交', '已评分')
        ORDER BY sw.like_count DESC
      ''', scope.args);
    }

    if (dimension == 'comments') {
      return db.rawQuery('''
        SELECT sw.*,
               ts.total_score as score, ts.comment,
               ts.scorer_name, sw.view_count, sw.like_count, sw.comment_count
        FROM student_works sw
        LEFT JOIN (
          SELECT ws.* FROM work_scores ws
          INNER JOIN users u ON u.user_id = ws.scorer_id AND u.role IN ('teacher','admin')
        ) ts ON ts.work_id = sw.id
        WHERE ${scope.where} AND sw.status IN ('已提交', '已评分')
        ORDER BY sw.comment_count DESC
      ''', scope.args);
    }

    // comprehensive: 加权综合排行
    // score×0.4 + normalized(views)×0.3 + normalized(likes)×0.2 + normalized(comments)×0.1
    final allWorks = await db.rawQuery('''
      SELECT sw.*,
             ts.total_score as score, ts.comment,
             ts.scorer_name, sw.view_count, sw.like_count, sw.comment_count
      FROM student_works sw
      LEFT JOIN (
        SELECT ws.* FROM work_scores ws
        INNER JOIN users u ON u.user_id = ws.scorer_id AND u.role IN ('teacher','admin')
      ) ts ON ts.work_id = sw.id
      WHERE ${scope.where} AND sw.status IN ('已提交', '已评分')
    ''', scope.args);

    if (allWorks.isEmpty) return [];

    // 找到各维度最大值用于归一化
    double maxScore = 1;
    double maxViews = 1;
    double maxLikes = 1;
    double maxComments = 1;
    for (final w in allWorks) {
      final s = (w['score'] as num?)?.toDouble() ?? 0;
      final v = (w['view_count'] as num?)?.toDouble() ?? 0;
      final l = (w['like_count'] as num?)?.toDouble() ?? 0;
      final c = (w['comment_count'] as num?)?.toDouble() ?? 0;
      if (s > maxScore) maxScore = s;
      if (v > maxViews) maxViews = v;
      if (l > maxLikes) maxLikes = l;
      if (c > maxComments) maxComments = c;
    }

    // 计算综合分并排序
    final ranked = allWorks.map((w) {
      final s = (w['score'] as num?)?.toDouble() ?? 0;
      final v = (w['view_count'] as num?)?.toDouble() ?? 0;
      final l = (w['like_count'] as num?)?.toDouble() ?? 0;
      final c = (w['comment_count'] as num?)?.toDouble() ?? 0;
      final composite = (s / maxScore) * 40 +
          (v / maxViews) * 30 +
          (l / maxLikes) * 20 +
          (c / maxComments) * 10;
      final m = Map<String, dynamic>.from(w);
      m['composite_score'] = composite;
      return m;
    }).toList();
    ranked.sort((a, b) =>
        ((b['composite_score'] as double) - (a['composite_score'] as double))
            .sign
            .toInt());
    return ranked;
  }

  /// 统计概览
  Future<Map<String, dynamic>> getOverview() async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final scope = await _studentWorksScope();
    final aliasScope = await _studentWorksScope(column: 'sw.course_id');
    final totalWorks = await db.rawQuery(
        'SELECT COUNT(*) as c FROM student_works WHERE ${scope.where}',
        scope.args);
    final scored = await db.rawQuery('''
      SELECT COUNT(*) as c, AVG(total_score) as avg, MAX(total_score) as max_s
      FROM work_scores ws
      JOIN student_works sw ON ws.work_id = sw.id
      WHERE ${aliasScope.where}
    ''', aliasScope.args);
    final viewSum = await db.rawQuery(
        'SELECT COALESCE(SUM(view_count), 0) as s FROM student_works WHERE ${scope.where}',
        scope.args);
    final likeSum = await db.rawQuery(
        'SELECT COALESCE(SUM(like_count), 0) as s FROM student_works WHERE ${scope.where}',
        scope.args);
    final commentSum = await db.rawQuery(
        'SELECT COALESCE(SUM(comment_count), 0) as s FROM student_works WHERE ${scope.where}',
        scope.args);
    final count = (totalWorks.first['c'] as int?) ?? 0;
    final scoredCount = (scored.first['c'] as int?) ?? 0;
    return {
      'total_works': count,
      'scored_count': scoredCount,
      'avg_score': scoredCount > 0
          ? ((scored.first['avg'] as num?)?.toDouble() ?? 0.0)
          : 0.0,
      'max_score': (scored.first['max_s'] as int?) ?? 0,
      'total_views': (viewSum.first['s'] as int?) ?? 0,
      'total_likes': (likeSum.first['s'] as int?) ?? 0,
      'total_comments': (commentSum.first['s'] as int?) ?? 0,
    };
  }

  // ══════════════════════════════════════════════════════════
  //  从 student_group_data.json 同步学生作品（每人一个）
  // ══════════════════════════════════════════════════════════

  /// 从学生列表同步作品。每位同学一个作品，以 user_id 为键幂等。
  /// 会主动清理不属于真实学生的旧虚拟数据。
  Future<void> syncStudentWorks(List<Map<String, dynamic>> students) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;

    // ── 清理旧虚拟数据：删除不属于真实学生的作品 ──────────────
    final validUserIds = students
        .map((s) => s['userId'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    final scope = await _studentWorksScope();
    final allWorks = await db.query(
      'student_works',
      where: scope.where,
      whereArgs: scope.args,
    );
    for (final w in allWorks) {
      final wUserId = w['user_id'] as String?;
      if (wUserId == null ||
          wUserId.isEmpty ||
          !validUserIds.contains(wUserId)) {
        final wId = w['id'] as int;
        await db
            .delete('work_comments', where: 'work_id = ?', whereArgs: [wId]);
        await db.delete('work_likes', where: 'work_id = ?', whereArgs: [wId]);
        await db.delete('work_views', where: 'work_id = ?', whereArgs: [wId]);
        await db.delete('work_scores', where: 'work_id = ?', whereArgs: [wId]);
        await db.delete('student_works', where: 'id = ?', whereArgs: [wId]);
      }
    }

    for (final s in students) {
      final sUserId = s['userId'] as String?;
      if (sUserId == null || sUserId.isEmpty) continue;

      // 已存在则跳过
      final existingScope = await _studentWorksScope(
        extraWhere: 'user_id = ?',
        extraArgs: [sUserId],
      );
      final existing = await db.query(
        'student_works',
        where: existingScope.where,
        whereArgs: existingScope.args,
      );
      if (existing.isNotEmpty) continue;

      // 从技术栈拆出标签
      final tags = <String>[];
      final techStr = s['techStack'] as String?;
      if (techStr != null) {
        tags.addAll(techStr
            .split(RegExp(r'[+,、，\s]+'))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty));
      }

      await addWork(
        title: s['project'] as String? ?? '未命名项目',
        description:
            s['feature_detail'] as String? ?? s['features'] as String? ?? '',
        techStack: techStr,
        workType: '综合项目',
        groupName: s['repo'] as String?,
        leaderName: s['name'] as String?,
        userId: sUserId,
        status: '待提交',
        tags: tags.isNotEmpty ? tags : null,
        repo: s['repo'] as String?,
        classGroup: s['classGroup'] as String?,
        project: s['project'] as String?,
        studentRole: s['role'] as String?,
        studentName: s['name'] as String?,
      );
    }
  }

  /// 清除旧版虚假互动数据（评分、评论、虚假播放/点赞计数）
  /// 调用一次后，将所有作品还原为"待提交"状态（无视频、无分数、无互动）
  Future<void> cleanupFakeData() async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;

    // 删除所有评分、评论、点赞、浏览记录
    await db.delete('work_scores');
    await db.delete('work_comments');
    await db.delete('work_likes');
    await db.delete('work_views');

    // 重置所有作品的状态和虚假计数
    await db.update('student_works', {
      'status': '待提交',
      'video_url': null,
      'video_duration': null,
      'view_count': 0,
      'like_count': 0,
      'comment_count': 0,
      'submit_time': null,
    });
    debugPrint('WorksDao: 已清除旧版虚假互动数据');
  }

  // ══════════════════════════════════════════════════════════
  //  从考核项目同步作品（兼容旧接口）
  // ══════════════════════════════════════════════════════════

  /// 从 assessment_projects + assessment_groups 同步作品条目
  Future<void> syncFromAssessmentProjects() async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final projects = await db.rawQuery('''
      SELECT p.*, g.name as group_name, g.leader as leader_name
      FROM assessment_projects p
      LEFT JOIN assessment_groups g ON p.group_id = g.id
    ''');
    for (final p in projects) {
      final projectId = p['id'] as int;
      final existingScope = await _studentWorksScope(
        extraWhere: 'project_id = ?',
        extraArgs: [projectId],
      );
      final existing = await db.query(
        'student_works',
        where: existingScope.where,
        whereArgs: existingScope.args,
      );
      if (existing.isEmpty) {
        await addWork(
          title: p['name'] as String? ?? '未命名项目',
          description: p['description'] as String?,
          techStack: p['tech_stack'] as String?,
          workType: '综合项目',
          groupName: p['group_name'] as String?,
          leaderName: p['leader_name'] as String?,
          projectId: projectId,
          groupId: p['group_id'] as int?,
          status: '已提交',
        );
      }
    }
  }

  /// 通过项目 ID 查找对应作品
  Future<Map<String, dynamic>?> getWorkByProjectId(int projectId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final scope = await _studentWorksScope(
      extraWhere: 'project_id = ?',
      extraArgs: [projectId],
    );
    final list = await db.query(
      'student_works',
      where: scope.where,
      whereArgs: scope.args,
    );
    return list.isNotEmpty ? list.first : null;
  }

  /// 通过学生 ID 查找对应作品
  Future<Map<String, dynamic>?> getWorkByUserId(String userId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final scope = await _studentWorksScope(
      extraWhere: 'user_id = ?',
      extraArgs: [userId],
    );
    final list = await db.query(
      'student_works',
      where: scope.where,
      whereArgs: scope.args,
    );
    return list.isNotEmpty ? list.first : null;
  }
}
