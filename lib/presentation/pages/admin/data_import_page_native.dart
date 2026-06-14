/// 原生平台文件操作实现（使用 dart:io）
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/class_dao.dart';
import '../../../services/course_context_service.dart';

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

    int idCol = headers.indexWhere((h) => h.contains('学号') || h.contains('工号'));
    int nameCol = headers.indexWhere((h) => h == '姓名');
    int roleCol = headers.indexWhere((h) => h == '角色');
    int classCol = headers.indexWhere((h) => h.contains('班级'));
    int teacherCol =
        headers.indexWhere((h) => h.contains('教师') || h.contains('任课'));
    int repoCol = headers.indexWhere(
        (h) => h.contains('仓库') || h.contains('Gitee') || h.contains('gitee'));

    if (idCol < 0 || nameCol < 0) {
      return {'success': false, 'message': '表头格式不匹配，需包含「学号」和「姓名」列'};
    }

    final db = await DatabaseHelper.instance.database;
    final classDao = ClassDao();
    int addedCount = 0;
    int skippedCount = 0;
    int classesCreated = 0;

    // 从文件名推断默认班级名（如 "软件23选88学生名单.xlsx" → "软件23选88"）
    String? defaultClassName;
    if (classCol < 0) {
      final baseName = p.basenameWithoutExtension(filePath);
      // 尝试从文件名中提取班级名（去掉"学生名单"等后缀）
      final cleaned = baseName.replaceAll(RegExp(r'学生名单|名单|学生|_|-'), '').trim();
      if (cleaned.isNotEmpty) {
        defaultClassName = cleaned;
      }
    }

    // 缓存：班级名 → classId（避免重复查询/创建）
    final classCache = <String, int>{};

    /// 获取或创建班级，返回 classId
    Future<int?> getOrCreateClass(String className,
        {String? teacherName}) async {
      if (className.isEmpty) return null;

      if (classCache.containsKey(className)) {
        // 如果有教师信息且现有班级没有，则更新
        if (teacherName != null && teacherName.isNotEmpty) {
          final classId = classCache[className]!;
          final cls = await classDao.getClass(classId);
          if (cls != null &&
              (cls['teacher_name'] == null || cls['teacher_name'] == '')) {
            await classDao.updateClass(classId, {'teacher_name': teacherName});
          }
        }
        return classCache[className];
      }

      // 查找已有班级
      var cls = await classDao.getClassByName(className);
      if (cls != null) {
        classCache[className] = cls['id'] as int;
        return cls['id'] as int;
      }

      // 创建新班级
      final classId = await classDao.createClass(
        name: className,
        teacherName: teacherName,
      );
      classCache[className] = classId;
      classesCreated++;
      return classId;
    }

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

      // 班级名
      String? className;
      if (classCol >= 0) {
        className = _cellValue(row, classCol).trim();
        if (className.isEmpty) className = null;
      }
      className ??= defaultClassName;

      // 教师名
      String? teacherName;
      if (teacherCol >= 0) {
        teacherName = _cellValue(row, teacherCol).trim();
        if (teacherName.isEmpty) teacherName = null;
      }

      // 仓库地址
      String? repoUrl;
      if (repoCol >= 0) {
        repoUrl = _cellValue(row, repoCol).trim();
        if (repoUrl.isEmpty) repoUrl = null;
      }

      // 检查用户是否已存在
      final existing =
          await db.query('users', where: 'user_id = ?', whereArgs: [userId]);
      if (existing.isNotEmpty) {
        // 更新已有用户的姓名和仓库地址
        final updateData = <String, dynamic>{};
        if (name.isNotEmpty) updateData['real_name'] = name;
        if (repoUrl != null) updateData['repository_url'] = repoUrl;
        if (updateData.isNotEmpty) {
          await db.update('users', updateData,
              where: 'user_id = ?', whereArgs: [userId]);
        }

        // 仍然需要绑定班级
        if (className != null && role == 'student') {
          final classId =
              await getOrCreateClass(className, teacherName: teacherName);
          if (classId != null) {
            await classDao.addMember(classId, userId);
          }
        }

        skippedCount++;
        continue;
      }

      // 插入新用户
      await db.insert('users', {
        'user_id': userId,
        'real_name': name.isNotEmpty ? name : null,
        'role': role,
        'is_active': 1,
        'repository_url': repoUrl,
        'created_at': DateTime.now().toIso8601String(),
      });
      addedCount++;

      // 绑定班级
      if (className != null && role == 'student') {
        final classId =
            await getOrCreateClass(className, teacherName: teacherName);
        if (classId != null) {
          await classDao.addMember(classId, userId);
        }
      }
    }

    final msgParts = <String>[
      '导入完成！新增 $addedCount 人，跳过已存在 $skippedCount 人。',
    ];
    if (classesCreated > 0) {
      msgParts.add('自动创建 $classesCreated 个班级。');
    }
    msgParts.add('来源文件: ${p.basename(filePath)}');

    return {
      'success': true,
      'message': msgParts.join('\n'),
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
    final resourceDir = Directory(p.join(docDir.path, 'resources', fileType));
    if (!await resourceDir.exists()) {
      await resourceDir.create(recursive: true);
    }

    final db = await DatabaseHelper.instance.database;
    final courseContext = CourseContextService();
    final courseId = await courseContext.activeCourseId();
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
          where: 'course_id = ? AND file_name = ? AND file_type = ?',
          whereArgs: [courseId, fileName, fileType]);

      if (existing.isNotEmpty) {
        await db.update(
          'resource_files',
          {'file_path': destPath},
          where: 'course_id = ? AND file_name = ? AND file_type = ?',
          whereArgs: [courseId, fileName, fileType],
        );
      } else {
        await db.insert('resource_files', {
          'course_id': courseId,
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
