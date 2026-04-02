/// 原生平台文件操作实现（使用 dart:io）
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../data/local/database_helper.dart';

Future<String?> saveStringToFile(String content, String prefix) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/${prefix}_$timestamp.csv');
    await file.writeAsString(content);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>> importStudentsFromFile(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    // 取第一个 sheet
    final sheet = excel.tables[excel.tables.keys.first]!;
    if (sheet.maxRows < 2) {
      return {'success': false, 'message': '文件为空或没有数据行'};
    }

    // 解析表头 → 列索引
    final headerRow = sheet.row(0);
    final headers =
        headerRow.map((cell) => cell?.value?.toString() ?? '').toList();

    int idCol =
        headers.indexWhere((h) => h.contains('学号') || h.contains('工号'));
    int nameCol = headers.indexWhere((h) => h == '姓名');
    int roleCol = headers.indexWhere((h) => h == '角色');

    if (idCol < 0 || nameCol < 0) {
      return {'success': false, 'message': '表头格式不匹配，需包含「学号」和「姓名」列'};
    }

    final db = await DatabaseHelper.instance.database;
    int addedCount = 0;
    int skippedCount = 0;

    for (int i = 1; i < sheet.maxRows; i++) {
      final row = sheet.row(i);
      final userId = _cellValue(row, idCol).trim();
      final name = _cellValue(row, nameCol).trim();
      if (userId.isEmpty) continue;

      String role = 'student';
      if (roleCol >= 0) {
        final roleStr = _cellValue(row, roleCol).trim();
        if (roleStr == '教师') {
          role = 'teacher';
        } else if (roleStr == '管理员') {
          role = 'admin';
        }
      }

      final password =
          userId.length >= 6 ? userId.substring(userId.length - 6) : userId;

      final existing = await db.query('users',
          where: 'user_id = ?', whereArgs: [userId]);
      if (existing.isNotEmpty) {
        skippedCount++;
        continue;
      }

      await db.insert('users', {
        'user_id': userId,
        'password': password,
        'role': role,
        'name': name,
        'is_active': 1,
      });
      addedCount++;
    }

    return {
      'success': true,
      'message': '导入完成！新增 $addedCount 人，跳过已存在 $skippedCount 人。\n'
          '来源文件: ${p.basename(filePath)}',
    };
  } catch (e) {
    return {'success': false, 'message': '导入失败: $e'};
  }
}

String _cellValue(List<Data?> row, int col) {
  if (col < 0 || col >= row.length) return '';
  final cell = row[col];
  if (cell == null || cell.value == null) return '';
  return cell.value.toString();
}

Future<String?> readFileAsString(String filePath) async {
  try {
    return await File(filePath).readAsString();
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>> uploadResourceFiles(
    List<PlatformFile> files, String fileType) async {
  try {
    final docDir = await getApplicationDocumentsDirectory();
    final resourceDir =
        Directory(p.join(docDir.path, 'resources', fileType));
    if (!await resourceDir.exists()) {
      await resourceDir.create(recursive: true);
    }

    final db = await DatabaseHelper.instance.database;
    int addedCount = 0;

    for (final file in files) {
      if (file.path == null) continue;
      final srcFile = File(file.path!);
      final fileName = file.name;

      // 复制到应用文档目录
      final destPath = p.join(resourceDir.path, fileName);
      await srcFile.copy(destPath);

      // 从文件名推断章节名（去掉扩展名）
      final chapter = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

      // 检查是否已存在同名记录
      final existing = await db.query('resource_files',
          where: 'file_name = ? AND file_type = ?',
          whereArgs: [fileName, fileType]);

      if (existing.isNotEmpty) {
        await db.update(
          'resource_files',
          {'file_path': destPath},
          where: 'file_name = ? AND file_type = ?',
          whereArgs: [fileName, fileType],
        );
      } else {
        await db.insert('resource_files', {
          'file_name': fileName,
          'file_path': destPath,
          'file_type': fileType,
          'chapter': chapter,
          'description': fileType == 'video'
              ? '视频教程'
              : (fileType == 'pdf' ? 'PDF课件' : 'PPT课件'),
        });
      }
      addedCount++;
    }

    return {
      'success': true,
      'message':
          '成功上传 $addedCount 个${fileType == 'video' ? '视频' : (fileType == 'pdf' ? 'PDF' : 'PPT')}文件。\n'
              '存储位置: ${resourceDir.path}',
    };
  } catch (e) {
    return {'success': false, 'message': '上传失败: $e'};
  }
}
