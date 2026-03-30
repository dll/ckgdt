import '../models/ai_config_model.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class AiConfigDao {
  final _db = DatabaseHelper.instance;

  Future<AiConfigModel> getConfig() async {
    final db = await _db.database;
    final rows = await db.query('ai_configs', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) return const AiConfigModel();
    return AiConfigModel.fromMap(rows.first);
  }

  Future<void> saveConfig(AiConfigModel config) async {
    final db = await _db.database;
    await db.insert(
      'ai_configs',
      config.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> hasApiKey() async {
    final config = await getConfig();
    return config.apiKey != null && config.apiKey!.isNotEmpty;
  }
}
