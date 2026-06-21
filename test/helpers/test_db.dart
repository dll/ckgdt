import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 单元测试用 sqflite ffi 初始化。
///
/// **用法**：在每个 DAO 测试文件的 `main()` 顶部调用 [setupTestSqflite]，
/// 然后用 [openInMemoryDb] 打开内存库（每个 test case 独立一份）。
void setupTestSqflite() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// 打开一个全新的内存 SQLite 库（用 `:memory:` URI）。
/// 调用方负责自己 CREATE TABLE 与 close。
Future<Database> openInMemoryDb() async {
  return databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1),
  );
}
