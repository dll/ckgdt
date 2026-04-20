import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../../services/courseware_service.dart';
import '../../../services/ai_service.dart';
import '../../../services/tts_service.dart';
import '../../../services/video_service.dart';
import '../../../data/local/ai_config_dao.dart';
import '../../../data/local/database_helper.dart';
import 'ai_settings_page.dart';

/// 课件工坊 — 教案→MD→PDF→UML→语音→视频 一站式课件生成
class CoursewareWorkshopPage extends StatefulWidget {
  const CoursewareWorkshopPage({super.key});

  @override
  State<CoursewareWorkshopPage> createState() => _CoursewareWorkshopPageState();
}

class _CoursewareWorkshopPageState extends State<CoursewareWorkshopPage> {
  final _coursewareService = CoursewareService();
  final _ttsService = TtsService();
  final _videoService = VideoService();
  final _configDao = AiConfigDao();

  // ── 状态 ──
  int _currentStep = 0;
  bool _hasApiKey = false;
  bool _checkingEnv = true;
  bool _hasFfmpeg = false;
  bool _hasEdgeTts = false;

  // ── Step 1: 教案 ──
  final _topicCtrl = TextEditingController();
  final _extraReqCtrl = TextEditingController();
  String _selectedChapter = '全部/自定义';
  int _classHours = 2;
  bool _generatingPlan = false;
  Map<String, dynamic>? _lessonPlan;
  bool _reviewingPlan = false;         // 教案审核中
  String? _planReviewResult;           // 教案审核结果
  int? _planReviewScore;               // 教案审核分数
  bool _applyingFix = false;           // AI 自动修改中

  // ── Step 2: 内容 ──
  String? _markdownContent;
  bool _generatingContent = false;
  List<Map<String, String>> _pumlResults = []; // {title, type, puml}
  List<Uint8List> _umlImages = [];

  // ── MD 导入 ──
  String? _importedMdPath;
  String? _rawMdContent;              // 原始 MD 文本（可编辑）
  final _mdEditCtrl = TextEditingController();
  bool _mdEditing = false;            // 是否处于编辑模式
  bool _aiReviewing = false;          // AI 审核中
  String? _aiReviewResult;            // AI 审核建议
  List<Map<String, dynamic>> _parsedSlides = [];
  bool _fromMdImport = false; // 标记是否从 MD 导入模式

  // ── MD 导入流程: 一键生成 ──
  bool _mdGeneratingAll = false;
  String _mdProgressMsg = '';
  double _mdProgress = 0;
  String? _mdVideoPath;  // MD 流程生成的视频路径
  List<String> _mdAudioPaths = []; // MD 流程的音频路径

  // ── Step 3: 导出 ──
  String? _pdfPath;
  String? _mdPath;
  String? _pptxPath;
  bool _exporting = false;
  bool _hasPythonPptx = false;

  // ── Step 4: 语音 ──
  List<Map<String, String>> _narrationScripts = [];
  List<String> _audioPaths = [];
  bool _generatingTts = false;
  String _ttsVoice = TtsService.defaultVoice;
  double _ttsProgress = 0;

  // ── Step 5: 视频 ──
  String? _videoPath;
  bool _generatingVideo = false;
  double _videoProgress = 0;
  String _videoStatus = '';

  // ── 发布状态 ──
  bool _published = false;       // AI 流程是否已发布
  bool _mdPublished = false;     // MD 导入流程是否已发布
  bool _publishing = false;

  static const _chapters = [
    '全部/自定义',
    '第1章 移动应用开发技术体系全景',
    '第2章 Android与iOS原生开发基础',
    '第3章 Flutter与跨平台开发',
    '第4章 微信小程序开发',
    '第5章 HarmonyOS鸿蒙开发',
    '第6章 综合开发实践',
  ];

  @override
  void initState() {
    super.initState();
    _checkEnvironment();
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _extraReqCtrl.dispose();
    _mdEditCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkEnvironment() async {
    final hasKey = await _configDao.hasApiKey();
    final hasFfmpeg = await _videoService.isFfmpegInstalled();
    final hasTts = await _ttsService.isEdgeTtsInstalled();
    final hasPptx = await _coursewareService.isPythonPptxInstalled();
    if (!mounted) return;
    setState(() {
      _hasApiKey = hasKey;
      _hasFfmpeg = hasFfmpeg;
      _hasEdgeTts = hasTts;
      _hasPythonPptx = hasPptx;
      _checkingEnv = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课件工坊'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'AI 设置',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AiSettingsPage()));
              _checkEnvironment();
            },
          ),
        ],
      ),
      body: _checkingEnv
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // ── 模式切换栏 ──
        _buildModeSelector(),
        const Divider(height: 1),
        // ── 内容 ──
        Expanded(
          child: _fromMdImport
              ? _buildMdImportFlow()
              : (_hasApiKey ? _buildAiFlow() : _buildNoApiKeyWarning()),
        ),
      ],
    );
  }

  /// 顶部模式选择器：AI 生成 / MD 导入
  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            avatar: Icon(_fromMdImport ? Icons.auto_awesome_outlined : Icons.auto_awesome,
                size: 18),
            label: const Text('AI 生成教案'),
            selected: !_fromMdImport,
            onSelected: (s) {
              if (s) setState(() => _fromMdImport = false);
            },
          ),
          const SizedBox(width: 12),
          ChoiceChip(
            avatar: Icon(_fromMdImport ? Icons.upload_file : Icons.upload_file_outlined,
                size: 18),
            label: const Text('导入 MD 文件'),
            selected: _fromMdImport,
            onSelected: (s) {
              if (s) setState(() {
                _fromMdImport = true;
                // 清除 AI 流程的旧数据，避免状态污染
                _pdfPath = null;
                _pptxPath = null;
                _mdVideoPath = null;
              });
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MD 导入流程
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMdImportFlow() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 文件选择 + 模板下载 ──
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择 Markdown 课件文件',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('支持按 "### 幻灯片N：标题" 格式拆分为独立幻灯片',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _mdGeneratingAll ? null : _doPickMdFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择 MD 文件'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _mdGeneratingAll ? null : _doDownloadTemplate,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('下载模板'),
                      ),
                      const SizedBox(width: 12),
                      if (_importedMdPath != null)
                        Expanded(
                          child: Text(
                            _importedMdPath!.split(Platform.pathSeparator).last,
                            style: TextStyle(fontSize: 13, color: Colors.green[700]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  if (_importedMdPath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '完整路径: $_importedMdPath',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── MD 内容预览/编辑 ──
          if (_rawMdContent != null) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.edit_document, color: Colors.indigo[700]),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('MD 内容预览与编辑',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        // 编辑/预览切换
                        TextButton.icon(
                          onPressed: _mdGeneratingAll ? null : () {
                            if (_mdEditing) {
                              // 保存编辑
                              setState(() {
                                _rawMdContent = _mdEditCtrl.text;
                                _mdEditing = false;
                              });
                              _reparseCurrentMd();
                            } else {
                              setState(() {
                                _mdEditCtrl.text = _rawMdContent!;
                                _mdEditing = true;
                              });
                            }
                          },
                          icon: Icon(_mdEditing ? Icons.check : Icons.edit, size: 18),
                          label: Text(_mdEditing ? '保存' : '编辑'),
                        ),
                        // AI 审核按钮
                        TextButton.icon(
                          onPressed: (_mdGeneratingAll || _aiReviewing)
                              ? null
                              : _doAiReview,
                          icon: _aiReviewing
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.rate_review, size: 18),
                          label: Text(_aiReviewing ? '审核中...' : 'AI 审核'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 400),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: _mdEditing ? Colors.white : Colors.grey.shade50,
                      ),
                      child: _mdEditing
                          ? TextField(
                              controller: _mdEditCtrl,
                              maxLines: null,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                height: 1.5,
                              ),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.all(12),
                                border: InputBorder.none,
                                hintText: '在此编辑 Markdown 内容...',
                              ),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                _rawMdContent!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),
                    ),
                    if (_mdEditing) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_mdEditCtrl.text.length} 字  |  编辑后点击"保存"重新解析幻灯片',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── AI 审核结果 ──
          if (_aiReviewResult != null) ...[
            Builder(builder: (_) {
              // 解析分数
              final scoreMatch =
                  RegExp(r'评分[：:]\s*(\d+)\s*/\s*100').firstMatch(_aiReviewResult!);
              final score =
                  scoreMatch != null ? int.tryParse(scoreMatch.group(1)!) : null;
              final scoreColor = score != null
                  ? (score >= 90
                      ? Colors.green
                      : score >= 80
                          ? Colors.orange
                          : Colors.red)
                  : Colors.amber;

              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                color: score != null && score >= 90
                    ? Colors.green.shade50
                    : Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb, color: scoreColor),
                          const SizedBox(width: 8),
                          const Text('AI 审核',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          if (score != null) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: scoreColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: scoreColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                '$score 分',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: scoreColor,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _aiReviewResult = null),
                          ),
                        ],
                      ),
                      const Divider(),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _aiReviewResult!,
                            style:
                                const TextStyle(fontSize: 13, height: 1.6),
                          ),
                        ),
                      ),
                      if (score == null || score < 90) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _aiReviewing
                                  ? null
                                  : () => _doAiAutoFixMd(),
                              icon: const Icon(Icons.auto_fix_high, size: 18),
                              label: const Text('AI 自动修改'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  _aiReviewing ? null : () => _doAiReview(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('重新审核'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // ── 解析结果预览 ──
          if (_parsedSlides.isNotEmpty) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.slideshow, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          '解析成功: ${_parsedSlides.length} 张幻灯片',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800]),
                        ),
                      ],
                    ),
                    const Divider(),
                    ...List.generate(
                      _parsedSlides.length,
                      (i) {
                        final slide = _parsedSlides[i];
                        final title = slide['title'] ?? '幻灯片 ${i + 1}';
                        final bullets = slide['bullets'] as List? ?? [];
                        final hasCode = (slide['code'] ?? '').toString().isNotEmpty;
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.blue[100],
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blue[800])),
                          ),
                          title: Text(title,
                              style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            '${bullets.length} 要点${hasCode ? ' + 代码' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── ★ 一键生成全部 ── ★
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: Colors.deepOrange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.deepOrange[700]),
                        const SizedBox(width: 8),
                        const Text('一键生成全部课件',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '自动生成 PPTX + PDF + TTS语音 + MP4教学视频',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _mdGeneratingAll || _exporting
                            ? null
                            : _doGenerateAllFromMd,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                        ),
                        icon: _mdGeneratingAll
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.rocket_launch),
                        label: Text(
                          _mdGeneratingAll
                              ? '正在生成...'
                              : '🚀 一键生成 PPTX + PDF + MP4',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                    if (_mdGeneratingAll) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _mdProgress,
                        backgroundColor: Colors.deepOrange.shade100,
                        color: Colors.deepOrange,
                      ),
                      const SizedBox(height: 6),
                      Text(_mdProgressMsg,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[700])),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 分步导出按钮组 ──
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('分步导出',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                    // PPTX 导出
                    _buildExportRow(
                      icon: Icons.slideshow,
                      title: 'PPTX 课件',
                      path: _pptxPath,
                      enabled: _hasPythonPptx,
                      hint: _hasPythonPptx ? '使用 python-pptx 生成' : '需安装: pip install python-pptx',
                      onGenerate: _doExportPptxFromMd,
                    ),
                    const Divider(),

                    // PDF 导出
                    _buildExportRow(
                      icon: Icons.picture_as_pdf,
                      title: 'PDF 课件',
                      path: _pdfPath,
                      enabled: true,
                      hint: '从 MD 内容生成 PDF 课件',
                      onGenerate: _doExportPdfFromMd,
                    ),
                    const Divider(),

                    // MP4 视频
                    _buildExportRow(
                      icon: Icons.videocam,
                      title: 'MP4 教学视频',
                      path: _mdVideoPath,
                      enabled: _hasFfmpeg && _hasEdgeTts && _pdfPath != null,
                      hint: _pdfPath == null
                          ? '请先生成 PDF'
                          : (_hasFfmpeg ? 'TTS语音 + PDF图片 → 视频' : '需安装 FFmpeg'),
                      onGenerate: _doGenerateVideoFromMd,
                    ),
                    const Divider(height: 24),

                    // 环境信息
                    _buildEnvCheck('python-pptx', _hasPythonPptx,
                        '运行: pip install python-pptx'),
                    _buildEnvCheck('edge_tts', _hasEdgeTts,
                        '运行: pip install edge-tts'),
                    _buildEnvCheck('FFmpeg', _hasFfmpeg,
                        '下载: ffmpeg.org/download.html'),
                    _buildEnvCheck('PyMuPDF', true,
                        '运行: pip install PyMuPDF'),
                  ],
                ),
              ),
            ),
          ],

          // ── 已生成的课件结果 ──
          if (_pptxPath != null || _pdfPath != null || _mdVideoPath != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.green.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Text('课件已生成',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800])),
                      ],
                    ),
                    if (_pptxPath != null)
                      _buildResultRow(Icons.slideshow, _pptxPath!, 'PPTX'),
                    if (_pdfPath != null)
                      _buildResultRow(Icons.picture_as_pdf, _pdfPath!, 'PDF'),
                    if (_mdVideoPath != null)
                      _buildResultRow(Icons.videocam, _mdVideoPath!, 'MP4'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: _mdPublished
                          ? OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.check, color: Colors.green),
                              label: const Text('已发布为扩展课件',
                                  style: TextStyle(color: Colors.green)),
                            )
                          : FilledButton.icon(
                              onPressed: _publishing
                                  ? null
                                  : () => _doPublish(isMdFlow: true),
                              icon: _publishing
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.publish),
                              label: Text(_publishing ? '正在发布...' : '发布为扩展课件'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建导出行
  Widget _buildExportRow({
    required IconData icon,
    required String title,
    String? path,
    required bool enabled,
    required String hint,
    required VoidCallback onGenerate,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon,
              color: path != null
                  ? Colors.green
                  : (enabled ? Colors.blue : Colors.grey)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                Text(
                  path != null
                      ? path.split(Platform.pathSeparator).last
                      : hint,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (path != null)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () => OpenFilex.open(path),
            ),
          if (enabled && !_exporting && !_mdGeneratingAll)
            TextButton(
              onPressed: onGenerate,
              child: Text(path != null ? '重新生成' : '生成'),
            ),
        ],
      ),
    );
  }

  /// 结果文件行
  Widget _buildResultRow(IconData icon, String path, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => OpenFilex.open(path),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text('$label: ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            Expanded(
              child: Text(
                path.split(Platform.pathSeparator).last,
                style: TextStyle(color: Colors.blue[700], fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.open_in_new, size: 16),
          ],
        ),
      ),
    );
  }

  /// 选择 MD 文件
  Future<void> _doPickMdFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
      dialogTitle: '选择 Markdown 课件文件',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    setState(() {
      _importedMdPath = path;
      _parsedSlides = [];
      _pptxPath = null;
      _pdfPath = null;
      _mdPublished = false;
      _rawMdContent = null;
      _aiReviewResult = null;
      _mdEditing = false;
    });

    // 读取原始内容
    try {
      final rawContent = await File(path).readAsString();
      setState(() {
        _rawMdContent = rawContent;
        _mdEditCtrl.text = rawContent;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取文件失败: $e')),
        );
      }
      return;
    }

    // 解析 MD 文件
    await _reparseCurrentMd();
  }

  /// 重新解析当前 MD 内容（编辑后或首次导入时）
  Future<void> _reparseCurrentMd() async {
    final content = _rawMdContent;
    if (content == null || content.trim().isEmpty) return;

    try {
      final slides = _coursewareService.parseMarkdownToSlides(content);
      if (!mounted) return;
      setState(() => _parsedSlides = slides);

      if (slides.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('未解析到幻灯片内容，请检查 MD 格式'),
              backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('成功解析 ${slides.length} 张幻灯片'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析失败: $e')),
        );
      }
    }
  }

  /// AI 审核 MD 内容
  Future<void> _doAiReview() async {
    final content = _rawMdContent;
    if (content == null || content.trim().isEmpty) return;

    setState(() {
      _aiReviewing = true;
      _aiReviewResult = null;
    });

    try {
      final aiService = (await _configDao.getConfig()) != null
          ? _coursewareService
          : null;

      if (aiService == null) {
        setState(() {
          _aiReviewing = false;
          _aiReviewResult = '未配置 AI 服务，无法审核';
        });
        return;
      }

      // 使用 AiService 进行审核
      final AiService ai = AiService();
      final review = await ai.chat(
        [{'role': 'user', 'content': content}],
        systemPrompt: '''你是一位课件质量审核专家。请对以下 Markdown 课件内容进行评审，从以下维度给出具体修改建议：

1. **结构完整性**：是否包含封面、目录、各章节、总结等必要部分
2. **内容质量**：知识点是否准确、是否有遗漏、深度是否足够
3. **教学设计**：是否符合教学规律（导入→讲授→练习→总结）
4. **格式规范**：标题层级是否正确、代码块是否标注语言、列表是否统一
5. **幻灯片拆分**：是否按 "### 幻灯片N：标题" 格式正确拆分，每页内容量是否合适（建议每页 4-6 个要点）

请用中文回复，给出评分（满分100）和具体修改建议。格式：
## 评分：XX/100
## 优点
- ...
## 需改进
- ...
## 具体修改建议
1. ...''',
      );

      if (!mounted) return;
      setState(() {
        _aiReviewing = false;
        _aiReviewResult = review;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiReviewing = false;
        _aiReviewResult = '审核失败: $e';
      });
    }
  }

  /// AI 根据审核建议自动修改 MD 内容
  Future<void> _doAiAutoFixMd() async {
    final content = _rawMdContent;
    if (content == null || _aiReviewResult == null) return;

    setState(() => _aiReviewing = true);

    try {
      final ai = AiService();
      final fixed = await ai.chat(
        [
          {
            'role': 'user',
            'content': '原始课件 MD:\n$content\n\n审核建议:\n$_aiReviewResult',
          },
        ],
        systemPrompt: '''你是一位课件制作专家。根据审核建议修改 Markdown 课件内容。

要求：
1. 严格按照审核建议逐条修改
2. 保持 "### 幻灯片N：标题" 的格式不变
3. 每张幻灯片保持 4-6 个要点
4. 保留代码块和表格等已有内容
5. 修改后直接返回完整的 Markdown 内容，不要包含任何解释''',
      );

      if (!mounted) return;

      // 更新 MD 内容
      setState(() {
        _rawMdContent = fixed;
        _mdEditCtrl.text = fixed;
        _aiReviewing = false;
        _aiReviewResult = null;
      });

      // 重新解析幻灯片
      _reparseCurrentMd();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ MD 内容已修改，请检查后重新审核'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiReviewing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自动修改失败: $e')),
        );
      }
    }
  }

  /// 下载 MD 课件模板
  Future<void> _doDownloadTemplate() async {
    const template = '''# 课程名称
> 授课教师：XXX | 适用对象：XX专业本科生

### 幻灯片1：课程导入
- 本节课的学习目标
- 预备知识回顾
- 本节内容概览

> 备注：用 1-2 分钟引入话题，激发学习兴趣

### 幻灯片2：核心概念
**副标题：基本定义与原理**
- 概念定义：XXX 是指...
- 核心原理：...
- 与相关概念的区别

> 备注：重点讲解，配合板书或演示

### 幻灯片3：技术架构
**副标题：系统组成与工作流程**
- 【模块一】功能描述
- 【模块二】功能描述
- 模块间的协作关系

| 组件 | 职责 | 技术选型 |
|------|------|---------|
| 前端 | UI展示 | Flutter |
| 后端 | 业务逻辑 | Spring Boot |

### 幻灯片4：代码演示
**副标题：实战代码讲解**
- 代码功能说明
- 关键实现要点

```dart
// 示例代码
class Example {
  void run() {
    print('Hello, World!');
  }
}
```

> 备注：逐行讲解代码逻辑，强调最佳实践

### 幻灯片5：对比分析
**副标题：方案优劣比较**
- 方案 A 的优势与不足
- 方案 B 的优势与不足
- 推荐选择依据

| 维度 | 方案A | 方案B |
|------|-------|-------|
| 性能 | 高 | 中 |
| 易用性 | 中 | 高 |
| 生态 | 丰富 | 一般 |

### 幻灯片6：实验环节
**副标题：动手实践**
- 实验目标：...
- 实验步骤：
  1. 环境准备
  2. 代码编写
  3. 运行测试
- 预期结果：...

> 备注：给学生 10-15 分钟完成实验

### 幻灯片7：课程总结
- 本节重点回顾
- 常见问题解答
- 课后作业布置
- 下节课预告

> 备注：总结时强调核心考点
''';

    try {
      final dir = await getApplicationDocumentsDirectory();
      final templateDir = Directory('${dir.path}/courseware/templates');
      if (!templateDir.existsSync()) {
        templateDir.createSync(recursive: true);
      }
      final filePath = '${templateDir.path}/课件模板.md';
      await File(filePath).writeAsString(template);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('模板已保存: $filePath'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: '打开',
            textColor: Colors.white,
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模板保存失败: $e')),
      );
    }
  }

  /// 从 MD 导出 PPTX
  Future<void> _doExportPptxFromMd() async {
    if (_parsedSlides.isEmpty || !_hasPythonPptx) return;
    setState(() => _exporting = true);

    try {
      // 提取标题
      final fileName = _importedMdPath?.split(Platform.pathSeparator).last ?? '';
      final title = fileName.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');

      final path = await _coursewareService.generatePptx(
        title: title.isNotEmpty ? title : '课件',
        slides: _parsedSlides,
        chapter: null,
      );

      setState(() {
        _pptxPath = path;
        _exporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(path != null ? '✅ PPTX 课件已生成' : '⚠️ PPTX 生成失败'),
            backgroundColor: path != null ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PPTX 生成失败: $e')),
        );
      }
    }
  }

  /// 从 MD 导出 PDF
  Future<void> _doExportPdfFromMd() async {
    if (_parsedSlides.isEmpty) return;
    setState(() => _exporting = true);

    try {
      final fileName = _importedMdPath?.split(Platform.pathSeparator).last ?? '';
      final title = fileName.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');

      // 构建教案结构以复用 PDF 生成逻辑
      final fakePlan = _buildFakePlanFromSlides(
        title.isNotEmpty ? title : '课件',
      );

      final path = await _coursewareService.generateEnhancedPdf(
        lessonPlan: fakePlan,
      );

      setState(() {
        _pdfPath = path;
        _exporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(path != null ? '✅ PDF 课件已生成' : '⚠️ PDF 生成失败'),
            backgroundColor: path != null ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 生成失败: $e')),
        );
      }
    }
  }

  /// ★ 一键生成全部: PPTX + PDF + TTS + MP4
  Future<void> _doGenerateAllFromMd() async {
    if (_parsedSlides.isEmpty) return;
    setState(() {
      _mdGeneratingAll = true;
      _mdProgress = 0;
      _mdProgressMsg = '准备生成...';
    });

    try {
      final fileName =
          _importedMdPath?.split(Platform.pathSeparator).last ?? '';
      final title =
          fileName.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
      final safeTitle = title.isNotEmpty ? title : '课件';

      // ── 1/5 生成 PPTX ──
      String? pptxPath;
      if (_hasPythonPptx) {
        setState(() {
          _mdProgress = 0.05;
          _mdProgressMsg = '(1/5) 正在生成 PPTX...';
        });
        pptxPath = await _coursewareService.generatePptx(
          title: safeTitle,
          slides: _parsedSlides,
        );
      }

      // ── 2/5 生成 PDF ──
      setState(() {
        _mdProgress = 0.15;
        _mdProgressMsg = '(2/5) 正在生成 PDF...';
      });
      final fakePlan = _buildFakePlanFromSlides(safeTitle);
      final pdfPath =
          await _coursewareService.generateEnhancedPdf(lessonPlan: fakePlan);

      // ── 3/5 生成 TTS 语音 ──
      List<String> audioPaths = [];
      if (_hasEdgeTts) {
        setState(() {
          _mdProgress = 0.25;
          _mdProgressMsg = '(3/5) 正在生成 TTS 语音...';
        });

        // 为每张幻灯片生成简短旁白文本
        final narrationTexts = _buildNarrationTexts(safeTitle);
        final coursewareDir = await _coursewareService.getCoursewareDir();
        final audioDir = '$coursewareDir/audio';

        audioPaths = await _ttsService.generateBatchAudio(
          scripts: narrationTexts,
          outputDir: audioDir,
          voice: _ttsVoice,
          onProgress: (current, total) {
            if (!mounted) return;
            setState(() {
              _mdProgress = 0.25 + 0.35 * (current / total);
              _mdProgressMsg =
                  '(3/5) TTS 语音 $current/$total...';
            });
          },
        );
      }

      // ── 4/5 用 Python PIL 直接渲染幻灯片图片（不经过 PDF→PNG） ──
      String? videoPath;
      if (_hasFfmpeg) {
        setState(() {
          _mdProgress = 0.65;
          _mdProgressMsg = '(4/5) 正在渲染幻灯片图片...';
        });

        final coursewareDir = await _coursewareService.getCoursewareDir();
        final slidesDir = '$coursewareDir/slides';

        final slideImages = await _coursewareService.generateSlideImages(
          title: safeTitle,
          slides: _parsedSlides,
          outputDir: slidesDir,
        );

        debugPrint('Workshop: PIL 渲染 ${slideImages.length} 张图片, '
            '旁白 ${audioPaths.length} 条');

        if (slideImages.isNotEmpty) {
          // ── 5/6 合成视频 ──
          setState(() {
            _mdProgress = 0.72;
            _mdProgressMsg = '(5/6) 正在合成教学视频...';
          });

          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final safeName =
              safeTitle.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
          final rawVideoPath =
              '$coursewareDir/${safeName}_raw_$timestamp.mp4';
          videoPath =
              '$coursewareDir/${safeName}_$timestamp.mp4';

          await _videoService.generateVideo(
            slides: slideImages,
            audios: audioPaths,
            outputPath: rawVideoPath,
            onProgress: (current, total, msg) {
              if (!mounted) return;
              setState(() {
                _mdProgress = 0.72 + 0.15 * (current / total);
                _mdProgressMsg = '(5/6) $msg';
              });
            },
          );

          // ── 6/6 生成 SRT 字幕并烧录 ──
          if (File(rawVideoPath).existsSync()) {
            setState(() {
              _mdProgress = 0.92;
              _mdProgressMsg = '(6/6) 正在生成字幕...';
            });

            final narrations = _buildNarrationTexts(safeTitle)
                .map((s) => s['narration'] ?? '')
                .toList();
            final srtPath = '$coursewareDir/${safeName}_$timestamp.srt';
            final srtResult = await _videoService.generateSrt(
              narrations: narrations,
              audioPaths: audioPaths,
              outputPath: srtPath,
            );

            if (srtResult != null) {
              final burned = await _videoService.burnSubtitles(
                videoPath: rawVideoPath,
                srtPath: srtPath,
                outputPath: videoPath,
              );
              if (burned != null) {
                try { File(rawVideoPath).deleteSync(); } catch (_) {}
              } else {
                try { File(rawVideoPath).renameSync(videoPath); } catch (_) {
                  videoPath = rawVideoPath;
                }
              }
            } else {
              try { File(rawVideoPath).renameSync(videoPath); } catch (_) {
                videoPath = rawVideoPath;
              }
            }
          }

          // 检查视频文件是否存在
          if (!File(videoPath).existsSync()) {
            videoPath = null;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _pptxPath = pptxPath;
        _pdfPath = pdfPath;
        _mdVideoPath = videoPath;
        _mdAudioPaths = audioPaths;
        _mdGeneratingAll = false;
        _mdProgress = 1.0;
        _mdProgressMsg = '全部生成完成！';
      });

      if (mounted) {
        final results = <String>[];
        if (pptxPath != null) results.add('PPTX');
        if (pdfPath != null) results.add('PDF');
        if (videoPath != null) results.add('MP4');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${results.join(" + ")} 课件已生成！'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _mdGeneratingAll = false;
        _mdProgressMsg = '生成失败: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e')),
        );
      }
    }
  }

  /// 单独生成视频（需已有 PDF）
  Future<void> _doGenerateVideoFromMd() async {
    if (_pdfPath == null || !_hasFfmpeg) return;

    setState(() {
      _exporting = true;
      _mdProgressMsg = '准备生成视频...';
    });

    try {
      final fileName =
          _importedMdPath?.split(Platform.pathSeparator).last ?? '';
      final safeTitle =
          fileName.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
      final coursewareDir = await _coursewareService.getCoursewareDir();

      // TTS 语音
      List<String> audioPaths = _mdAudioPaths;
      if (audioPaths.isEmpty && _hasEdgeTts) {
        final narrationTexts = _buildNarrationTexts(safeTitle);
        final audioDir = '$coursewareDir/audio';
        audioPaths = await _ttsService.generateBatchAudio(
          scripts: narrationTexts,
          outputDir: audioDir,
          voice: _ttsVoice,
        );
        setState(() => _mdAudioPaths = audioPaths);
      }

      // PDF → 图片
      final slidesDir = '$coursewareDir/slides';
      final slideImages = await _videoService.pdfToImages(
        pdfPath: _pdfPath!,
        outputDir: slidesDir,
      );

      if (slideImages.isEmpty) {
        setState(() => _exporting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ PDF 转图片失败')),
          );
        }
        return;
      }

      // 合成视频
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName =
          safeTitle.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final videoPath =
          '$coursewareDir/${safeName}_$timestamp.mp4';

      final success = await _videoService.generateVideo(
        slides: slideImages,
        audios: audioPaths,
        outputPath: videoPath,
      );

      setState(() {
        _exporting = false;
        _mdVideoPath = success ? videoPath : null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '✅ MP4 视频已生成' : '⚠️ 视频生成失败'),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频生成失败: $e')),
        );
      }
    }
  }

  /// 从幻灯片数据构建假教案结构（用于 PDF 生成）
  /// 注意：封面页和结束页由 generateEnhancedPdf 自动生成，
  /// 这里只需构建与 _parsedSlides 一一对应的 sections，
  /// 以保证 PDF 页数 = 封面(1) + sections(N) + 结束(1) = N+2
  /// 与 _buildNarrationTexts 产出的 N+2 条旁白严格对齐。
  Map<String, dynamic> _buildFakePlanFromSlides(String title) {
    return {
      'title': title,
      'chapter': '',
      'classHours': 2,
      'objectives': [],
      'keyPoints': [],
      'difficulties': [],
      'sections': _parsedSlides.map((s) {
            final bullets = (s['bullets'] as List? ?? []);
            // 每条 bullet 独立一行，保留原始结构（不再合并为一个大字符串）
            final items = <String>[];
            for (final b in bullets) {
              final text = b.toString().trim();
              if (text.isNotEmpty) items.add(text);
            }
            return {
              'title': s['title'] ?? '',
              'duration': '',
              'content': items.isNotEmpty ? items.join('\n') : '',
              'codeExample': s['code'] ?? '',
              'notes': s['notes'] ?? '',
            };
          }).toList(),
      'experiments': [],
      'umlDiagrams': [],
      'homework': '',
    };
  }

  /// 为每张幻灯片生成旁白脚本（用于 TTS）
  /// 原则：忠实于 MD 原文内容，优先使用 notes 备注作为讲解词，
  /// 无 notes 时从要点内容组织自然语言旁白
  List<Map<String, String>> _buildNarrationTexts(String courseTitle) {
    final scripts = <Map<String, String>>[];

    // 封面旁白
    scripts.add({
      'slide': '封面',
      'narration': '欢迎来到$courseTitle。我们开始今天的学习。',
    });

    // 每张幻灯片
    for (var i = 0; i < _parsedSlides.length; i++) {
      final slide = _parsedSlides[i];
      final title = slide['title']?.toString() ?? '';
      final subtitle = slide['subtitle']?.toString() ?? '';
      final bullets = slide['bullets'] as List? ?? [];
      final code = slide['code']?.toString() ?? '';
      final notes = slide['notes']?.toString() ?? '';

      final buf = StringBuffer();

      // 如果有备注（notes），优先用备注作为讲解词（教师手动写的讲稿）
      if (notes.isNotEmpty && notes.length > 10) {
        buf.write('$title。');
        if (subtitle.isNotEmpty) buf.write('$subtitle。');
        buf.write(notes);
        if (!notes.endsWith('。') && !notes.endsWith('！') && !notes.endsWith('？')) {
          buf.write('。');
        }
      } else {
        // 无备注时从幻灯片内容组织旁白
        buf.write('$title。');
        if (subtitle.isNotEmpty) {
          buf.write('$subtitle。');
        }

        // 收集所有文字要点（跳过表格行）
        final mainPoints = <String>[];
        final subSections = <String>[];
        for (final b in bullets) {
          final text = b.toString();
          if (text.startsWith('|')) continue; // 跳过表格
          if (text.startsWith('【') && text.endsWith('】')) {
            subSections.add(text.replaceAll('【', '').replaceAll('】', ''));
            continue;
          }
          final cleaned = text
              .replaceAll(RegExp(r'^  · '), '')
              .replaceAll(RegExp(r'^\d+\.\s*'), '')
              .replaceAll(RegExp(r'^[•\-]\s*'), '')
              .replaceAll(RegExp(r'^\*\*(.+?)\*\*'), r'$1')
              .trim();
          if (cleaned.length > 2) {
            mainPoints.add(cleaned);
          }
        }

        // 子章节概括
        if (subSections.isNotEmpty) {
          buf.write('涵盖${subSections.join("、")}。');
        }

        // 所有要点自然串联（限制总长度不超过300字，避免单页旁白过长）
        if (mainPoints.isNotEmpty) {
          final joined = mainPoints.join('；');
          if (joined.length <= 300) {
            buf.write(joined);
          } else {
            // 超长时取前部分并截断
            buf.write(joined.substring(0, 300));
          }
          if (!joined.endsWith('。')) buf.write('。');
        }
      }

      if (code.isNotEmpty) {
        buf.write('请看代码示例，理解其实现逻辑。');
      }

      final hasTable = bullets.any((b) => b.toString().startsWith('|'));
      if (hasTable) {
        buf.write('请参考表格中的对比分析。');
      }

      scripts.add({
        'slide': title,
        'narration': buf.toString(),
      });
    }

    // 结束旁白
    scripts.add({
      'slide': '结束',
      'narration': '本节课内容讲解完毕。请大家课后复习并完成练习。谢谢！',
    });

    return scripts;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI 生成流程 (Stepper 模式 — 增强版)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAiFlow() {
    return Column(
      children: [
        // ── 顶部进度可视化 ──
        _buildProgressBar(),
        const SizedBox(height: 8),
        Expanded(
          child: Stepper(
            currentStep: _currentStep,
            onStepContinue: _onStepContinue,
            onStepCancel: _currentStep > 0
                ? () => setState(() => _currentStep--)
                : null,
            onStepTapped: (step) {
              if (step <= _currentStep || _canGoToStep(step)) {
                setState(() => _currentStep = step);
              }
            },
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    if (_getStepAction() != null)
                      FilledButton.icon(
                        onPressed: _isStepBusy() ? null : _getStepAction(),
                        icon: _isStepBusy()
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(_getStepActionIcon()),
                        label: Text(_getStepActionLabel()),
                      ),
                    const SizedBox(width: 12),
                    if (_currentStep < 4 && _canGoToStep(_currentStep + 1))
                      FilledButton.tonalIcon(
                        onPressed: () => setState(() => _currentStep++),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('下一步'),
                      ),
                    const SizedBox(width: 8),
                    if (details.onStepCancel != null)
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: const Text('上一步'),
                      ),
                  ],
                ),
              );
            },
            steps: [
              _buildStep1(),
              _buildStep2(),
              _buildStep3(),
              _buildStep4(),
              _buildStep5(),
            ],
          ),
        ),
      ],
    );
  }

  /// 顶部进度指示条 — 显示每步完成状态 + 当前位置
  Widget _buildProgressBar() {
    final steps = ['教案', '内容', '课件', '语音', '视频'];
    final completed = [
      _lessonPlan != null,
      _markdownContent != null,
      _pdfPath != null || _pptxPath != null,
      _audioPaths.isNotEmpty,
      _videoPath != null,
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade50, Colors.blue.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // 连接线
            final leftDone = completed[i ~/ 2];
            return Expanded(
              child: Container(
                height: 3,
                color: leftDone ? Colors.green : Colors.grey.shade300,
              ),
            );
          }
          final idx = i ~/ 2;
          final isDone = completed[idx];
          final isCurrent = idx == _currentStep;
          return GestureDetector(
            onTap: () {
              if (idx <= _currentStep || _canGoToStep(idx)) {
                setState(() => _currentStep = idx);
              }
            },
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone
                        ? Colors.green
                        : isCurrent
                            ? Colors.deepPurple
                            : Colors.grey.shade300,
                    boxShadow: isCurrent
                        ? [BoxShadow(
                            color: Colors.deepPurple.withOpacity(0.3),
                            blurRadius: 8,
                          )]
                        : null,
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : Text(
                            '${idx + 1}',
                            style: TextStyle(
                              color: isCurrent ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[idx],
                  style: TextStyle(
                    fontSize: 10,
                    color: isCurrent ? Colors.deepPurple : Colors.grey,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 1: 教案设计
  // ═══════════════════════════════════════════════════════════════════════════

  Step _buildStep1() {
    return Step(
      title: const Text('教案设计'),
      subtitle: _lessonPlan != null
          ? Text(_lessonPlan!['title']?.toString() ?? '已生成')
          : const Text('输入主题，AI 生成教案'),
      isActive: _currentStep >= 0,
      state: _lessonPlan != null ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主题输入
          TextField(
            controller: _topicCtrl,
            decoration: const InputDecoration(
              labelText: '课程主题 *',
              hintText: '例如: Android Activity与生命周期',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.subject),
            ),
          ),
          const SizedBox(height: 12),

          // 章节选择
          DropdownButtonFormField<String>(
            value: _selectedChapter,
            decoration: const InputDecoration(
              labelText: '所属章节',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.book),
            ),
            items: _chapters
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _selectedChapter = v!),
          ),
          const SizedBox(height: 12),

          // 课时数
          Row(
            children: [
              const Text('课时数: '),
              ChoiceChip(
                label: const Text('1课时'),
                selected: _classHours == 1,
                onSelected: (s) => setState(() => _classHours = 1),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('2课时'),
                selected: _classHours == 2,
                onSelected: (s) => setState(() => _classHours = 2),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('3课时'),
                selected: _classHours == 3,
                onSelected: (s) => setState(() => _classHours = 3),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('4课时'),
                selected: _classHours == 4,
                onSelected: (s) => setState(() => _classHours = 4),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 额外要求
          TextField(
            controller: _extraReqCtrl,
            decoration: const InputDecoration(
              labelText: '额外要求（可选）',
              hintText: '例如: 包含SQLite数据库操作的实验',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.note_add),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          // ── 教案导入 ──
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('或者导入已有教案',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('支持 JSON / Markdown 格式的教案文件',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _generatingPlan ? null : _importLessonPlan,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('导入教案文件'),
                  ),
                ],
              ),
            ),
          ),

          // 教案预览
          if (_lessonPlan != null) ...[
            const SizedBox(height: 16),
            _buildLessonPlanPreview(),
            const SizedBox(height: 12),
            _buildPlanReviewSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildLessonPlanPreview() {
    final plan = _lessonPlan!;
    final sections = plan['sections'] as List? ?? [];
    final experiments = plan['experiments'] as List? ?? [];
    final objectives = plan['objectives'] as List? ?? [];

    return Card(
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✅ 教案已生成: ${plan['title']}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            Text('📋 教学目标 (${objectives.length}个)'),
            for (final obj in objectives)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 2),
                child: Text('• $obj', style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 8),
            Text('📝 教学环节 (${sections.length}个)'),
            for (final s in sections)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 2),
                child: Text(
                  '• ${(s as Map)['title']} (${s['duration']})',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            if (experiments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('🔬 实验项目 (${experiments.length}个)'),
              for (final e in experiments)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text('• ${(e as Map)['name']}',
                      style: const TextStyle(fontSize: 13)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 教案 AI 审核区域
  Widget _buildPlanReviewSection() {
    // 审核中
    if (_reviewingPlan) {
      return Card(
        color: Colors.blue.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('AI 正在审核教案质量...'),
            ],
          ),
        ),
      );
    }

    // 修改中
    if (_applyingFix) {
      return Card(
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('AI 正在根据建议修改教案...'),
            ],
          ),
        ),
      );
    }

    // 无审核结果
    if (_planReviewResult == null) {
      return OutlinedButton.icon(
        onPressed: _doReviewPlan,
        icon: const Icon(Icons.rate_review, size: 18),
        label: const Text('AI 审核教案'),
      );
    }

    // 显示审核结果
    final score = _planReviewScore;
    final Color scoreColor;
    final String scoreLabel;
    if (score != null) {
      if (score >= 90) {
        scoreColor = Colors.green;
        scoreLabel = '优秀';
      } else if (score >= 80) {
        scoreColor = Colors.orange;
        scoreLabel = '良好（建议修改）';
      } else if (score >= 60) {
        scoreColor = Colors.deepOrange;
        scoreLabel = '一般（需要修改）';
      } else {
        scoreColor = Colors.red;
        scoreLabel = '较差（建议重新生成）';
      }
    } else {
      scoreColor = Colors.grey;
      scoreLabel = '';
    }

    return Card(
      color: score != null && score >= 90
          ? Colors.green.shade50
          : Colors.amber.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题 + 分数
            Row(
              children: [
                Icon(
                  score != null && score >= 90
                      ? Icons.check_circle
                      : Icons.lightbulb,
                  color: scoreColor,
                ),
                const SizedBox(width: 8),
                const Text('AI 审核',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (score != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '$score 分 · $scoreLabel',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _planReviewResult = null;
                    _planReviewScore = null;
                  }),
                ),
              ],
            ),
            const Divider(),

            // 审核内容（可折叠）
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(
                  _planReviewResult!,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
              ),
            ),

            // 操作按钮（分数不满分时显示）
            if (score == null || score < 90) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _applyingFix ? null : _doApplyReviewFix,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('AI 自动修改'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _generatingPlan ? null : _doGeneratePlan,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重新生成教案'),
                    ),
                  ),
                ],
              ),
            ],

            // 满分直接提示
            if (score != null && score >= 90) ...[
              const SizedBox(height: 8),
              Text(
                '教案质量优秀，可以点击"下一步"继续生成内容。',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 2: 内容生成
  // ═══════════════════════════════════════════════════════════════════════════

  Step _buildStep2() {
    return Step(
      title: const Text('内容生成'),
      subtitle: _markdownContent != null
          ? const Text('Markdown + UML 已生成')
          : const Text('生成 Markdown 文档和 UML 图表'),
      isActive: _currentStep >= 1,
      state: _markdownContent != null ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_lessonPlan == null)
            const Text('⚠️ 请先完成教案设计', style: TextStyle(color: Colors.orange))
          else ...[
            const Text('从教案自动生成:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _featureChip(Icons.description, 'Markdown 文档',
                    _markdownContent != null),
                _featureChip(Icons.account_tree, 'UML 图表',
                    _pumlResults.isNotEmpty),
                _featureChip(Icons.image, 'UML 图片',
                    _umlImages.isNotEmpty),
              ],
            ),
            if (_markdownContent != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _markdownContent!,
                    style: const TextStyle(
                        fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
            if (_umlImages.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('UML 图表预览:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _umlImages.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Text(
                              i < _pumlResults.length
                                  ? _pumlResults[i]['title'] ?? 'UML'
                                  : 'UML ${i + 1}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Image.memory(_umlImages[i],
                                  fit: BoxFit.contain),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 3: 导出课件
  // ═══════════════════════════════════════════════════════════════════════════

  Step _buildStep3() {
    return Step(
      title: const Text('导出课件'),
      subtitle: _pdfPath != null || _pptxPath != null
          ? Text('${[
              if (_pdfPath != null) 'PDF',
              if (_pptxPath != null) 'PPTX',
            ].join(' + ')} 已生成')
          : const Text('导出 PDF / PPTX / Markdown'),
      isActive: _currentStep >= 2,
      state: _pdfPath != null || _pptxPath != null
          ? StepState.complete
          : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_markdownContent == null)
            const Text('⚠️ 请先生成内容',
                style: TextStyle(color: Colors.orange))
          else ...[
            // 生成产物预览卡片
            _buildFileCard(
              icon: Icons.slideshow,
              color: Colors.deepOrange,
              title: 'PPTX 课件（Prezi 风格）',
              subtitle: _pptxPath != null
                  ? _getFileInfo(_pptxPath!)
                  : (_hasPythonPptx
                      ? '渐变背景 + 动画入场 + 卡片式布局'
                      : '需安装: pip install python-pptx lxml'),
              isReady: _pptxPath != null,
              onOpen: _pptxPath != null ? () => OpenFilex.open(_pptxPath!) : null,
            ),
            const SizedBox(height: 8),
            _buildFileCard(
              icon: Icons.picture_as_pdf,
              color: Colors.red,
              title: 'PDF 课件（含 UML 图）',
              subtitle: _pdfPath != null
                  ? _getFileInfo(_pdfPath!)
                  : 'A4横版，封面/教学过程/UML/实验',
              isReady: _pdfPath != null,
              onOpen: _pdfPath != null ? () => OpenFilex.open(_pdfPath!) : null,
            ),
            const SizedBox(height: 8),
            _buildFileCard(
              icon: Icons.article,
              color: Colors.blue,
              title: 'Markdown 文档',
              subtitle: _mdPath != null
                  ? _getFileInfo(_mdPath!)
                  : '完整教案的 Markdown 格式',
              isReady: _mdPath != null,
              onOpen: _mdPath != null ? () => OpenFilex.open(_mdPath!) : null,
            ),
            if (!_hasPythonPptx) ...[
              const SizedBox(height: 8),
              _buildEnvCheck('python-pptx + lxml', false,
                  '运行: pip install python-pptx lxml'),
            ],
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 4: 语音合成
  // ═══════════════════════════════════════════════════════════════════════════

  Step _buildStep4() {
    return Step(
      title: const Text('语音合成'),
      subtitle: _audioPaths.isNotEmpty
          ? Text('已生成 ${_audioPaths.length} 段语音')
          : const Text('AI 生成旁白 + TTS 语音'),
      isActive: _currentStep >= 3,
      state: _audioPaths.isNotEmpty ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 环境检查
          _buildEnvCheck('edge_tts', _hasEdgeTts,
              '运行: pip install edge-tts'),
          const SizedBox(height: 12),

          // 语音选择
          DropdownButtonFormField<String>(
            value: _ttsVoice,
            decoration: const InputDecoration(
              labelText: '语音角色',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.record_voice_over),
            ),
            items: TtsService.voices.entries
                .map((e) => DropdownMenuItem(
                    value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _ttsVoice = v!),
          ),
          const SizedBox(height: 12),

          // 脚本预览
          if (_narrationScripts.isNotEmpty) ...[
            Text('旁白脚本 (${_narrationScripts.length}段):',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _narrationScripts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final script = _narrationScripts[i];
                  final hasAudio =
                      i < _audioPaths.length && _audioPaths[i].isNotEmpty;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      hasAudio ? Icons.check_circle : Icons.pending,
                      color: hasAudio ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    title: Text(script['slide'] ?? '段落${i + 1}',
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      script['narration'] ?? '',
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ],

          // 进度
          if (_generatingTts) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _ttsProgress),
            Text('正在合成语音... ${(_ttsProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],

          // 语音完成后显示：下一步去合成视频
          if (_audioPaths.isNotEmpty && !_generatingTts) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text('语音合成完成（${_audioPaths.length}段）',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _currentStep = 4),
                icon: const Icon(Icons.videocam),
                label: const Text('下一步：合成视频'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Step 5: 视频合成
  // ═══════════════════════════════════════════════════════════════════════════

  Step _buildStep5() {
    return Step(
      title: const Text('视频合成'),
      subtitle: _videoPath != null
          ? const Text('视频已生成')
          : const Text('合成教学视频 (MP4)'),
      isActive: _currentStep >= 4,
      state: _videoPath != null ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEnvCheck('FFmpeg', _hasFfmpeg,
              '下载: https://ffmpeg.org/download.html'),
          _buildEnvCheck('Python + PyMuPDF', true,
              '运行: pip install PyMuPDF'),
          const SizedBox(height: 12),

          if (_pdfPath == null && _pptxPath == null)
            const Text('⚠️ 请先导出 PDF 或 PPTX 课件',
                style: TextStyle(color: Colors.orange)),

          if (_audioPaths.isEmpty)
            const Text('⚠️ 建议先生成语音',
                style: TextStyle(color: Colors.orange)),

          // ── 合成视频按钮（独立、醒目）──
          if (_videoPath == null && !_generatingVideo &&
              (_pdfPath != null || _pptxPath != null)) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _hasFfmpeg ? _doGenerateVideo : null,
                icon: const Icon(Icons.videocam, size: 24),
                label: Text(_audioPaths.isNotEmpty
                    ? '合成视频（含语音旁白）'
                    : '合成视频（无语音）'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],

          if (_videoPath != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.green.shade50,
              child: ListTile(
                leading: const Icon(Icons.videocam, color: Colors.green),
                title: const Text('教学视频已生成'),
                subtitle: Text(_videoPath!,
                    style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.play_circle_filled,
                      color: Colors.green, size: 36),
                  onPressed: () => OpenFilex.open(_videoPath!),
                ),
              ),
            ),
          ],

          if (_generatingVideo) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _videoProgress),
            Text(_videoStatus,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],

          // ── 发布为扩展课件 ──
          if (_pdfPath != null || _pptxPath != null || _videoPath != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _published
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check, color: Colors.green),
                      label: const Text('已发布为扩展课件',
                          style: TextStyle(color: Colors.green)),
                    )
                  : FilledButton.icon(
                      onPressed: _publishing
                          ? null
                          : () => _doPublish(isMdFlow: false),
                      icon: _publishing
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.publish),
                      label: Text(_publishing ? '正在发布...' : '发布为扩展课件'),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 发布为扩展课件 → 写入 resource_files 表
  // ═══════════════════════════════════════════════════════════════════════════

  /// 将已生成的课件发布到 resource_files 表，使其出现在"课程资料"列表中
  Future<void> _doPublish({required bool isMdFlow}) async {
    setState(() => _publishing = true);

    try {
      final db = await DatabaseHelper.instance.database;

      // 确定标题和章节
      final title = isMdFlow
          ? (_importedMdPath?.split(Platform.pathSeparator).last ?? '课件')
              .replaceAll(RegExp(r'\.(md|markdown|txt)$'), '')
          : (_lessonPlan?['title']?.toString() ?? '课件');

      // 尝试从章节选择中提取章节名
      final chapter = _selectedChapter == '全部/自定义' ? title : _selectedChapter;

      // 获取当前流程的文件路径
      final pdfPath = isMdFlow ? _pdfPath : _pdfPath;
      final pptxPath = isMdFlow ? _pptxPath : _pptxPath;
      final videoPath = isMdFlow ? _mdVideoPath : _videoPath;

      int publishedCount = 0;

      // 发布 PDF
      if (pdfPath != null && File(pdfPath).existsSync()) {
        await db.insert('resource_files', {
          'file_name': '$title.pdf',
          'file_path': pdfPath,
          'file_type': 'pdf',
          'chapter': chapter,
          'description': '[AI生成] $title 课件',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        publishedCount++;
      }

      // 发布 PPT/PPTX
      if (pptxPath != null && File(pptxPath).existsSync()) {
        await db.insert('resource_files', {
          'file_name': '$title.pptx',
          'file_path': pptxPath,
          'file_type': 'ppt',
          'chapter': chapter,
          'description': '[AI生成] $title 课件',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        publishedCount++;
      }

      // 发布视频
      if (videoPath != null && File(videoPath).existsSync()) {
        await db.insert('resource_files', {
          'file_name': '$title.mp4',
          'file_path': videoPath,
          'file_type': 'video',
          'chapter': chapter,
          'description': '[AI生成] $title 教学视频',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        publishedCount++;
      }

      if (!mounted) return;

      setState(() {
        _publishing = false;
        if (isMdFlow) {
          _mdPublished = true;
        } else {
          _published = true;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已发布 $publishedCount 个课件到课程资料'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() => _publishing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发布失败: $e')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 环境检查组件
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEnvCheck(String name, bool installed, String installCmd) {
    return Row(
      children: [
        Icon(
          installed ? Icons.check_circle : Icons.warning,
          color: installed ? Colors.green : Colors.orange,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text('$name: ',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(
          installed ? '已安装' : '未安装',
          style: TextStyle(
              color: installed ? Colors.green : Colors.orange,
              fontSize: 13),
        ),
        if (!installed) ...[
          const SizedBox(width: 8),
          Text(installCmd,
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade600)),
        ],
      ],
    );
  }

  Widget _featureChip(IconData icon, String label, bool done) {
    return Chip(
      avatar: Icon(
        done ? Icons.check_circle : icon,
        color: done ? Colors.green : Colors.grey,
        size: 18,
      ),
      label: Text(label),
      backgroundColor: done ? Colors.green.shade50 : Colors.grey.shade100,
    );
  }

  /// 文件预览卡片 — 显示生成状态、文件大小、打开按钮
  Widget _buildFileCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isReady,
    VoidCallback? onOpen,
  }) {
    return Card(
      elevation: isReady ? 2 : 0,
      color: isReady ? Colors.green.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isReady ? Colors.green.shade200 : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isReady ? Colors.green : color.withOpacity(0.15),
          child: Icon(
            isReady ? Icons.check : icon,
            color: isReady ? Colors.white : color,
            size: 22,
          ),
        ),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: isReady
            ? FilledButton.tonalIcon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开', style: TextStyle(fontSize: 12)),
              )
            : Icon(Icons.pending, color: Colors.grey.shade400, size: 22),
      ),
    );
  }

  /// 获取文件信息（名称 + 大小）
  String _getFileInfo(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        final size = file.lengthSync();
        final sizeStr = size > 1024 * 1024
            ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
            : '${(size / 1024).toStringAsFixed(0)} KB';
        final name = path.split(Platform.pathSeparator).last;
        return '$name ($sizeStr)';
      }
    } catch (_) {}
    return path.split(Platform.pathSeparator).last;
  }

  Widget _buildNoApiKeyWarning() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.key_off, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('请先配置 AI API Key',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('课件工坊依赖 AI 服务生成教案和内容',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AiSettingsPage()));
                _checkEnvironment();
              },
              icon: const Icon(Icons.settings),
              label: const Text('前往设置'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Stepper 控制逻辑
  // ═══════════════════════════════════════════════════════════════════════════

  bool _canGoToStep(int step) {
    switch (step) {
      case 0:
        return true;
      case 1:
        return _lessonPlan != null;
      case 2:
        return _markdownContent != null;
      case 3:
        return _pdfPath != null || _pptxPath != null || _markdownContent != null;
      case 4:
        return _markdownContent != null || _pdfPath != null || _pptxPath != null || _audioPaths.isNotEmpty;
      default:
        return false;
    }
  }

  bool _isStepBusy() {
    switch (_currentStep) {
      case 0:
        return _generatingPlan;
      case 1:
        return _generatingContent;
      case 2:
        return _exporting;
      case 3:
        return _generatingTts;
      case 4:
        return _generatingVideo;
      default:
        return false;
    }
  }

  VoidCallback? _getStepAction() {
    switch (_currentStep) {
      case 0:
        return _topicCtrl.text.trim().isNotEmpty ? _doGeneratePlan : null;
      case 1:
        return _lessonPlan != null ? _doGenerateContent : null;
      case 2:
        return _markdownContent != null ? _doExport : null;
      case 3:
        return _hasEdgeTts ? _doGenerateTts : null;
      case 4:
        return _hasFfmpeg && (_pdfPath != null || _pptxPath != null) ? _doGenerateVideo : null;
      default:
        return null;
    }
  }

  IconData _getStepActionIcon() {
    switch (_currentStep) {
      case 0:
        return Icons.auto_awesome;
      case 1:
        return Icons.create;
      case 2:
        return Icons.download;
      case 3:
        return Icons.record_voice_over;
      case 4:
        return Icons.videocam;
      default:
        return Icons.play_arrow;
    }
  }

  String _getStepActionLabel() {
    switch (_currentStep) {
      case 0:
        return _generatingPlan
            ? 'AI 生成教案中...'
            : (_lessonPlan != null ? '重新生成教案' : '生成教案');
      case 1:
        return _generatingContent ? '正在生成...' : '生成内容';
      case 2:
        return _exporting ? '导出中...' : '导出 PDF + PPTX + MD';
      case 3:
        return _generatingTts ? '合成语音中...' : '生成旁白 + 语音';
      case 4:
        return _generatingVideo ? '合成视频中...' : '合成视频';
      default:
        return '执行';
    }
  }

  void _onStepContinue() {
    if (_currentStep < 4 && _canGoToStep(_currentStep + 1)) {
      setState(() => _currentStep++);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 业务逻辑
  // ═══════════════════════════════════════════════════════════════════════════

  /// 导入已有教案（支持 JSON 或 Markdown 格式）
  Future<void> _importLessonPlan() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'md', 'markdown', 'txt'],
        dialogTitle: '选择教案文件',
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final content = await File(filePath).readAsString();
      Map<String, dynamic>? plan;

      if (filePath.endsWith('.json')) {
        // JSON 格式教案
        try {
          final parsed = await Future(() => _parseJsonPlan(content));
          plan = parsed;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('JSON 解析失败: $e')),
            );
          }
          return;
        }
      } else {
        // Markdown 格式 — 解析为 slides 然后构建教案
        final slides = _coursewareService.parseMarkdownToSlides(content);
        if (slides.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('无法从文件中解析出幻灯片内容')),
            );
          }
          return;
        }

        // 从文件名提取标题
        final fileName = filePath.split(Platform.pathSeparator).last;
        final title = fileName.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');

        plan = {
          'title': title,
          'chapter': _selectedChapter == '全部/自定义' ? '' : _selectedChapter,
          'classHours': _classHours,
          'objectives': ['掌握$title相关核心知识'],
          'keyPoints': [],
          'difficulties': [],
          'sections': slides.map((s) {
            final bullets = (s['bullets'] as List? ?? []);
            return {
              'title': s['title'] ?? '',
              'duration': '${(_classHours * 45 / slides.length).round()}分钟',
              'content': bullets.map((b) => b.toString()).join('\n'),
              'codeExample': s['code'] ?? '',
              'notes': s['notes'] ?? '',
            };
          }).toList(),
          'experiments': [],
          'umlDiagrams': [],
          'homework': '',
        };
      }

      if (plan != null) {
        setState(() {
          _lessonPlan = plan;
          _topicCtrl.text = plan!['title']?.toString() ?? '';
          // 重置后续步骤
          _markdownContent = null;
          _pumlResults = [];
          _umlImages = [];
          _pdfPath = null;
          _pptxPath = null;
          _mdPath = null;
          _narrationScripts = [];
          _audioPaths = [];
          _videoPath = null;
          _published = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ 教案已导入: ${plan['title']}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  /// 解析 JSON 格式教案
  Map<String, dynamic> _parseJsonPlan(String content) {
    final data = Map<String, dynamic>.from(
      (content.contains('{'))
          ? _tryParseJson(content)
          : {'title': '导入的教案', 'sections': []},
    );
    // 确保必要字段存在
    data['title'] ??= '导入的教案';
    data['classHours'] ??= _classHours;
    data['objectives'] ??= [];
    data['keyPoints'] ??= [];
    data['difficulties'] ??= [];
    data['sections'] ??= [];
    data['experiments'] ??= [];
    data['umlDiagrams'] ??= [];
    data['homework'] ??= '';
    return data;
  }

  dynamic _tryParseJson(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return jsonDecode(content.substring(start, end + 1));
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  /// Step 1: AI 生成教案
  Future<void> _doGeneratePlan() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) return;

    setState(() => _generatingPlan = true);

    try {
      final chapter = _selectedChapter == '全部/自定义'
          ? null
          : _selectedChapter;
      final plan = await _coursewareService.generateLessonPlan(
        topic: topic,
        chapter: chapter,
        classHours: _classHours,
        additionalRequirements: _extraReqCtrl.text.trim().isEmpty
            ? null
            : _extraReqCtrl.text.trim(),
      );

      setState(() {
        _lessonPlan = plan;
        _generatingPlan = false;
        // 重置后续步骤
        _markdownContent = null;
        _pumlResults = [];
        _umlImages = [];
        _pdfPath = null;
        _pptxPath = null;
        _mdPath = null;
        _narrationScripts = [];
        _audioPaths = [];
        _videoPath = null;
        _planReviewResult = null;
        _planReviewScore = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ 教案生成成功，正在进行AI审核...'),
              backgroundColor: Colors.green),
        );
      }

      // 自动审核教案
      await _doReviewPlan();
    } catch (e) {
      setState(() => _generatingPlan = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('教案生成失败: $e')),
        );
      }
    }
  }

  /// 审核教案质量
  Future<void> _doReviewPlan() async {
    if (_lessonPlan == null) return;
    setState(() {
      _reviewingPlan = true;
      _planReviewResult = null;
      _planReviewScore = null;
    });

    try {
      final ai = AiService();
      final planJson = jsonEncode(_lessonPlan);
      final review = await ai.chat(
        [{'role': 'user', 'content': planJson}],
        systemPrompt: '''你是一位课程设计审核专家。请对以下教案 JSON 进行评审，从以下维度给出分数和建议：

1. **教学目标**：是否明确、可衡量、符合布鲁姆认知层次
2. **教学内容**：知识点是否全面、准确、深度适当
3. **教学设计**：环节衔接是否流畅（导入→讲授→练习→总结）
4. **时间分配**：各环节时间是否合理
5. **实验设计**：实验步骤是否可操作、目标是否明确

请严格按以下格式回复（不要修改格式）：
## 评分：XX/100
## 优点
- ...
## 需改进
- ...
## 具体修改建议
1. ...''',
      );

      // 解析分数
      int? score;
      final scoreMatch = RegExp(r'评分[：:]\s*(\d+)\s*/\s*100').firstMatch(review);
      if (scoreMatch != null) {
        score = int.tryParse(scoreMatch.group(1)!);
      }

      if (!mounted) return;
      setState(() {
        _reviewingPlan = false;
        _planReviewResult = review;
        _planReviewScore = score;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reviewingPlan = false;
        _planReviewResult = '审核失败: $e';
      });
    }
  }

  /// AI 根据审核建议自动修改教案
  Future<void> _doApplyReviewFix() async {
    if (_lessonPlan == null || _planReviewResult == null) return;

    setState(() => _applyingFix = true);

    try {
      final ai = AiService();
      final response = await ai.chat(
        [
          {
            'role': 'user',
            'content': '原始教案:\n${jsonEncode(_lessonPlan)}\n\n审核建议:\n$_planReviewResult'
          },
        ],
        systemPrompt: '''你是一位课程设计专家。根据审核建议修改教案。

要求：
1. 严格按照审核建议逐条修改
2. 保持原有教案的 JSON 结构不变
3. 只修改需要改进的部分，保留优秀的内容
4. 必须返回完整的修改后教案 JSON

请直接返回修改后的完整 JSON，不要包含任何解释文字，不要使用 markdown 代码块。''',
      );

      // 解析修改后的教案
      final fixedPlan = _tryParseJson(response);
      if (fixedPlan != null && fixedPlan is Map<String, dynamic>) {
        setState(() {
          _lessonPlan = fixedPlan;
          _applyingFix = false;
          // 清除旧的审核结果
          _planReviewResult = null;
          _planReviewScore = null;
          // 重置后续步骤
          _markdownContent = null;
          _pumlResults = [];
          _umlImages = [];
          _pdfPath = null;
          _pptxPath = null;
          _mdPath = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('✅ 教案已根据建议修改，正在重新审核...'),
                backgroundColor: Colors.green),
          );
        }
        // 重新审核
        await _doReviewPlan();
      } else {
        setState(() => _applyingFix = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('⚠️ AI 返回的修改结果格式异常，请重试'),
                backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) {
      setState(() => _applyingFix = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('修改失败: $e')),
        );
      }
    }
  }

  /// Step 2: 生成 Markdown + UML
  Future<void> _doGenerateContent() async {
    if (_lessonPlan == null) return;

    setState(() => _generatingContent = true);

    try {
      // 生成 Markdown
      final md = _coursewareService.generateMarkdown(_lessonPlan!);

      // 生成 UML 图表
      final pumlResults =
          await _coursewareService.generateAllPuml(_lessonPlan!);

      // 渲染 UML 图片
      final images = <Uint8List>[];
      for (final puml in pumlResults) {
        final code = puml['puml'] ?? '';
        if (code.isNotEmpty) {
          try {
            final imgBytes = await _coursewareService.renderPumlToPng(code);
            if (imgBytes != null) images.add(imgBytes);
          } catch (e) {
            debugPrint('Render PUML error: $e');
          }
        }
      }

      setState(() {
        _markdownContent = md;
        _pumlResults = pumlResults;
        _umlImages = images;
        _generatingContent = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 内容已生成 (UML: ${images.length}张)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _generatingContent = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('内容生成失败: $e')),
        );
      }
    }
  }

  /// Step 3: 导出 PDF + PPTX + MD
  Future<void> _doExport() async {
    if (_lessonPlan == null || _markdownContent == null) return;

    setState(() => _exporting = true);

    try {
      // 导出 PDF
      final pdfPath = await _coursewareService.generateEnhancedPdf(
        lessonPlan: _lessonPlan!,
        umlImages: _umlImages.isNotEmpty ? _umlImages : null,
      );

      // 导出 MD
      final mdPath = await _coursewareService.exportMarkdownFile(
        markdown: _markdownContent!,
        title: _lessonPlan!['title']?.toString() ?? '教案',
        chapter: _lessonPlan!['chapter']?.toString(),
      );

      // 导出 PPTX（如果 python-pptx 可用）
      String? pptxPath;
      if (_hasPythonPptx) {
        try {
          // 直接从教案生成幻灯片数据（不经过 Markdown 解析）
          final slides =
              _coursewareService.lessonPlanToSlides(_lessonPlan!);
          if (slides.isNotEmpty) {
            pptxPath = await _coursewareService.generatePptx(
              title: _lessonPlan!['title']?.toString() ?? '教案',
              slides: slides,
              chapter: _lessonPlan!['chapter']?.toString(),
            );
          }
        } catch (e) {
          debugPrint('PPTX export error: $e');
        }
      }

      setState(() {
        _pdfPath = pdfPath;
        _mdPath = mdPath;
        _pptxPath = pptxPath;
        _exporting = false;
      });

      if (mounted) {
        final results = <String>[];
        if (pdfPath != null) results.add('PDF');
        if (pptxPath != null) results.add('PPTX');
        if (mdPath != null) results.add('MD');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(results.isNotEmpty
                ? '✅ ${results.join(" + ")} 已导出'
                : '⚠️ 导出失败'),
            backgroundColor:
                results.isNotEmpty ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// Step 4: 生成旁白脚本 + TTS 语音
  Future<void> _doGenerateTts() async {
    if (_lessonPlan == null) return;

    setState(() {
      _generatingTts = true;
      _ttsProgress = 0;
    });

    try {
      // 1. AI 生成旁白脚本
      if (_narrationScripts.isEmpty) {
        final scripts =
            await _coursewareService.generateNarrationScripts(_lessonPlan!);
        setState(() => _narrationScripts = scripts);
      }

      if (_narrationScripts.isEmpty) {
        setState(() => _generatingTts = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('旁白脚本生成为空')),
          );
        }
        return;
      }

      // 2. TTS 合成
      final coursewareDir = await _coursewareService.getCoursewareDir();
      final audioDir = '$coursewareDir/audio';

      final paths = await _ttsService.generateBatchAudio(
        scripts: _narrationScripts,
        outputDir: audioDir,
        voice: _ttsVoice,
        onProgress: (current, total) {
          setState(() => _ttsProgress = current / total);
        },
      );

      setState(() {
        _audioPaths = paths;
        _generatingTts = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已生成 ${paths.length} 段语音'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _generatingTts = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('语音生成失败: $e')),
        );
      }
    }
  }

  /// Step 5: 合成视频
  Future<void> _doGenerateVideo() async {
    if ((_pdfPath == null && _pptxPath == null) || !_hasFfmpeg) return;

    setState(() {
      _generatingVideo = true;
      _videoProgress = 0;
      _videoStatus = '正在将 PDF 转为图片...';
    });

    try {
      // 1. 课件 → 图片
      final coursewareDir = await _coursewareService.getCoursewareDir();
      final slidesDir = '$coursewareDir/slides';
      List<String> slideImages = [];

      if (_pdfPath != null) {
        // 优先用 PDF → 图片
        slideImages = await _videoService.pdfToImages(
          pdfPath: _pdfPath!,
          outputDir: slidesDir,
        );
      }

      // PDF 转图片失败或没有 PDF → 尝试用 PIL 直接渲染幻灯片
      if (slideImages.isEmpty && _markdownContent != null) {
        final slides = _coursewareService.parseMarkdownToSlides(_markdownContent!);
        if (slides.isNotEmpty) {
          final title = _lessonPlan?['title']?.toString() ?? '教案';
          slideImages = await _coursewareService.generateSlideImages(
            title: title,
            slides: slides,
            outputDir: slidesDir,
          );
        }
      }

      if (slideImages.isEmpty) {
        setState(() {
          _generatingVideo = false;
          _videoStatus = '课件转图片失败（请安装 PyMuPDF: pip install PyMuPDF）';
        });
        return;
      }

      setState(() {
        _videoProgress = 0.1;
        _videoStatus = '幻灯片: ${slideImages.length}张，开始合成...';
      });

      // 2. 图片 + 音频 → 视频
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final title = _lessonPlan?['title']?.toString() ?? '教案';
      final safeTitle =
          title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final outputPath =
          '$coursewareDir/${safeTitle}_$timestamp.mp4';

      final success = await _videoService.generateVideo(
        slides: slideImages,
        audios: _audioPaths,
        outputPath: outputPath,
        onProgress: (current, total, msg) {
          setState(() {
            _videoProgress = 0.1 + 0.9 * (current / total);
            _videoStatus = msg;
          });
        },
      );

      setState(() {
        _generatingVideo = false;
        _videoPath = success ? outputPath : null;
        _videoStatus = success ? '视频生成完成！' : '视频合成失败';
      });

      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 教学视频已生成'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _generatingVideo = false;
        _videoStatus = '生成失败: $e';
      });
    }
  }
}
