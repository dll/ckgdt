import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// 讯飞语音配置 DAO — 从数据库读取试用凭据
class XunfeiConfigDao {
  final _db = DatabaseHelper.instance;

  /// 获取活跃的讯飞配置（id=1）
  Future<Map<String, dynamic>?> getConfig() async {
    final db = await _db.database;
    final rows = await db.query('xunfei_configs', where: 'id = ?', whereArgs: [1]);
    return rows.isEmpty ? null : rows.first;
  }

  /// 保存讯飞配置
  Future<void> saveConfig({
    required String appId,
    required String apiKey,
    required String apiSecret,
  }) async {
    final db = await _db.database;
    await db.insert(
      'xunfei_configs',
      {
        'id': 1,
        'app_id': appId,
        'api_key': apiKey,
        'api_secret': apiSecret,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取 AppID
  Future<String> getAppId() async {
    final config = await getConfig();
    return config?['app_id'] as String? ?? '';
  }

  /// 获取 API Key
  Future<String> getApiKey() async {
    final config = await getConfig();
    return config?['api_key'] as String? ?? '';
  }

  /// 获取 API Secret
  Future<String> getApiSecret() async {
    final config = await getConfig();
    return config?['api_secret'] as String? ?? '';
  }
}
