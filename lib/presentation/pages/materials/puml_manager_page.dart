import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_theme.dart';
import '../../../data/local/puml_dao.dart';
import '../../../data/models/puml_file_model.dart';
import '../../../services/plantuml_service.dart';

class PumlManagerPage extends StatefulWidget {
  final PumlFileModel? pumlFile;

  const PumlManagerPage({super.key, this.pumlFile});

  @override
  State<PumlManagerPage> createState() => _PumlManagerPageState();
}

class _PumlManagerPageState extends State<PumlManagerPage>
    with SingleTickerProviderStateMixin {
  static const _chapters = [
    '第1章', '第2章', '第3章', '第4章', '第5章', '第6章',
  ];

  static const _diagramTypes = [
    'class', 'sequence', 'activity', 'component', 'usecase',
  ];

  static const _diagramTypeLabels = {
    'class': '类图',
    'sequence': '时序图',
    'activity': '活动图',
    'component': '组件图',
    'usecase': '用例图',
  };

  // ── 内置模板 ──────────────────────────────────────────────────────────────

  static const _classTemplate = '''@startuml
title 类图示例
skinparam backgroundColor #FFFFFF

class 动物 {
  +名称: String
  +年龄: int
  +叫声(): void
}

class 狗 extends 动物 {
  +品种: String
  +摇尾巴(): void
}

class 猫 extends 动物 {
  +毛色: String
  +挠人(): void
}

动物 <|-- 狗
动物 <|-- 猫
@enduml''';

  static const _sequenceTemplate = '''@startuml
title 时序图示例
actor 用户
participant "客户端" as Client
participant "服务器" as Server
database "数据库" as DB

用户 -> Client : 发起请求
Client -> Server : HTTP GET /api/data
Server -> DB : SELECT * FROM table
DB --> Server : 返回数据集
Server --> Client : JSON 响应
Client --> 用户 : 展示结果
@enduml''';

  static const _activityTemplate = '''@startuml
title 活动图示例
start
:用户登录;
if (验证通过?) then (是)
  :进入主界面;
  :加载数据;
  if (数据加载成功?) then (是)
    :展示内容;
  else (否)
    :显示错误提示;
  endif
else (否)
  :提示账号或密码错误;
  :返回登录页;
endif
stop
@enduml''';

  // ── 控制器 & 状态 ─────────────────────────────────────────────────────────

  late final TabController _tabController;
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _codeFocusNode = FocusNode();

  String _selectedChapter = '第1章';
  String _selectedDiagramType = 'class';
  String? _renderedUrl;
  bool _rendering = false;
  bool _saving = false;

  final PumlDao _pumlDao = PumlDao();
  final PlantUmlService _pumlService = PlantUmlService();

  bool get _isNew => widget.pumlFile == null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 加载现有数据或初始化新建默认值
    if (widget.pumlFile != null) {
      final f = widget.pumlFile!;
      _titleController.text = f.title;
      _codeController.text = f.content;
      _selectedChapter = f.chapter ?? '第1章';
      _selectedDiagramType = f.diagramType;
      _renderedUrl = f.renderedUrl;
    } else {
      _titleController.text = '新建 UML 图';
      _codeController.text = _classTemplate;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _titleController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  // ── 渲染 ──────────────────────────────────────────────────────────────────

  Future<void> _render() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showSnack('请先输入 PUML 代码');
      return;
    }
    setState(() {
      _rendering = true;
      _renderedUrl = null;
    });
    try {
      final url = _pumlService.getKrokiUrl(code);
      if (!mounted) return;
      setState(() {
        _renderedUrl = url;
        _rendering = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _rendering = false);
      _showSnack('渲染失败：$e');
    }
  }

  // ── 保存 ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final code = _codeController.text.trim();

    if (title.isEmpty) {
      _showSnack('请输入标题');
      _tabController.animateTo(1); // 切到属性 Tab
      return;
    }
    if (code.isEmpty) {
      _showSnack('代码内容不能为空');
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      if (_isNew) {
        final newFile = PumlFileModel(
          title: title,
          content: code,
          renderedUrl: _renderedUrl,
          diagramType: _selectedDiagramType,
          chapter: _selectedChapter,
          createdAt: now,
          updatedAt: now,
        );
        await _pumlDao.insert(newFile);
      } else {
        final updated = widget.pumlFile!.copyWith(
          title: title,
          content: code,
          renderedUrl: _renderedUrl,
          diagramType: _selectedDiagramType,
          chapter: _selectedChapter,
        );
        await _pumlDao.update(updated);
      }
      if (!mounted) return;
      _showSnack('✅ 保存成功', success: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── 复制代码 ──────────────────────────────────────────────────────────────

  Future<void> _copyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showSnack('代码为空，无法复制');
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _showSnack('✅ 代码已复制到剪贴板', success: true);
  }

  // ── 插入模板 ──────────────────────────────────────────────────────────────

  void _insertTemplate(String template) {
    _codeController.text = template;
    _codeController.selection = TextSelection.collapsed(
      offset: _codeController.text.length,
    );
    _tabController.animateTo(0);
    _showSnack('已插入模板', success: true);
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          success ? Colors.green.shade600 : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = kToolbarHeight +
        MediaQuery.of(context).padding.top +
        kTextTabBarHeight;
    final bodyHeight = screenHeight - appBarHeight;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建 UML 图' : '编辑 UML 图'),
        actions: [
          // 渲染按钮
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: '渲染预览',
            onPressed: _rendering ? null : _render,
          ),
          // 复制代码
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: '复制代码',
            onPressed: _copyCode,
          ),
          // 保存按钮
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            tooltip: '保存',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 上半区：渲染结果（40%）────────────────────────────────────────
          SizedBox(
            height: bodyHeight * 0.40,
            child: _buildRenderArea(primary),
          ),

          // ── 分隔线 ─────────────────────────────────────────────────────────
          Container(
            height: 1,
            color: Colors.grey.shade200,
          ),

          // ── 下半区：编辑（60%）────────────────────────────────────────────
          Expanded(
            child: _buildEditArea(primary),
          ),
        ],
      ),
    );
  }

  // ── 渲染结果区域 ──────────────────────────────────────────────────────────

  Widget _buildRenderArea(Color primary) {
    if (_rendering) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primary),
            const SizedBox(height: 12),
            const Text('渲染中…', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_renderedUrl == null || _renderedUrl!.isEmpty) {
      return GestureDetector(
        onTap: _render,
        child: Container(
          color: Colors.grey.shade50,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_outline,
                    size: 48, color: primary.withOpacity(0.5)),
                const SizedBox(height: 10),
                Text(
                  '点击右上角 ▶ 按钮渲染预览',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  '或点击此处快速渲染',
                  style: TextStyle(
                    color: primary.withOpacity(0.7),
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: primary.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 显示渲染结果
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: _renderedUrl!,
                fit: BoxFit.contain,
                placeholder: (_, __) => Center(
                  child: CircularProgressIndicator(color: primary),
                ),
                errorWidget: (_, __, ___) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined,
                          size: 40, color: Colors.redAccent),
                      const SizedBox(height: 8),
                      const Text('图片加载失败',
                          style: TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                        onPressed: _render,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 右下角重新渲染按钮
          Positioned(
            right: 8,
            bottom: 8,
            child: FloatingActionButton.small(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              tooltip: '重新渲染',
              onPressed: _render,
              child: const Icon(Icons.refresh, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── 编辑区域 ──────────────────────────────────────────────────────────────

  Widget _buildEditArea(Color primary) {
    return Column(
      children: [
        // Tab 标题栏
        TabBar(
          controller: _tabController,
          indicatorColor: primary,
          labelColor: primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.code, size: 18), text: '代码'),
            Tab(icon: Icon(Icons.tune, size: 18), text: '属性'),
          ],
        ),
        // Tab 内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCodeTab(primary),
              _buildPropertiesTab(primary),
            ],
          ),
        ),
      ],
    );
  }

  // ── 代码 Tab ──────────────────────────────────────────────────────────────

  Widget _buildCodeTab(Color primary) {
    return Column(
      children: [
        // 模板快捷按钮工具栏
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Row(
            children: [
              const Text(
                '模板：',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(width: 4),
              _templateChip('类图', _classTemplate, primary),
              const SizedBox(width: 6),
              _templateChip('时序图', _sequenceTemplate, primary),
              const SizedBox(width: 6),
              _templateChip('活动图', _activityTemplate, primary),
              const Spacer(),
              // 清空按钮
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('清空', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('确认清空'),
                      content: const Text('确定要清空所有代码吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () {
                            _codeController.clear();
                            Navigator.pop(ctx);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        // 代码编辑器
        Expanded(
          child: Container(
            color: const Color(0xFFF8F9FA),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 行号区域
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _codeController,
                  builder: (_, value, __) {
                    final lineCount =
                        '\n'.allMatches(value.text).length + 1;
                    return Container(
                      width: 36,
                      padding: const EdgeInsets.only(top: 12),
                      color: const Color(0xFFEEEFF1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(
                          lineCount,
                          (i) => SizedBox(
                            height: 21,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                                fontFamily: 'monospace',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // 文本输入区
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    focusNode: _codeFocusNode,
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(8, 12, 8, 12),
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.6,
                    ),
                    keyboardType: TextInputType.multiline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _templateChip(String label, String template, Color primary) {
    return GestureDetector(
      onTap: () => _insertTemplate(template),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              color: primary,
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ── 属性 Tab ──────────────────────────────────────────────────────────────

  Widget _buildPropertiesTab(Color primary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          _sectionLabel('标题'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: '输入图的标题',
              prefixIcon: const Icon(Icons.title),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),

          // 章节
          _sectionLabel('所属章节'),
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
                    .map((c) =>
                        DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedChapter = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 图类型
          _sectionLabel('图类型'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDiagramType,
                isExpanded: true,
                items: _diagramTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(
                              _diagramTypeLabels[t] ?? t),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedDiagramType = v);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 渲染 URL 信息（只读）
          if (_renderedUrl != null && _renderedUrl!.isNotEmpty) ...[
            _sectionLabel('渲染地址'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.05),
                border: Border.all(color: primary.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _renderedUrl!,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: '复制 URL',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _renderedUrl!));
                      _showSnack('URL 已复制', success: true);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('渲染预览'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    side: BorderSide(color: primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _rendering ? null : _render,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
          fontWeight: FontWeight.w600, fontSize: 14),
    );
  }
}
