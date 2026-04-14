import '../models/puml_file_model.dart';
import 'database_helper.dart';

class PumlDao {
  final _db = DatabaseHelper.instance;

  Future<int> insert(PumlFileModel p) async {
    final db = await _db.database;
    return db.insert('puml_files', p.toMap());
  }

  Future<List<PumlFileModel>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('puml_files', orderBy: 'updated_at DESC');
    return rows.map(PumlFileModel.fromMap).toList();
  }

  Future<List<PumlFileModel>> getByChapter(String chapter) async {
    final db = await _db.database;
    final rows = await db.query('puml_files',
        where: 'chapter = ?', whereArgs: [chapter], orderBy: 'updated_at DESC');
    return rows.map(PumlFileModel.fromMap).toList();
  }

  Future<PumlFileModel?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('puml_files', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return PumlFileModel.fromMap(rows.first);
  }

  Future<int> update(PumlFileModel p) async {
    final db = await _db.database;
    return db
        .update('puml_files', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('puml_files', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM puml_files');
    return result.first['c'] as int? ?? 0;
  }

  // 初始化内置 PUML 样例（首次运行）
  Future<void> initSamples() async {
    final c = await count();
    if (c > 0) return;

    final samples = [
      PumlFileModel(
        title: '知识图谱系统架构图',
        content: '''@startuml
title 知识图谱教学系统架构图
skinparam backgroundColor #FFFFFF
skinparam defaultFontName Microsoft YaHei

package "Flutter UI" {
  [LoginPage]
  [HomePage]
  [GraphDetailPage]
  [QuizPage]
  [ProgressPage]
}
package "Service/DAO" {
  [AuthService]
  [GraphDao]
  [QuizDao]
  [LearningRecordDao]
}
database "SQLite" as DB

[LoginPage] --> [AuthService]
[HomePage] --> [GraphDetailPage]
[GraphDetailPage] --> [GraphDao]
[QuizPage] --> [QuizDao]
[ProgressPage] --> [LearningRecordDao]
[GraphDao] --> DB
[QuizDao] --> DB
[LearningRecordDao] --> DB
@enduml''',
        diagramType: 'component',
        chapter: '系统架构',
      ),
      PumlFileModel(
        title: '图谱功能时序图',
        content: '''@startuml
title 图谱浏览时序图
actor 用户
participant GraphListPage
participant GraphDetailPage
participant GraphDao
database SQLite

用户 -> GraphListPage : 进入图谱模块
GraphListPage -> GraphDao : getAllGraphs()
GraphDao -> SQLite : SELECT * FROM graphs
SQLite --> GraphDao : 图谱列表
GraphDao --> GraphListPage : List<GraphModel>
GraphListPage --> 用户 : 展示图谱卡片

用户 -> GraphListPage : 点击图谱
GraphListPage -> GraphDetailPage : Navigator.push(graphId)
GraphDetailPage -> GraphDao : getNodes(graphId)
GraphDao -> SQLite : SELECT * FROM nodes
SQLite --> GraphDetailPage : 节点+边数据
GraphDetailPage --> 用户 : 渲染图谱视图
@enduml''',
        diagramType: 'sequence',
        chapter: '图谱模块',
      ),
    ];
    for (final s in samples) {
      await insert(s);
    }
  }
}
