/// 平台初始化 — 原生平台（Windows/macOS/Linux/Android/iOS）
library;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/init_logger.dart';

Future<void> initPlatform() async {
  // Windows/Linux/macOS 桌面端需要 FFI 初始化 sqflite
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // 显式固化数据库目录到 ApplicationSupportDirectory（跨启动场景稳定）。
    // 默认 getDatabasesPath() 在 sqflite_common_ffi 上是 CWD 相对的
    // (<cwd>/.dart_tool/sqflite_common_ffi/databases)，
    // 学生从开始菜单 / 双击 / 命令行不同位置启动 → CWD 不同 →
    // 等于每次都"首次安装"，seed DB 复制随便一个错就掉进空数据库的坑。
    try {
      final support = await getApplicationSupportDirectory();
      final dbDir = Directory(p.join(support.path, 'databases'));
      if (!await dbDir.exists()) await dbDir.create(recursive: true);

      // 一次性迁移：如果老用户在 CWD 路径下已经有 DB（含成绩、错题、本地学生数据），
      // 而新路径还没有，搬过来。避免修复后所有学生的"已学过"状态丢失。
      final newDbFile = File(p.join(dbDir.path, 'knowledge_graph.db'));
      if (!await newDbFile.exists()) {
        // sqflite_common_ffi 老默认路径 = <cwd>/.dart_tool/sqflite_common_ffi/databases/
        final legacyCwd = File(p.join(
            Directory.current.path,
            '.dart_tool',
            'sqflite_common_ffi',
            'databases',
            'knowledge_graph.db'));
        // 也试 exe 同级（万一以前用过 setCustomFactory）
        final exeDir = File(Platform.resolvedExecutable).parent;
        final legacyExe = File(p.join(
            exeDir.path,
            '.dart_tool',
            'sqflite_common_ffi',
            'databases',
            'knowledge_graph.db'));

        File? legacy;
        if (await legacyCwd.exists()) {
          legacy = legacyCwd;
        } else if (await legacyExe.exists()) {
          legacy = legacyExe;
        }
        if (legacy != null) {
          try {
            await legacy.copy(newDbFile.path);
            InitLogger.log('platform_init',
                'migrated legacy DB ${legacy.path} → ${newDbFile.path}');
          } catch (e, st) {
            InitLogger.error(
                'platform_init', 'legacy DB migration failed: $e', st);
          }
        }
      }

      await databaseFactory.setDatabasesPath(dbDir.path);
      InitLogger.log('platform_init', 'databasesPath fixed = ${dbDir.path}');
    } catch (e, st) {
      // 如果 ApplicationSupport 也拿不到（极端权限场景），就让 sqflite 用默认值，
      // 至少不阻塞应用启动；DB 初始化层会有 fallback 处理。
      InitLogger.error('platform_init', 'setDatabasesPath failed: $e', st);
    }

    InitLogger.log('platform_init', 'sqflite FFI initialized for desktop');
  }

  // 仅在移动端锁定竖屏，桌面端不限制
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
}
