import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../../../services/courseware_service.dart';
import '../../../services/tts_service.dart';
import '../../../services/video_service.dart';
import '../../../data/local/ai_config_dao.dart';
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

  // ── Step 2: 内容 ──
  String? _markdownContent;
  bool _generatingContent = false;
  List<Map<String, String>> _pumlResults = []; // {title, type, puml}
  List<Uint8List> _umlImages = [];

  // ── MD 导入 ──
  String? _importedMdPath;
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

  static const _chapters = [
    '全部/自定义',
    '第1章 Android开发基础',
    '第2章 UI界面设计',
    '第3章 Activity与生命周期',
    '第4章 数据存储',
    '第5章 网络编程',
    '第6章 综合项目实战',
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
              if (s) setState(() => _fromMdImport = true);
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
          // ── 文件选择 ──
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
    });

    // 解析 MD 文件
    try {
      final slides = await _coursewareService.parseMdFile(path);
      if (!mounted) return;
      setState(() => _parsedSlides = slides);

      if (slides.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('⚠️ 未解析到幻灯片内容，请检查 MD 格式'),
              backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('✅ 成功解析 ${slides.length} 张幻灯片'),
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
      final fakePlan = <String, dynamic>{
        'title': title.isNotEmpty ? title : '课件',
        'chapter': '',
        'classHours': 2,
        'objectives': [],
        'keyPoints': [],
        'difficulties': [],
        'sections': _parsedSlides.map((s) => {
              'title': s['title'] ?? '',
              'duration': '',
              'content':
                  (s['bullets'] as List? ?? []).join('\n'),
              'codeExample': s['code'] ?? '',
              'notes': s['notes'] ?? '',
            }).toList(),
        'experiments': [],
        'umlDiagrams': [],
        'homework': '',
      };

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
      if (_hasEdgeTts && pdfPath != null) {
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
          // ── 5/5 合成视频 ──
          setState(() {
            _mdProgress = 0.75;
            _mdProgressMsg = '(5/5) 正在合成教学视频...';
          });

          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final safeName =
              safeTitle.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
          videoPath =
              '$coursewareDir/${safeName}_$timestamp.mp4';

          await _videoService.generateVideo(
            slides: slideImages,
            audios: audioPaths,
            outputPath: videoPath,
            onProgress: (current, total, msg) {
              if (!mounted) return;
              setState(() {
                _mdProgress = 0.75 + 0.25 * (current / total);
                _mdProgressMsg = '(5/5) $msg';
              });
            },
          );

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
  List<Map<String, String>> _buildNarrationTexts(String courseTitle) {
    final scripts = <Map<String, String>>[];

    // 封面旁白
    scripts.add({
      'slide': '封面',
      'narration': '同学们好！欢迎来到今天的课程。本节课我们将一起学习${courseTitle}的相关内容。'
          '请大家做好笔记，跟随课程节奏，我们开始今天的学习。',
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

      // 开场过渡语
      if (i == 0) {
        buf.write('首先，我们来了解$title。');
      } else if (i == _parsedSlides.length - 1) {
        buf.write('最后，我们来看$title。');
      } else {
        final transitions = ['接下来', '下面', '现在', '然后'];
        buf.write('${transitions[i % transitions.length]}，我们来学习$title。');
      }

      if (subtitle.isNotEmpty) {
        buf.write('副标题是$subtitle。');
      }

      // 提取非表格、非标签的要点
      final mainPoints = <String>[];
      final subSections = <String>[];
      for (final b in bullets) {
        final text = b.toString();
        if (text.startsWith('|')) continue; // 跳过表格行
        if (text.startsWith('【') && text.endsWith('】')) {
          subSections.add(text.replaceAll('【', '').replaceAll('】', ''));
          continue;
        }
        // 清理前缀
        final cleaned = text
            .replaceAll(RegExp(r'^  · '), '')
            .replaceAll(RegExp(r'^\d+\.\s*'), '')
            .replaceAll(RegExp(r'^• '), '');
        if (cleaned.length > 2) {
          mainPoints.add(cleaned);
        }
      }

      // 展开子章节
      if (subSections.isNotEmpty) {
        buf.write('本部分主要涵盖${subSections.join("、")}等方面的内容。');
      }

      // 展开要点（取前5个）
      final pointsToNarrate = mainPoints.take(5).toList();
      if (pointsToNarrate.isNotEmpty) {
        buf.write('具体来说，');
        for (var j = 0; j < pointsToNarrate.length; j++) {
          final point = pointsToNarrate[j];
          if (j == 0) {
            buf.write('首先是$point');
          } else if (j == pointsToNarrate.length - 1) {
            buf.write('，最后是$point');
          } else {
            buf.write('，其次是$point');
          }
        }
        buf.write('。');
      }

      // 如果有代码示例，加一句说明
      if (code.isNotEmpty) {
        buf.write('在这张幻灯片中，我们可以看到具体的代码示例，请大家仔细阅读并理解代码的逻辑。');
      }

      // 如果有表格数据，加说明
      final hasTable = bullets.any((b) => b.toString().startsWith('|'));
      if (hasTable) {
        buf.write('请注意看屏幕上的对比表格，它直观地展示了各技术方案的差异。');
      }

      // 补充备注内容
      if (notes.isNotEmpty && notes.length > 5) {
        buf.write(notes);
      }

      // 如果旁白太短，追加通用过渡
      if (buf.length < 60) {
        buf.write('请大家认真理解这部分内容，这是本节课的重要知识点。');
      }

      scripts.add({
        'slide': title,
        'narration': buf.toString(),
      });
    }

    // 结束旁白
    scripts.add({
      'slide': '结束',
      'narration': '好的，今天的课程内容就讲到这里。我们回顾一下本节课的重点内容。'
          '希望同学们课后能够认真复习，并完成相关的练习。'
          '如果有任何疑问，可以在课后讨论或答疑时间提出。谢谢大家，下节课再见！',
    });

    return scripts;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI 生成流程 (原 Stepper 模式)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAiFlow() {
    return Stepper(
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
                ElevatedButton.icon(
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
            initialValue: _selectedChapter,
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

          // 教案预览
          if (_lessonPlan != null) ...[
            const SizedBox(height: 16),
            _buildLessonPlanPreview(),
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
            // PPTX 导出
            ListTile(
              leading: Icon(Icons.slideshow,
                  color: _pptxPath != null
                      ? Colors.green
                      : (_hasPythonPptx
                          ? Colors.deepOrange
                          : Colors.grey)),
              title: const Text('PPTX 课件（专业幻灯片）'),
              subtitle: _pptxPath != null
                  ? Text(_pptxPath!,
                      style: const TextStyle(fontSize: 11))
                  : Text(_hasPythonPptx
                      ? '使用 python-pptx 生成专业 PPT 课件'
                      : '需安装: pip install python-pptx'),
              trailing: _pptxPath != null
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => OpenFilex.open(_pptxPath!),
                    )
                  : null,
            ),
            if (!_hasPythonPptx)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _buildEnvCheck('python-pptx', false,
                    '运行: pip install python-pptx'),
              ),
            const Divider(),

            // PDF 导出
            ListTile(
              leading: Icon(Icons.picture_as_pdf,
                  color: _pdfPath != null ? Colors.green : Colors.red),
              title: const Text('PDF 课件（含UML图）'),
              subtitle: _pdfPath != null
                  ? Text(_pdfPath!, style: const TextStyle(fontSize: 11))
                  : const Text('A4横版，包含封面/教学过程/UML图/实验'),
              trailing: _pdfPath != null
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => OpenFilex.open(_pdfPath!),
                    )
                  : null,
            ),
            const Divider(),

            // MD 导出
            ListTile(
              leading: Icon(Icons.article,
                  color: _mdPath != null ? Colors.green : Colors.blue),
              title: const Text('Markdown 文档'),
              subtitle: _mdPath != null
                  ? Text(_mdPath!, style: const TextStyle(fontSize: 11))
                  : const Text('完整教案的 Markdown 格式'),
              trailing: _mdPath != null
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => OpenFilex.open(_mdPath!),
                    )
                  : null,
            ),
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
            initialValue: _ttsVoice,
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

          if (_pdfPath == null)
            const Text('⚠️ 请先导出 PDF 课件',
                style: TextStyle(color: Colors.orange)),

          if (_audioPaths.isEmpty)
            const Text('⚠️ 建议先生成语音',
                style: TextStyle(color: Colors.orange)),

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
        ],
      ),
    );
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
        return _pdfPath != null;
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
        return _hasFfmpeg && _pdfPath != null ? _doGenerateVideo : null;
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
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ 教案生成成功'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _generatingPlan = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('教案生成失败: $e')),
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
          // 从 Markdown 解析幻灯片
          final slides =
              _coursewareService.parseMarkdownToSlides(_markdownContent!);
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
    if (_pdfPath == null || !_hasFfmpeg) return;

    setState(() {
      _generatingVideo = true;
      _videoProgress = 0;
      _videoStatus = '正在将 PDF 转为图片...';
    });

    try {
      // 1. PDF → 图片
      final coursewareDir = await _coursewareService.getCoursewareDir();
      final slidesDir = '$coursewareDir/slides';
      final slideImages = await _videoService.pdfToImages(
        pdfPath: _pdfPath!,
        outputDir: slidesDir,
      );

      if (slideImages.isEmpty) {
        setState(() {
          _generatingVideo = false;
          _videoStatus = 'PDF 转图片失败（请安装 PyMuPDF: pip install PyMuPDF）';
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
