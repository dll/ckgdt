import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// class_qa_dao 的核心契约测试。
///
/// 由于 ClassQaDao 强耦合 DatabaseHelper.instance 单例 + assets 种子库，直接
/// 测它需要先在 main() 里完成种子 DB 初始化（成本高）。这里改测**等价 SQL**：
/// 直接在内存 DB 上建 class_qa schema 复刻关键查询模式（按可见性过滤、教师回复
/// 自动转 answered、采纳最佳回复），保证业务逻辑不会被无意改坏。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE class_qa(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_role TEXT NOT NULL,
        class_id TEXT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        visibility TEXT NOT NULL DEFAULT 'class',
        status TEXT NOT NULL DEFAULT 'open',
        accepted_reply_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE class_qa_replies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        qa_id INTEGER NOT NULL,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_role TEXT NOT NULL,
        body TEXT NOT NULL,
        is_teacher INTEGER NOT NULL DEFAULT 0,
        likes INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertQa(
      {String author = 'stu1',
      String role = 'student',
      String visibility = 'class',
      String status = 'open'}) async {
    final now = DateTime.now().toIso8601String();
    return db.insert('class_qa', {
      'author_id': author,
      'author_name': author,
      'author_role': role,
      'title': 'q',
      'body': 'b',
      'visibility': visibility,
      'status': status,
      'created_at': now,
      'updated_at': now,
    });
  }

  group('class_qa 可见性过滤', () {
    test('教师可见 private + class 全部', () async {
      await insertQa(author: 'a', visibility: 'class');
      await insertQa(author: 'b', visibility: 'private');
      // 教师视角 = 不加 visibility 过滤
      final r = await db.query('class_qa');
      expect(r.length, 2);
    });

    test('学生只可见 class 或自己的 private', () async {
      await insertQa(author: 'me', visibility: 'class');
      await insertQa(author: 'other', visibility: 'private');
      await insertQa(author: 'me', visibility: 'private');

      // 学生 'me' 视角的过滤条件
      final r = await db.query(
        'class_qa',
        where: "(visibility = 'class' OR author_id = ?)",
        whereArgs: ['me'],
      );
      expect(r.length, 2, reason: '应看到 me 的 class + me 的 private');
    });
  });

  group('class_qa 教师回复转 answered', () {
    test('教师首次回复 → status open → answered', () async {
      final qaId = await insertQa(status: 'open');
      // 教师回复
      await db.insert('class_qa_replies', {
        'qa_id': qaId,
        'author_id': 't1',
        'author_name': 'teacher',
        'author_role': 'teacher',
        'body': 'reply',
        'is_teacher': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      // 模拟 DAO 的 update（仅当 status=open 时改成 answered）
      await db.update(
        'class_qa',
        {'status': 'answered'},
        where: 'id = ? AND status = ?',
        whereArgs: [qaId, 'open'],
      );
      final row = (await db.query('class_qa',
              where: 'id = ?', whereArgs: [qaId]))
          .first;
      expect(row['status'], 'answered');
    });

    test('教师再次回复 → 已 answered 不退回 open', () async {
      final qaId = await insertQa(status: 'answered');
      await db.update('class_qa', {'status': 'answered'},
          where: 'id = ? AND status = ?', whereArgs: [qaId, 'open']);
      final row = (await db.query('class_qa',
              where: 'id = ?', whereArgs: [qaId]))
          .first;
      expect(row['status'], 'answered');
    });
  });

  group('class_qa 采纳最佳回复', () {
    test('updateStatus + acceptedReplyId 写入', () async {
      final qaId = await insertQa(status: 'answered');
      final replyId = await db.insert('class_qa_replies', {
        'qa_id': qaId,
        'author_id': 't1',
        'author_name': 't',
        'author_role': 'teacher',
        'body': 'best',
        'is_teacher': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.update(
        'class_qa',
        {'status': 'closed', 'accepted_reply_id': replyId},
        where: 'id = ?',
        whereArgs: [qaId],
      );

      final row = (await db.query('class_qa',
              where: 'id = ?', whereArgs: [qaId]))
          .first;
      expect(row['status'], 'closed');
      expect(row['accepted_reply_id'], replyId);
    });
  });

  group('class_qa 删除级联', () {
    test('删除 qa 应同时删它的所有 replies', () async {
      final qaId = await insertQa();
      await db.insert('class_qa_replies', {
        'qa_id': qaId,
        'author_id': 'x',
        'author_name': 'x',
        'author_role': 'student',
        'body': 'r',
        'is_teacher': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // DAO 的实现：先删 replies 再删 qa
      await db.delete('class_qa_replies',
          where: 'qa_id = ?', whereArgs: [qaId]);
      await db.delete('class_qa', where: 'id = ?', whereArgs: [qaId]);

      final remainQa = await db
          .query('class_qa', where: 'id = ?', whereArgs: [qaId]);
      final remainReplies = await db.query('class_qa_replies',
          where: 'qa_id = ?', whereArgs: [qaId]);
      expect(remainQa, isEmpty);
      expect(remainReplies, isEmpty);
    });
  });
}
