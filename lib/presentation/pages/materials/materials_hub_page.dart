import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/puml_dao.dart';
import '../../../data/models/material_model.dart';
import '../../../data/models/puml_file_model.dart';
import '../../../services/file_opener_service.dart';
import '../../../services/material_service.dart';
import 'ai_assist_page.dart';
import 'ai_settings_page.dart';
import 'puml_manager_page.dart';
import 'slide_generator_page.dart';

class MaterialsHubPage extends StatefulWidget {
  const MaterialsHubPage({super.key});

  @override
  State<MaterialsHubPage> createState() => _MaterialsHubPageState();
}

class _MaterialsHubPageState extends State<MaterialsHubPage> {
  // Tab 0 — 课程资料
  List<Map<String, dynamic>> _pdfFiles = [];
  List<Map<String, dynamic>> _pptFiles = [];
  bool _resourceLoading = true;

  // Tab 2 — UML图谱
  List<PumlFileModel> _pumlFiles = [];
  bool _pumlLoading = true;

  // Tab 3 — 素材库
  List<MaterialModel> _materials = [];
  bool _materialLoading = true;

  final PumlDao _pumlDao = PumlDao();
  final MaterialService _materialService = MaterialService();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadResourceFiles(),
      _loadPumlFiles(),
      _loadMaterials(),
    ]);
  }

  // ── 数据加载 ─────────────────────────────────────────────────────────────

  Future<void> _loadResourceFiles() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final pdfs = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['pdf'],
      );
      final ppts = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['ppt'],
      );
      if (!mounted) return;
      setState(() {
        _pdfFiles = pdfs;
        _pptFiles = ppts;
        _resourceLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _resourceLoading = false);
    }
  }

  Future<void> _loadPumlFiles() async {
    try {
      await _pumlDao.initSamples();
      final files = await _pumlDao.getAll();
      if (!mounted) return;
      setState(() {
        _pumlFiles = files;
        _pumlLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pumlLoading = false);
    }
  }

  Future<void> _loadMaterials() async {
    try {
      final items = await _materialService.getAll();
      if (!mounted) return;
      setState(() {
        _materials = items;
        _materialLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _materialLoading = false);
    }
  }

  // ── 删除操作 ─────────────────────────────────────────────────────────────

  Future<void> _deletePuml(PumlFileModel item) async {
    final ok = await _showConfirmDialog('删除确认', '确定要删除"${item.title}"吗？');
    if (!ok || !mounted) return;
    await _pumlDao.delete(item.id!);
    if (!mounted) return;
    _loadPumlFiles();
  }

  Future<void> _deleteMaterial(MaterialModel item) async {
    final ok =
        await _showConfirmDialog('删除确认', '确定要删除"${item.title}"吗？此操作不可恢复。');
    if (!ok || !mounted) return;
    await _materialService.delete(item);
    if (!mounted) return;
    _loadMaterials();
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showContentDialog(MaterialModel item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.title),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              item.content ?? '',
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final gradient = AppGradientTheme.of(context).linearGradient;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('素材中心'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '配置 AI',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiSettingsPage()),
              ).then((_) => _loadAllData()),
            ),
          ],
          bottom: TabBar(
            indicatorColor: primary,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(icon: Icon(Icons.menu_book_outlined), text: '课程资料'),
              Tab(icon: Icon(Icons.auto_awesome_outlined), text: 'AI生成'),
              Tab(icon: Icon(Icons.account_tree_outlined), text: 'UML图谱'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: '素材库'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildResourceTab(primary),
            _buildAiTab(gradient),
            _buildPumlTab(primary),
            _buildMaterialsTab(primary),
          ],
        ),
      ),
    );
  }

  // ── Tab 0：课程资料 ──────────────────────────────────────────────────────

  Widget _buildResourceTab(Color primary) {
    if (_resourceLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorColor: primary,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'PDF (${_pdfFiles.length})'),
              Tab(text: 'PPT (${_pptFiles.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildFileList(_pdfFiles, '📄', 'PDF'),
                _buildFileList(_pptFiles, '🖼️', 'PPT'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(
    List<Map<String, dynamic>> files,
    String emoji,
    String type,
  ) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('暂无 $type 文件',
                style: const TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadResourceFiles,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: files.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final file = files[index];
          final name = file['file_name'] as String? ?? '未命名';
          final path = file['file_path'] as String? ?? '';
          final chapter = file['chapter'] as String?;
          final desc = file['description'] as String?;
          return ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              [if (chapter != null) chapter, if (desc != null) desc].join('  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              if (path.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('文件路径未设置')),
                );
                return;
              }
              FileOpenerService.openFile(context, path, name);
            },
          );
        },
      ),
    );
  }

  // ── Tab 1：AI生成 ────────────────────────────────────────────────────────

  Widget _buildAiTab(LinearGradient gradient) {
    final features = <_AiFeature>[
      _AiFeature(
        icon: Icons.slideshow_outlined,
        title: '生成课件',
        desc: '自动生成 PDF 幻灯片',
        color: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SlideGeneratorPage()),
        ).then((_) => _loadMaterials()),
      ),
      _AiFeature(
        icon: Icons.article_outlined,
        title: '生成脚本',
        desc: 'AI 生成视频讲解脚本',
        color: Colors.green,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiAssistPage(mode: 'script')),
        ).then((_) => _loadMaterials()),
      ),
      _AiFeature(
        icon: Icons.account_tree_outlined,
        title: '生成UML',
        desc: 'AI 生成 PlantUML 代码',
        color: Colors.purple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiAssistPage(mode: 'uml')),
        ).then((_) => _loadPumlFiles()),
      ),
      _AiFeature(
        icon: Icons.smart_toy_outlined,
        title: 'AI问答',
        desc: '自由对话、生成题目等',
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiAssistPage(mode: 'chat')),
        ),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 欢迎横幅
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✨ AI 智能创作',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '利用 AI 快速生成教学材料，提升备课效率',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '选择功能',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: features.map(_buildFeatureCard).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(_AiFeature f) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: f.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: f.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(f.icon, color: f.color, size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                f.title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                f.desc,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 2：UML图谱 ───────────────────────────────────────────────────────

  Widget _buildPumlTab(Color primary) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _pumlLoading
          ? const Center(child: CircularProgressIndicator())
          : _pumlFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔷', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      const Text(
                        '暂无 UML 图，点击右下角新建',
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('新建 UML'),
                        onPressed: () => _openPumlEditor(null),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPumlFiles,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
                    itemCount: _pumlFiles.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) =>
                        _buildPumlTile(_pumlFiles[index], primary),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        tooltip: '新建 UML',
        onPressed: () => _openPumlEditor(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPumlTile(PumlFileModel item, Color primary) {
    final dateStr = item.updatedAt != null
        ? _formatDate(item.updatedAt!)
        : (item.createdAt != null ? _formatDate(item.createdAt!) : '');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text('🔷', style: TextStyle(fontSize: 22)),
        ),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Wrap(
        spacing: 6,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(item.typeLabel,
                style: TextStyle(fontSize: 11, color: primary)),
          ),
          if (item.chapter != null)
            Text(item.chapter!, style: const TextStyle(fontSize: 12)),
          if (dateStr.isNotEmpty)
            Text(dateStr,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: primary),
            tooltip: '编辑',
            onPressed: () => _openPumlEditor(item),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: '删除',
            onPressed: () => _deletePuml(item),
          ),
        ],
      ),
      onTap: () => _openPumlEditor(item),
    );
  }

  void _openPumlEditor(PumlFileModel? item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PumlManagerPage(pumlFile: item)),
    ).then((_) => _loadPumlFiles());
  }

  // ── Tab 3：素材库 ────────────────────────────────────────────────────────

  Widget _buildMaterialsTab(Color primary) {
    if (_materialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        // 统计头部
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: primary.withValues(alpha: 0.07),
          child: Text(
            '共 ${_materials.length} 个素材  •  长按可删除',
            style: TextStyle(color: primary, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: _materials.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('📦', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text(
                        '暂无素材，先去「AI生成」Tab 创建',
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMaterials,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _materials.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) =>
                        _buildMaterialTile(_materials[index], primary),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMaterialTile(MaterialModel item, Color primary) {
    final icon = MaterialService.typeIcon(item.type);
    final dateStr = item.createdAt != null ? _formatDate(item.createdAt!) : '';
    final sizeStr = item.size > 0 ? MaterialService.formatSize(item.size) : '';
    final hasContent = item.content != null && item.content!.isNotEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(icon, style: const TextStyle(fontSize: 22)),
        ),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Wrap(
        spacing: 6,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(item.typeLabel,
                style: TextStyle(fontSize: 11, color: primary)),
          ),
          if (item.chapter != null)
            Text(item.chapter!, style: const TextStyle(fontSize: 12)),
          if (dateStr.isNotEmpty)
            Text(dateStr,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (sizeStr.isNotEmpty)
            Text(sizeStr,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
      trailing: hasContent
          ? const Icon(Icons.open_in_new, size: 18, color: Colors.grey)
          : null,
      onTap: hasContent ? () => _showContentDialog(item) : null,
      onLongPress: () => _deleteMaterial(item),
    );
  }

  // ── 工具 ─────────────────────────────────────────────────────────────────

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.month}/${dt.day} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}

// ── 辅助数据类 ────────────────────────────────────────────────────────────────

class _AiFeature {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  final VoidCallback onTap;

  const _AiFeature({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
    required this.onTap,
  });
}
