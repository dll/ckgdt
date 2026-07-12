import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/models/skill_def_model.dart';
import '../../../services/skill_registry.dart';
import '../../../services/skill_export_service.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/error_handler.dart';
import '../../widgets/back_button_bar.dart';
import 'ai_skill_page.dart';

class SkillManagePage extends StatefulWidget {
  const SkillManagePage({super.key});

  @override
  State<SkillManagePage> createState() => _SkillManagePageState();
}

class _SkillManagePageState extends State<SkillManagePage> {
  final _registry = SkillRegistry.instance;
  final _exportService = SkillExportService();
  String _searchQuery = '';
  bool _importing = false;

  List<SkillDef> get _skills {
    final all = _registry.getAll();
    if (_searchQuery.trim().isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.id.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.keywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildQuickActions(),
          Expanded(
            child: _skills.isEmpty
                ? _buildEmptyState()
                : _buildSkillGrid(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importSkill,
        icon: const Icon(Icons.file_download_outlined),
        label: const Text('导入技能'),
        backgroundColor: const Color(0xFF667eea),
        foregroundColor: Colors.white,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF667eea),
      foregroundColor: Colors.white,
      elevation: 0,
      title: Text('技能管理（${_registry.count}）'),
      actions: [
        IconButton(
          icon: const Icon(Icons.upload_file_outlined),
          tooltip: '导出全部',
          onPressed: _exportAll,
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: '分享全部',
          onPressed: _shareAll,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
          onPressed: () => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索技能名称、关键词…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _actionChip(Icons.upload_file, '导出全部', _exportAll),
            const SizedBox(width: 8),
            _actionChip(Icons.file_download, '导入文件', _importSkill),
            const SizedBox(width: 8),
            _actionChip(Icons.content_paste, '从剪贴板导入', _importFromClipboard),
            const SizedBox(width: 8),
            _actionChip(Icons.open_in_new, '打开导出目录', _openExportDir),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      onPressed: onTap,
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.grey.shade200),
    );
  }

  Widget _buildSkillGrid() {
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _skills.length,
        itemBuilder: (_, i) => _SkillManageCard(
          skill: _skills[i],
          onTap: () => _openSkillDetail(_skills[i]),
          onExport: () => _exportSingle(_skills[i].id),
          onDelete: () => _deleteSkill(_skills[i].id),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tips_and_updates_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? '未找到匹配技能' : '暂无技能',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角"导入技能"添加外部技能',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  void _openSkillDetail(SkillDef skill) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _SkillDetailPage(skill: skill)),
    );
  }

  Future<void> _exportAll() async {
    final result = await _exportService.exportAllToDesktop();
    _showSnack(result.message);
    if (result.success && result.filePath != null) {
      _showOpenDirPrompt();
    }
  }

  Future<void> _exportSingle(String id) async {
    final result = await _exportService.exportForReuse(id);
    _showSnack(result.message);
  }

  Future<void> _importSkill() async {
    setState(() => _importing = true);
    final count = await _exportService.importFromFile();
    setState(() => _importing = false);
    if (count > 0) {
      _showSnack('成功导入 $count 个技能');
      setState(() {});
    } else {
      _showSnack('未导入新技能（可能文件格式不符或技能已存在）');
    }
  }

  Future<void> _importFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.trim().isEmpty) {
        _showSnack('剪贴板为空');
        return;
      }
      final result = await _exportService.importFromClipboard(text);
      if (result.success) {
        setState(() {});
      }
      _showSnack(result.message);
    } catch (e, st) {
      swallowDebug(e, tag: 'SkillManage.importClipboard', stack: st);
      _showSnack('导入失败: $e');
    }
  }

  Future<void> _shareAll() async {
    final result = await _exportService.exportAllToClipboard();
    _showSnack(result.message);
  }

  void _deleteSkill(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除技能'),
        content: Text('确定删除技能"${_registry.get(id)?.name ?? id}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              _registry.remove(id);
              Navigator.pop(ctx);
              setState(() {});
              _showSnack('已删除');
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _openExportDir() async {
    try {
      final dir = await SkillExportService.defaultExportDirectory();
      if (kIsWeb) return;
      if (Platform.isWindows) {
        await Process.run('explorer', [dir.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'SkillManage.openDir', stack: st);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 14)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  void _showOpenDirPrompt() {
    _showSnack('已导出到 skill_exports 目录');
  }
}

class _SkillManageCard extends StatelessWidget {
  final SkillDef skill;
  final VoidCallback onTap;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _SkillManageCard({
    required this.skill,
    required this.onTap,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildIcon(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(skill.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'export') onExport();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'export', child: Text('导出')),
                      const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(skill.subtitle.isNotEmpty ? skill.subtitle : skill.description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.touch_app, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('${skill.usageSteps.length} 步',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                  const Spacer(),
                  Text('优先级 ${skill.priority}',
                      style: TextStyle(color: Colors.grey.shade300, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: skill.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(skill.icon, color: skill.color, size: 20),
    );
  }
}

class _SkillDetailPage extends StatelessWidget {
  final SkillDef skill;
  const _SkillDetailPage({required this.skill});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: skill.color,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(skill.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '打开技能页',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AiSkillPage(skillId: skill.id)),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildDescription(),
            const SizedBox(height: 20),
            _buildUsageSteps(),
            const SizedBox(height: 20),
            _buildKeywords(),
            const SizedBox(height: 20),
            _buildClassicCases(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          skill.color.withValues(alpha: 0.8),
          skill.color,
        ]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(skill.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.name,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(skill.subtitle,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 20, color: Color(0xFF667eea)),
                const SizedBox(width: 8),
                const Text('技能说明', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Text(skill.description, style: const TextStyle(fontSize: 14, height: 1.6)),
            if (skill.features.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text('核心功能', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...skill.features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: Color(0xFF667eea))),
                        Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUsageSteps() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.format_list_numbered, size: 20, color: Color(0xFF667eea)),
                const SizedBox(width: 8),
                const Text('使用步骤', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            ...skill.usageSteps.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF667eea),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text('${e.key + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(e.value, style: const TextStyle(fontSize: 14, height: 1.5)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildKeywords() {
    if (skill.keywords.isEmpty && skill.examples.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.label_outline, size: 20, color: Color(0xFF667eea)),
                SizedBox(width: 8),
                Text('触发关键词 & 示例', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...skill.keywords.map((k) => Chip(
                      label: Text(k, style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFF667eea).withValues(alpha: 0.1),
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )),
                ...skill.examples.map((e) => Chip(
                      label: Text(e, style: const TextStyle(fontSize: 12)),
                      backgroundColor: Colors.deepPurple.withValues(alpha: 0.08),
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassicCases() {
    if (skill.classicCases.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bookmark_outline, size: 20, color: Color(0xFF667eea)),
                SizedBox(width: 8),
                Text('经典案例', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            ...skill.classicCases.map((c) => Card(
                  color: Colors.grey.shade50,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text('输入: ${c.userInput}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('结果: ${c.resultSummary}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
