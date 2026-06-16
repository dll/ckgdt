import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../data/local/lab_task_dao.dart';
import '../../../data/local/grading_result_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/auto_grading_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/agent/agents/grading_agent.dart';
import '../../../services/gitee_service.dart';
import '../../../services/course_resource_service.dart';
import '../../../services/pdf_text_service.dart';
import '../../../services/lab_report_validation_service.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/score_export_service.dart';
import '../../widgets/agent_entry_button.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import '../../widgets/score_preview_dialog.dart';
import '../admin/repo_detail_page.dart';
import 'lab_material_preview_page.dart';
import '../learning/pdf_viewer_page.dart';
import 'ai_grading_tab.dart';

import '../../../core/error_handler.dart';
// ── Tab 实现拆分到 tabs/ 子目录（part / part of 模式）─────────────
part 'tabs/task_list_tab.dart';
part 'tabs/submission_tab.dart';
part 'tabs/report_tab.dart';
part 'tabs/task_manage_tab.dart';
part 'tabs/student_repo_tab.dart';
part 'tabs/repo_report_tab.dart';
part 'tabs/materials_tab.dart';

/// 实验任务页面
/// 学生: 5 Tab（任务列表 / 我的提交 / 实验报告 / 实验材料 / 仓库报表）
/// 教师/管理员: 7 Tab（任务列表 / 提交管理 / 实验报告 / 实验材料 / 任务管理 / AI批阅 / 仓库报表）
class LabTasksPage extends StatefulWidget {
  const LabTasksPage({super.key});

  @override
  State<LabTasksPage> createState() => _LabTasksPageState();
}

/// 尝试从 AI 批阅结果中解析 JSON（顶层函数，多处复用）
Map<String, dynamic>? tryParseGradingJson(String text) {
  final candidates = <String>[];
  final trimmed = text.trim();
  candidates.add(trimmed);
  final fenced =
      RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false)
          .firstMatch(trimmed);
  if (fenced != null) {
    candidates.add(fenced.group(1)!.trim());
  }
  candidates.addAll(_balancedJsonObjects(trimmed));

  for (final candidate in candidates) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is! Map<String, dynamic>) continue;
      if (decoded.containsKey('score') ||
          decoded.containsKey('total_score') ||
          decoded.containsKey('feedback') ||
          decoded.containsKey('summary') ||
          decoded.containsKey('scores') ||
          decoded.containsKey('dimensions')) {
        return decoded;
      }
    } catch (e) {
      swallow(e, tag: 'tryParseGradingJson.candidate');
    }
  }
  return null;
}

List<String> _balancedJsonObjects(String text) {
  final objects = <String>[];
  var start = -1;
  var depth = 0;
  var inString = false;
  var escaping = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (escaping) {
      escaping = false;
      continue;
    }
    if (ch == '\\') {
      escaping = inString;
      continue;
    }
    if (ch == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (ch == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (ch == '}' && depth > 0) {
      depth--;
      if (depth == 0 && start >= 0) {
        objects.add(text.substring(start, i + 1));
        start = -1;
      }
    }
  }
  return objects;
}

/// 将 AI 批阅的 JSON 结果转为人类可读的反馈文本（顶层函数，多处复用）
String formatGradingFeedback(Map<String, dynamic> parsed) {
  final sb = StringBuffer();

  final summary = parsed['summary'] as String?;
  if (summary != null && summary.isNotEmpty) {
    sb.writeln('【总评】$summary');
    sb.writeln();
  }

  final dims = parsed['dimensions'] as Map<String, dynamic>?;
  if (dims != null) {
    sb.writeln('【各维度评分】');
    for (final entry in dims.entries) {
      final d = entry.value;
      if (d is Map<String, dynamic>) {
        sb.writeln(
            '  ${entry.key}: ${d['score'] ?? ''}/${d['max'] ?? ''} — ${d['comment'] ?? ''}');
      }
    }
    sb.writeln();
  }

  final strengths = parsed['strengths'] as List?;
  if (strengths != null && strengths.isNotEmpty) {
    sb.writeln('【优点】');
    for (final s in strengths) {
      sb.writeln('  - $s');
    }
    sb.writeln();
  }

  final improvements = parsed['improvements'] as List?;
  if (improvements != null && improvements.isNotEmpty) {
    sb.writeln('【改进建议】');
    for (final s in improvements) {
      sb.writeln('  - $s');
    }
    sb.writeln();
  }

  final feedback = parsed['feedback'] as String?;
  if (feedback != null && feedback.isNotEmpty) {
    sb.writeln('【详细反馈】');
    sb.writeln(feedback);
  }

  final result = sb.toString().trim();
  return result.isNotEmpty ? result : (parsed['feedback'] as String? ?? '');
}

/// 准备 AI 批阅内容：若提交内容仅含文件名占位（旧数据），尝试从 PDF 重新提取文本。
///
/// 返回 (content, hasBody)：
/// - hasBody=false 表示仍未拿到正文，UI 应提示教师 "PDF 同步中或损坏，需手动批改"
String? _gradingContentBodyMarker = LabReportValidationService.bodyMarker;

Future<({String content, bool hasBody})> prepareGradingContent({
  required String rawContent,
  required String filePaths,
  required String fileNames,
}) async {
  // 已有正文标记 → 直接返回
  if (rawContent.contains(_gradingContentBodyMarker!) &&
      rawContent.length > 200) {
    return (content: rawContent, hasBody: true);
  }
  // 旧数据（仅 "PDF实验报告：xxx.pdf"）→ 尝试从本地 PDF 提取
  final resolved = _resolveFilePath(filePaths, fileNames);
  if (resolved != null) {
    final extracted = await PdfTextService.extractFromFile(resolved);
    if (extracted != null && extracted.isNotEmpty) {
      final buf = StringBuffer()
        ..writeln(rawContent.isEmpty ? 'PDF实验报告：$fileNames' : rawContent.trim())
        ..writeln()
        ..writeln(_gradingContentBodyMarker)
        ..writeln(extracted);
      return (content: buf.toString(), hasBody: true);
    }
  }
  // 仍无正文：返回原内容供 UI 决策
  return (content: rawContent, hasBody: false);
}

/// 解析PDF文件路径：优先使用原始路径，若不存在则尝试在常见目录查找同名文件
String? _resolveFilePath(String filePath, String fileNames) {
  // 1. 直接路径存在
  if (filePath.isNotEmpty && File(filePath).existsSync()) {
    return filePath;
  }
  // 2. 尝试按文件名在常见目录查找
  final fileName = fileNames.isNotEmpty
      ? fileNames
      : filePath.split('/').last.split('\\').last;
  if (fileName.isEmpty) return null;

  // 检查下载目录和应用文档目录
  final searchDirs = <String>[
    // 当前路径的目录（可能同设备换了盘符）
    if (filePath.isNotEmpty) File(filePath).parent.path,
  ];
  // 添加平台常见目录
  if (Platform.isWindows) {
    final userHome = Platform.environment['USERPROFILE'] ?? '';
    if (userHome.isNotEmpty) {
      searchDirs.addAll([
        '$userHome\\Downloads',
        '$userHome\\Documents',
        '$userHome\\Desktop',
      ]);
    }
  }
  for (final dir in searchDirs) {
    final candidate = File('$dir${Platform.pathSeparator}$fileName');
    if (candidate.existsSync()) return candidate.path;
  }

  // 3. 在同步下载目录浅层搜索（仅 sync_files/{userId}/，最多 2 层）
  try {
    final appDataPaths = <String>[
      if (Platform.isWindows)
        '${Platform.environment['LOCALAPPDATA'] ?? ''}\\com.edu.knowledge_graph_app',
      if (Platform.isWindows)
        '${Platform.environment['APPDATA'] ?? ''}\\com.edu.knowledge_graph_app',
      if (Platform.isWindows)
        '${Platform.environment['USERPROFILE'] ?? ''}\\Documents\\sync_files',
    ];
    for (final appPath in appDataPaths) {
      if (appPath.isEmpty) continue;
      final syncDir = Directory(
          appPath.endsWith('sync_files') ? appPath : '$appPath\\sync_files');
      if (!syncDir.existsSync()) continue;
      // 仅扫描第一层（用户目录）和第二层（实验/考核/作品 子目录）
      try {
        for (final userDir in syncDir.listSync()) {
          if (userDir is! Directory) continue;
          for (final entity in userDir.listSync(recursive: false)) {
            if (entity is File && entity.path.endsWith(fileName)) {
              return entity.path;
            }
            if (entity is Directory) {
              for (final inner in entity.listSync(recursive: false)) {
                if (inner is File && inner.path.endsWith(fileName)) {
                  return inner.path;
                }
              }
            }
          }
        }
      } catch (e) {
        swallow(e, tag: '_resolveFilePath.inner');
      }
    }
  } catch (e) {
    swallow(e, tag: '_resolveFilePath.outer');
  }

  return null;
}

/// 教师端 PDF 预览统一入口：本地存在 → 直接打开；缺失 → 提示并提供"立即同步"动作
Future<void> previewOrPromptSync(
  BuildContext context, {
  required String filePaths,
  required String fileNames,
  required String userId,
  required String title,
  VoidCallback? onSyncFinished,
}) async {
  final resolved = _resolveFilePath(filePaths, fileNames);
  if (resolved != null) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InAppPdfViewerPage(filePath: resolved, title: title),
      ),
    );
    return;
  }

  final fileName = fileNames.isNotEmpty
      ? fileNames
      : (filePaths.isNotEmpty
          ? filePaths.split(Platform.pathSeparator).last
          : '附件');
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(
        '该 PDF 在学生本机提交，尚未同步到当前设备。\n文件名：$fileName',
        style: const TextStyle(height: 1.4),
      ),
      action: userId.isEmpty
          ? null
          : SnackBarAction(
              label: '立即同步',
              onPressed: () async {
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(SnackBar(
                  content: Text('正在从云端拉取 $userId 的提交…'),
                  duration: const Duration(seconds: 2),
                ));
                try {
                  final r = await SyncService().downloadOwnData(userId);
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(SnackBar(
                    content: Text(
                        r.success ? '同步完成：${r.message}' : '同步失败：${r.message}'),
                    backgroundColor: r.success ? null : Colors.red,
                  ));
                  if (r.success) onSyncFinished?.call();
                } catch (e) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(SnackBar(
                    content: Text('同步出错：$e'),
                    backgroundColor: Colors.red,
                  ));
                }
              },
            ),
    ),
  );
}

class _LabTasksPageState extends State<LabTasksPage>
    with SingleTickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _labTaskDao = LabTaskDao();
  bool _initialized = false;

  bool get _isTeacherOrAdmin => _authService.isTeacher || _authService.isAdmin;

  @override
  String get innerTabPageKey => 'lab';
  @override
  String get innerTabSpeakLabel => '实验';
  @override
  TabController get innerTabController => _tabController;
  @override
  List<String> innerTabLabels() => _isTeacherOrAdmin
      ? const ['任务列表', '提交管理', '实验报告', '实验材料', '任务管理', 'AI批阅', '仓库报表']
      : const ['任务列表', '我的提交', '实验报告', '实验材料', '仓库报表'];

  @override
  void initState() {
    super.initState();
    final tabCount = _isTeacherOrAdmin ? 7 : 5;
    _tabController = TabController(length: tabCount, vsync: this);
    _initData();
    bindInnerTabRequest();
  }

  Future<void> _initData() async {
    try {
      await _labTaskDao.initDemoDataIfEmpty();
    } catch (e, st) {
      swallowDebug(e, tag: 'LabPage._initData', stack: st);
    }
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showLabScorePreview() async {
    final data = await ScoreExportService.instance.getLabScoresForPreview();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => ScorePreviewDialog.lab(
        data,
        onExport: data.isNotEmpty
            ? () async {
                Navigator.pop(context);
                await _exportLabScores();
              }
            : null,
      ),
    );
  }

  Future<void> _exportLabScores() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('正在导出实验成绩…'),
      duration: Duration(seconds: 1),
    ));
    final path = await ScoreExportService.instance.exportLabScores();
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    if (path != null) {
      messenger.showSnackBar(SnackBar(
        content: Text('导出成功！\n$path'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '确定',
          onPressed: () => messenger.hideCurrentSnackBar(),
        ),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: const Text('暂无成绩数据可导出'),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: '确定',
          onPressed: () => messenger.hideCurrentSnackBar(),
        ),
      ));
    }
  }

  Widget _buildScoreActions(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<String>(
      icon: Icon(Icons.assessment, size: 20, color: primary),
      tooltip: '实验成绩',
      onSelected: (v) {
        if (v == 'view') _showLabScorePreview();
        if (v == 'export') _exportLabScores();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'view',
          child: Row(children: [
            Icon(Icons.table_chart, size: 18),
            SizedBox(width: 8),
            Text('查看成绩'),
          ]),
        ),
        const PopupMenuItem(
          value: 'export',
          child: Row(children: [
            Icon(Icons.file_download, size: 18),
            SizedBox(width: 8),
            Text('导出成绩'),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Tab 栏 + Agent 入口
        Container(
          color: primary.withValues(alpha: 0.05),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: primary,
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  indicatorColor: primary,
                  tabs: [
                    const Tab(
                        icon: Icon(Icons.science, size: 20), text: '任务列表'),
                    Tab(
                      icon: const Icon(Icons.assignment_turned_in, size: 20),
                      text: _isTeacherOrAdmin ? '提交管理' : '我的提交',
                    ),
                    const Tab(
                        icon: Icon(Icons.description, size: 20), text: '实验报告'),
                    const Tab(
                        icon: Icon(Icons.menu_book, size: 20), text: '实验材料'),
                    if (!_isTeacherOrAdmin)
                      const Tab(
                          icon: Icon(Icons.analytics, size: 20), text: '仓库报表'),
                    if (_isTeacherOrAdmin)
                      const Tab(
                          icon: Icon(Icons.settings, size: 20), text: '任务管理'),
                    if (_isTeacherOrAdmin)
                      const Tab(
                          icon: Icon(Icons.auto_awesome, size: 20),
                          text: 'AI批阅'),
                    if (_isTeacherOrAdmin)
                      const Tab(
                          icon: Icon(Icons.analytics, size: 20), text: '仓库报表'),
                  ],
                ),
              ),
              const AgentEntryButton(agentId: 'lab'),
              if (_isTeacherOrAdmin) _buildScoreActions(context),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _TaskListTab(authService: _authService, labTaskDao: _labTaskDao),
              _SubmissionTab(
                  authService: _authService, labTaskDao: _labTaskDao),
              _ReportTab(authService: _authService, labTaskDao: _labTaskDao),
              _MaterialsTab(authService: _authService),
              if (!_isTeacherOrAdmin)
                _StudentRepoTab(authService: _authService),
              if (_isTeacherOrAdmin)
                _TaskManageTab(
                    authService: _authService, labTaskDao: _labTaskDao),
              if (_isTeacherOrAdmin)
                LabAiGradingTab(
                    authService: _authService, labTaskDao: _labTaskDao),
              if (_isTeacherOrAdmin) const _RepoReportTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1: 任务列表
// ══════════════════════════════════════════════════════════════════════════════
