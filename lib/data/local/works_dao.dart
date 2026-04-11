import 'dart:convert';
import 'dart:math';
import 'database_helper.dart';

/// 作品管理 DAO — 每位同学一个作品（视频演示）/ 视频互动 / 多维排行
class WorksDao {
  // ══════════════════════════════════════════════════════════
  //  表结构保障（懒迁移，不修改 database_helper）
  // ══════════════════════════════════════════════════════════

  bool _tableEnsured = false;

  Future<void> _ensureWorksTable() async {
    if (_tableEnsured) return;
    final db = await DatabaseHelper.instance.database;

    // student_works 新增列（已存在则静默跳过）
    const newColumns = [
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
    String sql = '''
      SELECT w.*, ws.total_score as score, ws.comment as score_comment,
             ws.scorer_name, ws.scored_at,
             ws.score_functionality, ws.score_tech_depth,
             ws.score_integration, ws.score_quality, ws.score_documentation
      FROM student_works w
      LEFT JOIN work_scores ws ON ws.work_id = w.id
      WHERE 1=1
    ''';
    final args = <dynamic>[];
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
      'score' => 'COALESCE(ws.total_score, 0) DESC',
      _ => 'w.created_at DESC',
    };
    sql += ' ORDER BY $orderBy';
    return db.rawQuery(sql, args);
  }

  Future<Map<String, dynamic>?> getWork(int id) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final list = await db.rawQuery('''
      SELECT w.*, ws.total_score as score, ws.comment as score_comment,
             ws.scorer_name, ws.scored_at,
             ws.score_functionality, ws.score_tech_depth,
             ws.score_integration, ws.score_quality, ws.score_documentation
      FROM student_works w
      LEFT JOIN work_scores ws ON ws.work_id = w.id
      WHERE w.id = ?
    ''', [id]);
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
    return db.insert('student_works', {
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
    return db.update('student_works', data,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> submitWork(int id) async {
    return updateWork(id, {
      'status': '已提交',
      'submit_time': DateTime.now().toIso8601String(),
    });
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
        where: 'work_id = ? AND user_id = ?',
        whereArgs: [workId, userId]);
    if (existing.isNotEmpty) {
      // 取消点赞
      await db.delete('work_likes',
          where: 'work_id = ? AND user_id = ?',
          whereArgs: [workId, userId]);
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
        where: 'work_id = ? AND user_id = ?',
        whereArgs: [workId, userId]);
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
        where: 'work_id = ?',
        whereArgs: [workId],
        orderBy: 'created_at ASC');
  }

  /// 删除评论
  Future<void> deleteComment(int commentId, int workId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    await db.delete('work_comments',
        where: 'id = ?', whereArgs: [commentId]);
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

    // 先检查是否已评分
    final existing = await db.query('work_scores',
        where: 'work_id = ?', whereArgs: [workId]);
    if (existing.isNotEmpty) {
      // 更新评分
      await db.update(
          'work_scores',
          {
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
          },
          where: 'work_id = ?',
          whereArgs: [workId]);
      await updateWork(workId, {'status': '已评分'});
      return existing.first['id'] as int;
    }

    // 新增评分
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
    return db.rawQuery('''
      SELECT ws.*, sw.title as work_title, sw.group_name, sw.work_type,
             sw.student_name, sw.repo
      FROM work_scores ws
      JOIN student_works sw ON ws.work_id = sw.id
      ORDER BY ws.scored_at DESC
    ''');
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

    if (dimension == 'score') {
      return db.rawQuery('''
        SELECT sw.*, ws.total_score as score, ws.comment,
               ws.scorer_name, sw.view_count, sw.like_count, sw.comment_count
        FROM student_works sw
        JOIN work_scores ws ON ws.work_id = sw.id
        ORDER BY ws.total_score DESC
      ''');
    }

    if (dimension == 'views') {
      return db.rawQuery('''
        SELECT sw.*, ws.total_score as score, ws.comment,
               ws.scorer_name, sw.view_count, sw.like_count, sw.comment_count
        FROM student_works sw
        LEFT JOIN work_scores ws ON ws.work_id = sw.id
        WHERE sw.status IN ('已提交', '已评分')
        ORDER BY sw.view_count DESC
      ''');
    }

    if (dimension == 'likes') {
      return db.rawQuery('''
        SELECT sw.*, ws.total_score as score, ws.comment,
               ws.scorer_name, sw.view_count, sw.like_count, sw.comment_count
        FROM student_works sw
        LEFT JOIN work_scores ws ON ws.work_id = sw.id
        WHERE sw.status IN ('已提交', '已评分')
        ORDER BY sw.like_count DESC
      ''');
    }

    if (dimension == 'comments') {
      return db.rawQuery('''
        SELECT sw.*, ws.total_score as score, ws.comment,
               ws.scorer_name, sw.view_count, sw.like_count, sw.comment_count
        FROM student_works sw
        LEFT JOIN work_scores ws ON ws.work_id = sw.id
        WHERE sw.status IN ('已提交', '已评分')
        ORDER BY sw.comment_count DESC
      ''');
    }

    // comprehensive: 加权综合排行
    // score×0.4 + normalized(views)×0.3 + normalized(likes)×0.2 + normalized(comments)×0.1
    final allWorks = await db.rawQuery('''
      SELECT sw.*, ws.total_score as score, ws.comment,
             ws.scorer_name, sw.view_count, sw.like_count, sw.comment_count
      FROM student_works sw
      LEFT JOIN work_scores ws ON ws.work_id = sw.id
      WHERE sw.status IN ('已提交', '已评分')
    ''');

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
    final totalWorks = await db.rawQuery(
        'SELECT COUNT(*) as c FROM student_works');
    final scored = await db.rawQuery('''
      SELECT COUNT(*) as c, AVG(total_score) as avg, MAX(total_score) as max_s
      FROM work_scores
    ''');
    final viewSum = await db.rawQuery(
        'SELECT COALESCE(SUM(view_count), 0) as s FROM student_works');
    final likeSum = await db.rawQuery(
        'SELECT COALESCE(SUM(like_count), 0) as s FROM student_works');
    final commentSum = await db.rawQuery(
        'SELECT COALESCE(SUM(comment_count), 0) as s FROM student_works');
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
  /// 首次同步时自动生成演示互动数据（评论、评分）。
  /// 会主动清理不属于真实学生的旧虚拟数据。
  Future<void> syncStudentWorks(
      List<Map<String, dynamic>> students) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final rng = Random(42); // 固定种子保证一致性

    // ── 清理旧虚拟数据：删除不属于真实学生的作品 ──────────────
    final validUserIds = students
        .map((s) => s['userId'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    final allWorks = await db.query('student_works');
    for (final w in allWorks) {
      final wUserId = w['user_id'] as String?;
      if (wUserId == null ||
          wUserId.isEmpty ||
          !validUserIds.contains(wUserId)) {
        final wId = w['id'] as int;
        await db.delete('work_comments',
            where: 'work_id = ?', whereArgs: [wId]);
        await db.delete('work_likes',
            where: 'work_id = ?', whereArgs: [wId]);
        await db.delete('work_views',
            where: 'work_id = ?', whereArgs: [wId]);
        await db.delete('work_scores',
            where: 'work_id = ?', whereArgs: [wId]);
        await db.delete('student_works',
            where: 'id = ?', whereArgs: [wId]);
      }
    }

    int newCount = 0;
    final newWorkIds = <int>[];

    for (final s in students) {
      final sUserId = s['userId'] as String?;
      if (sUserId == null || sUserId.isEmpty) continue;

      // 已存在则跳过
      final existing = await db.query('student_works',
          where: 'user_id = ?', whereArgs: [sUserId]);
      if (existing.isNotEmpty) continue;

      // 生成演示用视频时长 02:15 ~ 06:59
      final mins = 2 + rng.nextInt(5);
      final secs = rng.nextInt(60);
      final duration =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

      // 从技术栈拆出标签
      final tags = <String>[];
      final techStr = s['techStack'] as String?;
      if (techStr != null) {
        tags.addAll(techStr
            .split(RegExp(r'[+,、，\s]+'))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty));
      }

      final wId = await addWork(
        title: s['project'] as String? ?? '未命名项目',
        description: s['feature_detail'] as String? ??
            s['features'] as String? ??
            '',
        techStack: techStr,
        workType: '综合项目',
        groupName: s['repo'] as String?,
        leaderName: s['name'] as String?,
        userId: sUserId,
        status: '已提交',
        tags: tags.isNotEmpty ? tags : null,
        videoUrl: 'assets/videos/demo_$sUserId.mp4',
        videoDuration: duration,
        viewCount: 20 + rng.nextInt(200),
        likeCount: 3 + rng.nextInt(50),
        commentCount: 0, // 后面通过 addComment 自增
        repo: s['repo'] as String?,
        classGroup: s['classGroup'] as String?,
        project: s['project'] as String?,
        studentRole: s['role'] as String?,
        studentName: s['name'] as String?,
      );
      newWorkIds.add(wId);
      newCount++;
    }

    // 首次同步时生成演示互动数据
    if (newCount > 0) {
      await _generateDemoInteractions(students, newWorkIds, rng);
    }
  }

  /// 生成演示互动数据（评论 + 部分评分）
  Future<void> _generateDemoInteractions(
    List<Map<String, dynamic>> students,
    List<int> workIds,
    Random rng,
  ) async {
    if (workIds.isEmpty || students.isEmpty) return;
    final db = await DatabaseHelper.instance.database;

    // 获取刚创建的作品
    final works = <Map<String, dynamic>>[];
    for (final wId in workIds) {
      final w = await db.query('student_works',
          where: 'id = ?', whereArgs: [wId]);
      if (w.isNotEmpty) works.add(w.first);
    }
    if (works.isEmpty) return;

    // ── 教师评论：~30% 的作品 ───────────────────────────────
    const teacherComments = [
      '技术实现完整，UI交互流畅，值得肯定。',
      '功能完成度高，建议进一步优化性能。',
      '代码结构清晰，文档规范，整体不错。',
      '跨平台适配做得不错，AI功能有亮点。',
      '整体完成度良好，建议加强异常处理和测试覆盖。',
      '功能丰富，技术栈运用熟练，继续保持。',
      '界面设计美观，交互逻辑清晰，值得推广。',
      '架构设计合理，代码质量较高。',
      '创新点突出，实用性强，期待进一步完善。',
      '基础功能扎实，建议增加更多差异化特色。',
    ];

    for (final w in works) {
      if (rng.nextDouble() < 0.30) {
        await addComment(
          workId: w['id'] as int,
          userId: '419116',
          userName: '刘东良',
          userRole: 'teacher',
          content: teacherComments[rng.nextInt(teacherComments.length)],
        );
      }
    }

    // ── 同学互评：每个作品 0-3 条 ────────────────────────────
    const peerComments = [
      '学习了，很有启发！',
      '功能做得很完整，佩服。',
      'UI设计很好看，交互流畅。',
      '技术栈选择很合理。',
      '值得学习的项目！',
      '期待后续迭代更新。',
      '代码写得很规范，值得参考。',
      'AI功能很实用，创意不错。',
      '界面交互很流畅，用户体验很好。',
      '这个功能设计得很巧妙。',
      '演示视频做得很清晰。',
      '跨平台适配做得不错。',
      '项目完成度很高，赞！',
      '文档写得很详细。',
    ];

    for (final w in works) {
      final numComments = rng.nextInt(4); // 0-3
      final workUserId = w['user_id'] as String?;
      for (int i = 0; i < numComments; i++) {
        final commenter = students[rng.nextInt(students.length)];
        final commenterId = commenter['userId'] as String?;
        // 不评论自己的作品
        if (commenterId == workUserId) continue;
        await addComment(
          workId: w['id'] as int,
          userId: commenterId ?? '',
          userName: commenter['name'] as String?,
          userRole: 'student',
          content: peerComments[rng.nextInt(peerComments.length)],
        );
      }
    }

    // ── 教师评分：~25% 的作品 ────────────────────────────────
    const scoreComments = [
      '功能完整，技术栈选型合理，UI 交互流畅。',
      '学习功能全面，建议优化数据同步性能。',
      '技术实现扎实，跨平台适配值得肯定。',
      '交互设计完善，核心功能亮点突出。',
      '整体表现良好，文档和代码规范。',
      '创新性强，AI 功能集成出色。',
      '基础功能完整，建议加强性能优化。',
      '项目结构清晰，团队协作成果明显。',
    ];

    for (final w in works) {
      if (rng.nextDouble() < 0.25) {
        final func = 16 + rng.nextInt(10); // 16-25
        final tech = 12 + rng.nextInt(9); // 12-20
        final integ = 16 + rng.nextInt(10); // 16-25
        final qual = 8 + rng.nextInt(8); // 8-15
        final doc = 8 + rng.nextInt(8); // 8-15
        await scoreWork(
          workId: w['id'] as int,
          scorerId: '419116',
          scorerName: '刘东良',
          functionality: func,
          techDepth: tech,
          integration: integ,
          quality: qual,
          documentation: doc,
          comment: scoreComments[rng.nextInt(scoreComments.length)],
        );
      }
    }
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
      final existing = await db.query('student_works',
          where: 'project_id = ?', whereArgs: [projectId]);
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
    final list = await db.query('student_works',
        where: 'project_id = ?', whereArgs: [projectId]);
    return list.isNotEmpty ? list.first : null;
  }

  /// 通过学生 ID 查找对应作品
  Future<Map<String, dynamic>?> getWorkByUserId(String userId) async {
    await _ensureWorksTable();
    final db = await DatabaseHelper.instance.database;
    final list = await db.query('student_works',
        where: 'user_id = ?', whereArgs: [userId]);
    return list.isNotEmpty ? list.first : null;
  }
}
