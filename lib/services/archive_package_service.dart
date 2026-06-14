import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../core/constants/archive_periods.dart' as periods;
import '../core/error_handler.dart';
import '../data/local/class_dao.dart';
import '../data/local/course_dao.dart';
import '../data/models/archive_document_model.dart';
import 'archive/pandoc_service.dart';
import 'archive/processor_registry.dart';
import 'auth_service.dart';

/// 一键归档打包服务。
///
/// **职责**：把已审核通过 / 已存稿的归档文档落盘成符合学校命名规范的 docx，
/// 按"学期/课程/期"分目录归档，整期可打 zip 供 QQ 群分享。
///
/// **命名规范**：`{学院}+{课程}+{文档类型}+{教师}+{学期}.docx`
///   - 例如：`软件学院+移动应用开发+教学大纲+刘东良+2025-2026-2.docx`
///
/// **目录布局**：
///   archive_out/
///     2025-2026-2/
///       移动应用开发/
///         期初/
///           软件学院+移动应用开发+教学大纲+刘东良+2025-2026-2.docx
///           软件学院+移动应用开发+教学日历+刘东良+2025-2026-2.docx
///         期初_软件学院+移动应用开发+刘东良+2025-2026-2.zip
///         期中/...
///         期末/...
///         全期_软件学院+移动应用开发+刘东良+2025-2026-2.zip
class ArchivePackageService {
  ArchivePackageService._();
  static final instance = ArchivePackageService._();

  /// 归档输出根目录绝对路径，由 main.dart 在启动时注入。
  /// 桌面端默认 `<项目根>/archive_out/`，移动端 / web 不可用。
  static String? outputRoot;

  /// 部署院校简称，用于归档文件命名的 `{学院}` 段。
  /// classes/users 表均无学院字段，故用此可配置常量；换部署单位改这一处即可。
  static String collegeName = '信息学院';

  final _classDao = ClassDao();
  final _courseDao = CourseDao();
  final _auth = AuthService();

  bool get isAvailable {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 构建标准命名（不含 .docx 后缀）。
  ///
  /// 字段不全时降级填充 `[未填]`，但会写入 [warnings] 让 UI 提示。
  Future<ArchiveNaming> buildNaming({
    required ArchiveDocument doc,
    required String docLabel,
  }) async {
    final warnings = <String>[];

    // 课程
    String courseName;
    try {
      final c = await _courseDao.getActiveCourse();
      courseName = c?.name ?? '[未知课程]';
      if (c == null) warnings.add('未找到激活课程');
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePackageService.course', stack: st);
      courseName = '[未知课程]';
      warnings.add('课程读取失败');
    }

    // 教师 + 学院
    final user = _auth.currentUser;
    final teacherName = user?.realName ?? user?.userId ?? '[未登录]';
    if (user == null) warnings.add('教师未登录');
    // 学期：取教师当前班级的 semester（classes 表真实列）；找不到给当前学年默认值
    String semester = _defaultSemester();
    try {
      final tid = user?.userId;
      if (tid != null) {
        final classes = await _classDao.getTeacherClasses(tid);
        if (classes.isNotEmpty) {
          final s = classes.first['semester']?.toString();
          if (s != null && s.isNotEmpty) semester = s;
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePackageService.class', stack: st);
    }
    // 学院：classes/users 表均无学院列，采用部署院校简称常量（可改 [collegeName]）。
    final department = collegeName;

    return ArchiveNaming(
      department: _safeSegment(department),
      course: _safeSegment(courseName),
      docLabel: _safeSegment(docLabel),
      teacher: _safeSegment(teacherName),
      semester: _safeSegment(semester),
      warnings: warnings,
    );
  }

  /// 写一份 docx 到归档目录，返回绝对路径。
  ///
  /// [docLabel] 是用户可见的中文文档名（如"教学大纲"），来源于
  /// archive_constants.DocumentTypeDef.label。Processor 注册时也有同名字段。
  Future<String> archiveDocxOf(
    ArchiveDocument doc, {
    required String docLabel,
    ArchiveNaming? naming,
  }) async {
    if (!isAvailable) {
      throw const ArchivePackageException('一键归档仅在桌面端可用');
    }
    final outRoot = outputRoot;
    if (outRoot == null) {
      throw const ArchivePackageException(
          '归档输出目录未注入（main._initArchivePaths 未运行？）');
    }
    final n = naming ?? await buildNaming(doc: doc, docLabel: docLabel);

    final dir = Directory(
        p.join(outRoot, n.semester, n.course, _periodLabel(doc.period)));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final sourcePdf = _sourcePdfFile(doc);
    if (sourcePdf != null) {
      final outFile = File(
        p.join(dir.path, '${n.fileBase(docLabel: n.docLabel)}.pdf'),
      );
      await sourcePdf.copy(outFile.path);
      return outFile.path;
    }

    // 1) 拿 docx 字节：优先 Processor 路径（继承 reference-doc 样式），
    //    没注册就 PandocService 默认。
    Uint8List bytes;
    final processor = ProcessorRegistry.instance.find(doc.documentType);
    if (processor != null) {
      bytes = await processor.toDocx(doc);
    } else {
      bytes = await PandocService.instance.markdownToDocx(doc.content ?? '');
    }

    // 2) 写盘
    final fileName = '${n.fileBase(docLabel: n.docLabel)}.docx';
    final outFile = File(p.join(dir.path, fileName));
    await outFile.writeAsBytes(bytes, flush: true);

    if (_shouldArchivePdf(doc, processor)) {
      final pdfBytes = await processor!.toPdf(doc);
      final pdfFile =
          File(p.join(dir.path, '${n.fileBase(docLabel: n.docLabel)}.pdf'));
      await pdfFile.writeAsBytes(pdfBytes, flush: true);
    }
    return outFile.path;
  }

  /// 把整期已归档的 docx 打成 zip，返回 zip 绝对路径。
  ///
  /// 命名：`{期}_{学院}+{课程}+{教师}+{学期}.zip`
  Future<String> zipPeriod({
    required String period,
    required ArchiveNaming naming,
  }) async {
    final outRoot = outputRoot;
    if (outRoot == null) {
      throw const ArchivePackageException('归档输出目录未注入');
    }
    final periodDir = Directory(
        p.join(outRoot, naming.semester, naming.course, _periodLabel(period)));
    if (!periodDir.existsSync()) {
      throw ArchivePackageException('未找到归档目录：${periodDir.path}');
    }
    final archiveFiles = periodDir
        .listSync()
        .whereType<File>()
        .where(_isArchiveOutputFile)
        .toList();
    if (archiveFiles.isEmpty) {
      throw ArchivePackageException('期内无归档文件可打包：${periodDir.path}');
    }

    final encoder = ZipFileEncoder();
    final zipPath = p.join(
      periodDir.parent.path,
      '${_periodLabel(period)}_${naming.department}+${naming.course}+${naming.teacher}+${naming.semester}.zip',
    );
    encoder.create(zipPath);
    for (final f in archiveFiles) {
      encoder.addFile(f);
    }
    encoder.close();
    return zipPath;
  }

  /// 全期合并 zip：把 期初 / 期中 / 期末 / 归档 四个目录都打进去
  Future<String> zipAllPeriods(ArchiveNaming naming) async {
    final outRoot = outputRoot;
    if (outRoot == null) {
      throw const ArchivePackageException('归档输出目录未注入');
    }
    final courseDir =
        Directory(p.join(outRoot, naming.semester, naming.course));
    if (!courseDir.existsSync()) {
      throw ArchivePackageException('未找到课程归档目录：${courseDir.path}');
    }

    final encoder = ZipFileEncoder();
    final zipPath = p.join(
      courseDir.parent.path,
      '全期_${naming.department}+${naming.course}+${naming.teacher}+${naming.semester}.zip',
    );
    encoder.create(zipPath);
    for (final entity in courseDir.listSync(recursive: false)) {
      if (entity is Directory) {
        // 仅打正式归档文件，跳过已生成的 .zip
        for (final f in entity.listSync().whereType<File>()) {
          if (!_isArchiveOutputFile(f)) continue;
          final rel = p.relative(f.path, from: courseDir.path);
          encoder.addArchiveFile(_fileToArchiveFile(f, rel));
        }
      }
    }
    encoder.close();
    return zipPath;
  }

  /// 在系统文件管理器中打开并选中给定文件。
  /// Windows: explorer /select,<path>; macOS: open -R; Linux: xdg-open 父目录
  Future<void> revealInFileManager(String path) async {
    if (!isAvailable) return;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', ['/select,', path], runInShell: false);
      } else if (Platform.isMacOS) {
        await Process.start('open', ['-R', path], runInShell: false);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [File(path).parent.path],
            runInShell: false);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchivePackageService.reveal', stack: st);
    }
  }

  // ─── helpers ──────────────────────────────────────────────────────────

  ArchiveFile _fileToArchiveFile(File f, String relPath) {
    final bytes = f.readAsBytesSync();
    return ArchiveFile(relPath, bytes.length, bytes);
  }

  bool _shouldArchivePdf(ArchiveDocument doc, Object? processor) =>
      doc.documentType == 'teaching_task' && processor != null;

  File? _sourcePdfFile(ArchiveDocument doc) {
    final path = doc.filePath;
    if (path == null || !path.toLowerCase().endsWith('.pdf')) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  bool _isArchiveOutputFile(File f) {
    final lower = f.path.toLowerCase();
    return lower.endsWith('.docx') || lower.endsWith('.pdf');
  }

  String _periodLabel(String key) => periods.periodLabel(key);

  /// 默认学期：当前年月推断（>=8 月为上半年；<8 月为下半年）
  String _defaultSemester() {
    final now = DateTime.now();
    if (now.month >= 8) {
      return '${now.year}-${now.year + 1}-1';
    }
    return '${now.year - 1}-${now.year}-2';
  }

  /// 文件名段净化：去除 / \ : * ? " < > | 这些 NTFS 非法字符
  String _safeSegment(String input) {
    var s = input.trim();
    if (s.isEmpty) return '[未填]';
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    // 防止重复"+"打乱命名约定
    s = s.replaceAll('+', '＋');
    return s;
  }
}

/// 一份归档文档的标准命名要素
class ArchiveNaming {
  final String department;
  final String course;
  final String docLabel;
  final String teacher;
  final String semester;
  final List<String> warnings;

  ArchiveNaming({
    required this.department,
    required this.course,
    required this.docLabel,
    required this.teacher,
    required this.semester,
    this.warnings = const [],
  });

  /// 文件名前缀（不含扩展名 / 不含期目录）
  /// 形如：`{学院}+{课程}+{docLabel}+{教师}+{学期}`
  String fileBase({String? docLabel}) {
    final lbl = docLabel ?? this.docLabel;
    return '$department+$course+$lbl+$teacher+$semester';
  }

  /// 用于 zip 命名（不含 docLabel，因为 zip 是聚合）
  String get zipBase => '$department+$course+$teacher+$semester';

  ArchiveNaming copyWith({
    String? department,
    String? course,
    String? docLabel,
    String? teacher,
    String? semester,
  }) =>
      ArchiveNaming(
        department: department ?? this.department,
        course: course ?? this.course,
        docLabel: docLabel ?? this.docLabel,
        teacher: teacher ?? this.teacher,
        semester: semester ?? this.semester,
        warnings: warnings,
      );
}

class ArchivePackageException implements Exception {
  final String message;
  const ArchivePackageException(this.message);
  @override
  String toString() => 'ArchivePackageException: $message';
}
