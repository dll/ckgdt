import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../core/error_handler.dart';
import 'skill_registry.dart';

class SkillExportResult {
  final bool success;
  final String message;
  final String? filePath;
  const SkillExportResult({
    required this.success,
    required this.message,
    this.filePath,
  });
}

class SkillExportService {
  SkillExportService({SkillRegistry? registry})
      : _registry = registry ?? SkillRegistry.instance;
  final SkillRegistry _registry;

  Future<SkillExportResult> exportAllToDesktop() async {
    if (kIsWeb) {
      return const SkillExportResult(success: false, message: 'Web 不支持文件导出');
    }
    try {
      final dir = await _exportDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${dir.path}/skills_all_$ts.skill.json');
      await file.writeAsString(_registry.exportAllToJson(), flush: true);
      return SkillExportResult(
        success: true,
        message: '已导出 ${_registry.count} 个技能到 ${file.path}',
        filePath: file.path,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'SkillExportService.exportAll', stack: st);
      return SkillExportResult(success: false, message: '导出失败: $e');
    }
  }

  Future<SkillExportResult> exportAllToClipboard() async {
    try {
      final json = _registry.exportAllToJson();
      await Clipboard.setData(ClipboardData(text: json));
      return SkillExportResult(success: true, message: '已复制全部技能 JSON 到剪贴板');
    } catch (e, st) {
      swallowDebug(e, tag: 'SkillExportService.exportClipboard', stack: st);
      return SkillExportResult(success: false, message: '复制失败: $e');
    }
  }

  Future<SkillExportResult> exportSingleToDesktop(String skillId) async {
    if (kIsWeb) {
      return const SkillExportResult(success: false, message: 'Web 不支持文件导出');
    }
    try {
      final skill = _registry.get(skillId);
      if (skill == null) {
        return const SkillExportResult(success: false, message: '技能不存在');
      }
      final dir = await _exportDirectory();
      final fileName = 'skill_${skill.id}_${DateTime.now().millisecondsSinceEpoch}.skill.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(_registry.exportSkillToJson(skillId), flush: true);
      return SkillExportResult(
        success: true,
        message: '已导出技能"${skill.name}"到 ${file.path}',
        filePath: file.path,
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'SkillExportService.exportSingle', stack: st);
      return SkillExportResult(success: false, message: '导出失败: $e');
    }
  }

  Future<SkillExportResult> exportForReuse(String skillId) async {
    final result = await exportSingleToDesktop(skillId);
    if (result.success) {
      return SkillExportResult(
        success: true,
        message: '技能已导出，可分享给其他用户导入使用',
        filePath: result.filePath,
      );
    }
    return result;
  }

  Future<int> importFromFile() async {
    if (kIsWeb) {
      return 0;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return 0;
      final path = result.files.single.path;
      if (path == null) return 0;
      final content = await File(path).readAsString();
      return _registry.importFromJson(content);
    } catch (e, st) {
      swallowDebug(e, tag: 'SkillExportService.import', stack: st);
      return 0;
    }
  }

  Future<Directory> _exportDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/skill_exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> defaultExportDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/skill_exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<List<FileSystemEntity>> listExportedFiles() async {
    final dir = await defaultExportDirectory();
    return dir.listSync()..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  }

  Future<SkillExportResult> importFromClipboard(String json) async {
    try {
      final count = _registry.importFromJson(json);
      if (count > 0) {
        return SkillExportResult(
          success: true,
          message: '成功导入 $count 个技能',
        );
      }
      return const SkillExportResult(success: false, message: '未找到可导入的技能（可能已存在）');
    } catch (e, st) {
      swallowDebug(e, tag: 'SkillExportService.importClipboard', stack: st);
      return SkillExportResult(success: false, message: '导入失败: $e');
    }
  }
}
