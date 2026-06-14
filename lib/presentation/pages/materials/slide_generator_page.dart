import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../data/local/ai_config_dao.dart';
import '../../../services/ai_service.dart';
import '../../../services/course_context_service.dart';
import '../../../services/slide_generator_service.dart';
import '../../../data/models/material_model.dart';
import 'ai_settings_page.dart';

class SlideGeneratorPage extends StatefulWidget {
  const SlideGeneratorPage({super.key});

  @override
  State<SlideGeneratorPage> createState() => _SlideGeneratorPageState();
}

class _SlideGeneratorPageState extends State<SlideGeneratorPage> {
  final _topicController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _selectedChapter = '全部/自定义';
  List<String> _chapters = const ['全部/自定义'];
  double _slideCount = 8;
  bool _generating = false;
  bool _hasApiKey = false;
  bool _checkingKey = true;

  final AiConfigDao _configDao = AiConfigDao();
  final CourseContextService _courseContext = CourseContextService();
  final SlideGeneratorService _slideService = SlideGeneratorService();

  @override
  void initState() {
    super.initState();
    _loadCourseChapters();
    _checkApiKey();
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _checkApiKey() async {
    final has = await _configDao.hasApiKey();
    if (!mounted) return;
    setState(() {
      _hasApiKey = has;
      _checkingKey = false;
    });
  }

  Future<void> _loadCourseChapters() async {
    final chapters = await _courseContext.chapterTitles(includeAll: true);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      if (!_chapters.contains(_selectedChapter)) {
        _selectedChapter = _chapters.first;
      }
    });
  }

  Future<void> _generate() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final topic = _topicController.text.trim();
    final chapter = _selectedChapter == '全部/自定义' ? null : _selectedChapter;

    setState(() => _generating = true);

    try {
      final result = await _slideService.generateFromAI(
        aiService: AiService(),
        topic: topic,
        chapter: chapter,
        slideCount: _slideCount.round(),
      );
      if (!mounted) return;
      if (result != null) {
        _showSuccessDialog(result);
      } else {
        _showError('生成失败，请检查 AI 服务配置后重试');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showSuccessDialog(MaterialModel material) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('课件生成成功'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('标题', material.title),
            const SizedBox(height: 8),
            if (material.chapter != null) _infoRow('章节', material.chapter!),
            if (material.chapter != null) const SizedBox(height: 8),
            if (material.filePath != null)
              _infoRow('路径', material.filePath!, wrap: true),
            if (material.filePath != null) const SizedBox(height: 8),
            if (material.size > 0)
              _infoRow(
                  '大小', '约 ${(material.size / 1024).toStringAsFixed(1)} KB'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('文件位置：${material.filePath ?? '未知'}'),
                  duration: const Duration(seconds: 5),
                ),
              );
            },
            child: const Text('查看路径'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool wrap = false}) {
    return Row(
      crossAxisAlignment:
          wrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          '$label：',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        wrap
            ? Expanded(
                child: Text(value,
                    style: const TextStyle(fontSize: 12), softWrap: true))
            : Expanded(
                child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── 预览模板 ─────────────────────────────────────────────────────────────

  List<String> _previewSlides() {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) return [];
    final count = _slideCount.round();
    final chapter = _selectedChapter == '全部/自定义' ? '' : ' · $_selectedChapter';
    return [
      '封面：$topic$chapter',
      '目录：课程内容概览',
      '背景：$topic 简介',
      '核心：关键概念一',
      if (count > 4) '核心：关键概念二',
      if (count > 5) '技术细节与代码示例',
      if (count > 6) '实践案例分析',
      if (count > 7) '常见问题与解答',
      if (count > 8) '扩展阅读与资源',
      if (count > 9) '小结与要点回顾',
      '总结：课程总结',
    ].take(count).toList();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final gradient = AppGradientTheme.of(context).linearGradient;

    return Scaffold(
      appBar: AppBar(title: const Text('生成课件')),
      body: _checkingKey
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 顶部渐变卡片
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.slideshow_outlined,
                              color: Colors.white, size: 22),
                          SizedBox(width: 8),
                          Text('AI 课件生成',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ]),
                        SizedBox(height: 6),
                        Text('输入主题，AI 自动生成结构完整的教学 PDF 幻灯片',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // API Key 警告
                  if (!_hasApiKey) ...[
                    _buildNoKeyWarning(),
                    const SizedBox(height: 16),
                  ],

                  // 章节选择
                  const Text('选择章节',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedChapter,
                        isExpanded: true,
                        items: _chapters
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedChapter = v);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 主题输入
                  const Text('课件主题',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _topicController,
                    decoration: InputDecoration(
                      hintText: '如：需求分析方法、结构化设计、核心概念辨析',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.topic_outlined),
                      suffixIcon: _topicController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _topicController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入课件主题' : null,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 20),

                  // 幻灯片数量
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('幻灯片数量',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_slideCount.round()} 张',
                          style: TextStyle(
                              color: primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _slideCount,
                    min: 4,
                    max: 16,
                    divisions: 12,
                    activeColor: primary,
                    label: '${_slideCount.round()} 张',
                    onChanged: (v) => setState(() => _slideCount = v),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('4 张',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                      Text('16 张',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 幻灯片预览
                  if (_previewSlides().isNotEmpty) ...[
                    _buildPreviewSection(primary),
                    const SizedBox(height: 20),
                  ],

                  // 生成进度
                  if (_generating) ...[
                    const Text('正在调用 AI 生成课件内容，请稍候…',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                        borderRadius: BorderRadius.circular(4), color: primary),
                    const SizedBox(height: 20),
                  ],

                  // 生成按钮
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      icon: _generating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        _generating ? '生成中，请稍候…' : '生成课件',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed:
                          (!_hasApiKey || _generating) ? null : _generate,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 提示
                  Text(
                    '提示：生成过程约需 10-30 秒，完成后 PDF 文件自动保存到素材库',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  // ── 无 API Key 警告卡片 ──────────────────────────────────────────────────

  Widget _buildNoKeyWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('尚未配置 AI API Key',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                SizedBox(height: 2),
                Text('需要先配置 API Key 才能使用 AI 生成功能',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiSettingsPage()),
            ).then((_) => _checkApiKey()),
            child: const Text('去配置'),
          ),
        ],
      ),
    );
  }

  // ── 预览模板区域 ─────────────────────────────────────────────────────────

  Widget _buildPreviewSection(Color primary) {
    final slides = _previewSlides();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.preview_outlined, size: 18, color: primary),
            const SizedBox(width: 6),
            const Text('预览结构',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            Text('${slides.length} 张幻灯片',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.04),
            border: Border.all(color: primary.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: slides.asMap().entries.map((entry) {
              final idx = entry.key;
              final title = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                              fontSize: 10,
                              color: primary,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
