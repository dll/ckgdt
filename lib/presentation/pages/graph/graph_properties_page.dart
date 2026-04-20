import 'package:flutter/material.dart';
import '../../../data/local/knowledge_graph_dao.dart';
import '../../../services/ai_service.dart';

/// Page for viewing and managing knowledge graph concepts & relations.
class GraphPropertiesPage extends StatefulWidget {
  const GraphPropertiesPage({super.key});

  @override
  State<GraphPropertiesPage> createState() => _GraphPropertiesPageState();
}

class _GraphPropertiesPageState extends State<GraphPropertiesPage>
    with TickerProviderStateMixin {
  static const _primaryColor = Color(0xFF667eea);

  static const _conceptTypes = [
    'concept',
    'technology',
    'tool',
    'framework',
    'language',
    'platform',
    'pattern',
  ];

  static const _importanceLevels = ['core', 'important', 'supplementary'];

  static const _relationTypes = [
    'prerequisite',
    'related_to',
    'part_of',
    'compared_with',
    'applied_in',
    'builds_upon',
    'alternative_to',
    'extends',
  ];

  static const _typeColors = <String, Color>{
    'concept': Colors.purple,
    'technology': Colors.blue,
    'tool': Colors.orange,
    'framework': Colors.green,
    'language': Colors.red,
    'platform': Colors.cyan,
    'pattern': Colors.brown,
  };

  static const _importanceColors = <String, Color>{
    'core': Color(0xFFE53935),
    'important': Color(0xFFFB8C00),
    'supplementary': Color(0xFF43A047),
  };

  static const _importanceLabels = <String, String>{
    'core': '核心',
    'important': '重要',
    'supplementary': '补充',
  };

  static const _typeLabels = <String, String>{
    'concept': '概念',
    'technology': '技术',
    'tool': '工具',
    'framework': '框架',
    'language': '语言',
    'platform': '平台',
    'pattern': '模式',
  };

  static const _relationLabels = <String, String>{
    'prerequisite': '前置知识',
    'related_to': '相关',
    'part_of': '属于',
    'compared_with': '对比',
    'applied_in': '应用于',
    'builds_upon': '基于',
    'alternative_to': '替代',
    'extends': '扩展',
  };

  final KnowledgeGraphDao _dao = KnowledgeGraphDao();
  late TabController _tabController;

  // ── Node state ──
  List<Map<String, dynamic>> _allConcepts = [];
  List<Map<String, dynamic>> _filteredConcepts = [];
  final TextEditingController _nodeSearchController = TextEditingController();
  String _nodeSortField = 'concept_name';

  // ── Edge state ──
  List<Map<String, dynamic>> _allRelations = [];
  List<Map<String, dynamic>> _filteredRelations = [];
  final TextEditingController _edgeSearchController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nodeSearchController.dispose();
    _edgeSearchController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final concepts = await _dao.getAllConcepts();
      final relations = await _dao.getAllRelations();
      setState(() {
        _allConcepts = concepts;
        _allRelations = relations;
        _applyNodeFilter();
        _applyEdgeFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载数据失败: $e')),
        );
      }
    }
  }

  // ── Filtering & sorting ───────────────────────────────────────────────────

  void _applyNodeFilter() {
    final query = _nodeSearchController.text.trim().toLowerCase();
    var list = _allConcepts.where((c) {
      if (query.isEmpty) return true;
      final name = (c['concept_name'] as String? ?? '').toLowerCase();
      final keywords = (c['keywords'] as String? ?? '').toLowerCase();
      final type = (c['concept_type'] as String? ?? '').toLowerCase();
      return name.contains(query) ||
          keywords.contains(query) ||
          type.contains(query);
    }).toList();

    list.sort((a, b) {
      switch (_nodeSortField) {
        case 'chapter':
          return ((a['chapter'] as int?) ?? 0)
              .compareTo((b['chapter'] as int?) ?? 0);
        case 'concept_type':
          return (a['concept_type'] as String? ?? '')
              .compareTo(b['concept_type'] as String? ?? '');
        case 'concept_name':
        default:
          return (a['concept_name'] as String? ?? '')
              .compareTo(b['concept_name'] as String? ?? '');
      }
    });

    _filteredConcepts = list;
  }

  void _applyEdgeFilter() {
    final query = _edgeSearchController.text.trim().toLowerCase();
    _filteredRelations = _allRelations.where((r) {
      if (query.isEmpty) return true;
      final srcName = _conceptNameById(r['source_concept_id'] as int? ?? 0)
          .toLowerCase();
      final tgtName = _conceptNameById(r['target_concept_id'] as int? ?? 0)
          .toLowerCase();
      final relType = (r['relation_type'] as String? ?? '').toLowerCase();
      return srcName.contains(query) ||
          tgtName.contains(query) ||
          relType.contains(query);
    }).toList();
  }

  String _conceptNameById(int id) {
    for (final c in _allConcepts) {
      if (c['id'] == id) return c['concept_name'] as String? ?? '未知';
    }
    return '未知(#$id)';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图谱属性管理'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.bubble_chart), text: '节点列表'),
            Tab(icon: Icon(Icons.timeline), text: '关系列表'),
          ],
        ),
        actions: [
          // AI 推荐按钮
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent),
            tooltip: 'AI 智能推荐',
            onPressed: _showAiRecommendDialog,
          ),
          // Sort dropdown only visible on nodes tab
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              if (_tabController.index != 0) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                icon: const Icon(Icons.sort, color: Colors.white),
                tooltip: '排序方式',
                onSelected: (value) {
                  setState(() {
                    _nodeSortField = value;
                    _applyNodeFilter();
                  });
                },
                itemBuilder: (_) => [
                  _sortMenuItem('concept_name', '按名称'),
                  _sortMenuItem('chapter', '按章节'),
                  _sortMenuItem('concept_type', '按类型'),
                ],
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildNodesTab(),
                _buildEdgesTab(),
              ],
            ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          return FloatingActionButton(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            tooltip: _tabController.index == 0 ? '添加节点' : '添加关系',
            onPressed: () {
              if (_tabController.index == 0) {
                _showNodeDialog();
              } else {
                _showEdgeDialog();
              }
            },
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }

  PopupMenuEntry<String> _sortMenuItem(String value, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          if (_nodeSortField == value)
            const Icon(Icons.check, size: 18, color: _primaryColor)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  // ── Nodes tab ─────────────────────────────────────────────────────────────

  Widget _buildNodesTab() {
    return Column(
      children: [
        _buildSearchBar(
          controller: _nodeSearchController,
          hint: '搜索节点名称、关键词或类型…',
          onChanged: (_) => setState(() => _applyNodeFilter()),
        ),
        Expanded(
          child: _filteredConcepts.isEmpty
              ? _buildEmptyState('暂无节点', Icons.bubble_chart_outlined)
              : RefreshIndicator(
                  color: _primaryColor,
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                    itemCount: _filteredConcepts.length,
                    itemBuilder: (context, index) =>
                        _buildNodeCard(_filteredConcepts[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildNodeCard(Map<String, dynamic> concept) {
    final id = concept['id'] as int;
    final name = concept['concept_name'] as String? ?? '';
    final type = concept['concept_type'] as String? ?? 'concept';
    final chapter = concept['chapter'] as int?;
    final importance = concept['importance'] as String? ?? '';
    final keywords = concept['keywords'] as String? ?? '';

    final typeColor = _typeColors[type] ?? Colors.grey;

    return Dismissible(
      key: ValueKey('concept_$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete('确定删除节点「$name」？'),
      onDismissed: (_) => _deleteConcept(id),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showNodeDialog(concept: concept),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 32,
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 10),
                // Badges row
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _badge(
                      _typeLabels[type] ?? type,
                      typeColor,
                    ),
                    if (chapter != null)
                      _badge(
                        '第$chapter章',
                        _primaryColor,
                      ),
                    if (importance.isNotEmpty)
                      _badge(
                        _importanceLabels[importance] ?? importance,
                        _importanceColors[importance] ?? Colors.grey,
                      ),
                  ],
                ),
                // Keywords
                if (keywords.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.label_outline,
                          size: 14,
                          color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          keywords,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Edges tab ─────────────────────────────────────────────────────────────

  Widget _buildEdgesTab() {
    return Column(
      children: [
        _buildSearchBar(
          controller: _edgeSearchController,
          hint: '搜索源/目标节点或关系类型…',
          onChanged: (_) => setState(() => _applyEdgeFilter()),
        ),
        Expanded(
          child: _filteredRelations.isEmpty
              ? _buildEmptyState('暂无关系', Icons.timeline_outlined)
              : RefreshIndicator(
                  color: _primaryColor,
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                    itemCount: _filteredRelations.length,
                    itemBuilder: (context, index) =>
                        _buildEdgeCard(_filteredRelations[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEdgeCard(Map<String, dynamic> relation) {
    final id = relation['id'] as int;
    final srcId = relation['source_concept_id'] as int? ?? 0;
    final tgtId = relation['target_concept_id'] as int? ?? 0;
    final relType = relation['relation_type'] as String? ?? '';
    final weight = relation['weight'];
    final description = relation['description'] as String? ?? '';

    final srcName = _conceptNameById(srcId);
    final tgtName = _conceptNameById(tgtId);

    return Dismissible(
      key: ValueKey('relation_$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete('确定删除关系「$srcName → $tgtName」？'),
      onDismissed: (_) => _deleteRelation(id),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showEdgeDialog(relation: relation),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source → Target
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: srcName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const TextSpan(
                              text: '  →  ',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: tgtName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 8),
                // Badges
                Row(
                  children: [
                    _badge(
                      _relationLabels[relType] ?? relType,
                      _primaryColor,
                    ),
                    if (weight != null) ...[
                      const SizedBox(width: 6),
                      _badge(
                        '权重: $weight',
                        Colors.blueGrey,
                      ),
                    ],
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _buildSearchBar({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, color: _primaryColor),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: _primaryColor.withValues(alpha: 0.06),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _primaryColor, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  // ── Deletion helpers ──────────────────────────────────────────────────────

  Future<bool> _confirmDelete(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('确认删除'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteConcept(int id) async {
    try {
      await _dao.deleteConcept(id);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('节点已删除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteRelation(int id) async {
    try {
      await _dao.deleteRelation(id);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('关系已删除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  // ── Node edit dialog ──────────────────────────────────────────────────────

  void _showNodeDialog({Map<String, dynamic>? concept}) {
    final isEditing = concept != null;

    final nameCtrl =
        TextEditingController(text: concept?['concept_name'] as String? ?? '');
    final descCtrl =
        TextEditingController(text: concept?['description'] as String? ?? '');
    final keywordsCtrl =
        TextEditingController(text: concept?['keywords'] as String? ?? '');

    String selectedType = concept?['concept_type'] as String? ?? 'concept';
    int selectedChapter = concept?['chapter'] as int? ?? 1;
    String selectedImportance =
        concept?['importance'] as String? ?? 'important';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: Text(isEditing ? '编辑节点' : '添加节点'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '概念名称 *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Type dropdown
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(
                          labelText: '类型',
                          border: OutlineInputBorder(),
                        ),
                        items: _conceptTypes.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _typeColors[t] ?? Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(_typeLabels[t] ?? t),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedType = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Chapter & Importance in a row
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: selectedChapter,
                              decoration: const InputDecoration(
                                labelText: '章节',
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(6, (i) => i + 1)
                                  .map((ch) => DropdownMenuItem(
                                        value: ch,
                                        child: Text('第$ch章'),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setDialogState(() => selectedChapter = v);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedImportance,
                              decoration: const InputDecoration(
                                labelText: '重要性',
                                border: OutlineInputBorder(),
                              ),
                              items: _importanceLevels.map((imp) {
                                return DropdownMenuItem(
                                  value: imp,
                                  child: Text(
                                      _importanceLabels[imp] ?? imp),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setDialogState(
                                      () => selectedImportance = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Description
                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: '描述',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Keywords
                      TextField(
                        controller: keywordsCtrl,
                        decoration: const InputDecoration(
                          labelText: '关键词（逗号分隔）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryColor,
                  ),
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('概念名称不能为空')),
                      );
                      return;
                    }
                    final data = <String, dynamic>{
                      'concept_name': name,
                      'concept_type': selectedType,
                      'chapter': selectedChapter,
                      'importance': selectedImportance,
                      'description': descCtrl.text.trim(),
                      'keywords': keywordsCtrl.text.trim(),
                    };
                    Navigator.pop(ctx);
                    if (isEditing) {
                      _updateConcept(concept['id'] as int, data);
                    } else {
                      _addConcept(data);
                    }
                  },
                  child: Text(isEditing ? '保存' : '添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addConcept(Map<String, dynamic> data) async {
    try {
      await _dao.addConcept(data);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('节点已添加')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  Future<void> _updateConcept(int id, Map<String, dynamic> data) async {
    try {
      await _dao.updateConcept(id, data);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('节点已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
    }
  }

  // ── Edge edit dialog ──────────────────────────────────────────────────────

  void _showEdgeDialog({Map<String, dynamic>? relation}) {
    final isEditing = relation != null;

    int? selectedSource = relation?['source_concept_id'] as int?;
    int? selectedTarget = relation?['target_concept_id'] as int?;
    String selectedRelType =
        relation?['relation_type'] as String? ?? 'related_to';
    final weightCtrl = TextEditingController(
      text: (relation?['weight'] ?? 1.0).toString(),
    );
    final descCtrl = TextEditingController(
      text: relation?['description'] as String? ?? '',
    );

    // Build concept dropdown items
    final conceptItems = _allConcepts.map((c) {
      final cId = c['id'] as int;
      final cName = c['concept_name'] as String? ?? '未知';
      return DropdownMenuItem<int>(
        value: cId,
        child: Text(cName, overflow: TextOverflow.ellipsis),
      );
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: Text(isEditing ? '编辑关系' : '添加关系'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Source concept
                      DropdownButtonFormField<int>(
                        value: selectedSource,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '源节点 *',
                          border: OutlineInputBorder(),
                        ),
                        items: conceptItems,
                        onChanged: (v) {
                          setDialogState(() => selectedSource = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      // Target concept
                      DropdownButtonFormField<int>(
                        value: selectedTarget,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '目标节点 *',
                          border: OutlineInputBorder(),
                        ),
                        items: conceptItems,
                        onChanged: (v) {
                          setDialogState(() => selectedTarget = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      // Relation type
                      DropdownButtonFormField<String>(
                        value: selectedRelType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '关系类型',
                          border: OutlineInputBorder(),
                        ),
                        items: _relationTypes.map((rt) {
                          return DropdownMenuItem(
                            value: rt,
                            child: Text(_relationLabels[rt] ?? rt),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedRelType = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Weight
                      TextField(
                        controller: weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: '权重',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Description
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: '描述',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryColor,
                  ),
                  onPressed: () {
                    if (selectedSource == null || selectedTarget == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请选择源节点和目标节点')),
                      );
                      return;
                    }
                    if (selectedSource == selectedTarget) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('源节点和目标节点不能相同')),
                      );
                      return;
                    }
                    final data = <String, dynamic>{
                      'source_concept_id': selectedSource,
                      'target_concept_id': selectedTarget,
                      'relation_type': selectedRelType,
                      'weight': double.tryParse(weightCtrl.text.trim()) ?? 1.0,
                      'description': descCtrl.text.trim(),
                    };
                    Navigator.pop(ctx);
                    if (isEditing) {
                      _updateRelation(relation['id'] as int, data);
                    } else {
                      _addRelation(data);
                    }
                  },
                  child: Text(isEditing ? '保存' : '添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addRelation(Map<String, dynamic> data) async {
    try {
      await _dao.addRelation(data);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('关系已添加')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  Future<void> _updateRelation(int id, Map<String, dynamic> data) async {
    try {
      // DAO has no updateRelation – delete and re-insert
      await _dao.deleteRelation(id);
      await _dao.addRelation(data);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('关系已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
    }
  }

  // ── AI 智能推荐 ─────────────────────────────────────────────────────────

  void _showAiRecommendDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AiRecommendDialog(
        existingConcepts: _allConcepts,
        existingRelations: _allRelations,
        dao: _dao,
        onAccepted: () {
          _loadData(); // 刷新列表
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI 推荐审核对话框
// ═══════════════════════════════════════════════════════════════════════════════

class _AiRecommendDialog extends StatefulWidget {
  final List<Map<String, dynamic>> existingConcepts;
  final List<Map<String, dynamic>> existingRelations;
  final KnowledgeGraphDao dao;
  final VoidCallback onAccepted;

  const _AiRecommendDialog({
    required this.existingConcepts,
    required this.existingRelations,
    required this.dao,
    required this.onAccepted,
  });

  @override
  State<_AiRecommendDialog> createState() => _AiRecommendDialogState();
}

class _AiRecommendDialogState extends State<_AiRecommendDialog> {
  static const _primaryColor = Color(0xFF667eea);
  static const _aiGold = Color(0xFFFFAB00);

  static const _typeLabels = <String, String>{
    'concept': '概念',
    'technology': '技术',
    'tool': '工具',
    'framework': '框架',
    'language': '语言',
    'platform': '平台',
    'pattern': '模式',
  };

  static const _relationLabels = <String, String>{
    'prerequisite': '前置知识',
    'related_to': '相关',
    'part_of': '属于',
    'compared_with': '对比',
    'applied_in': '应用于',
    'builds_upon': '基于',
    'alternative_to': '替代',
    'extends': '扩展',
  };

  final AiService _aiService = AiService();

  bool _isLoading = false;
  String? _error;

  // AI 推荐结果
  List<Map<String, dynamic>> _recConcepts = [];
  List<Map<String, dynamic>> _recRelations = [];

  // 勾选状态
  List<bool> _conceptChecked = [];
  List<bool> _relationChecked = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchRecommendations();
  }

  Future<void> _fetchRecommendations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _aiService.recommendGraphElements(
        existingConcepts: widget.existingConcepts,
        existingRelations: widget.existingRelations,
      );
      setState(() {
        _recConcepts =
            (result['concepts'] as List).cast<Map<String, dynamic>>();
        _recRelations =
            (result['relations'] as List).cast<Map<String, dynamic>>();
        _conceptChecked = List.filled(_recConcepts.length, true);
        _relationChecked = List.filled(_recRelations.length, true);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Flexible(child: _buildBody()),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: BoxDecoration(
        color: _primaryColor.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: _aiGold, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 智能推荐',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
                Text(
                  '基于现有 ${widget.existingConcepts.length} 个概念、'
                  '${widget.existingRelations.length} 条关系分析推荐',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: _primaryColor,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'AI 正在分析知识图谱并生成推荐...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              '这可能需要 10~30 秒',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(
              '推荐失败',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _fetchRecommendations,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_recConcepts.isEmpty && _recRelations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('AI 未返回推荐内容，当前图谱可能已比较完善。'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 推荐概念 ──
          if (_recConcepts.isNotEmpty) ...[
            _sectionTitle(
              Icons.bubble_chart,
              '推荐新概念',
              '${_recConcepts.length} 个',
            ),
            const SizedBox(height: 8),
            ...List.generate(_recConcepts.length, (i) {
              final c = _recConcepts[i];
              final conf = (c['confidence'] as num?)?.toDouble() ?? 0.8;
              return _recommendCard(
                checked: _conceptChecked[i],
                onChecked: (v) =>
                    setState(() => _conceptChecked[i] = v ?? true),
                title: c['concept_name'] as String? ?? '未命名',
                subtitle: _typeLabels[c['concept_type']] ?? c['concept_type']?.toString() ?? '概念',
                description: c['description'] as String? ?? '',
                confidence: conf,
                badgeColor: Colors.purple,
                icon: Icons.add_circle_outline,
              );
            }),
            const SizedBox(height: 16),
          ],

          // ── 推荐关系 ──
          if (_recRelations.isNotEmpty) ...[
            _sectionTitle(
              Icons.timeline,
              '推荐新关系',
              '${_recRelations.length} 条',
            ),
            const SizedBox(height: 8),
            ...List.generate(_recRelations.length, (i) {
              final r = _recRelations[i];
              final conf = (r['confidence'] as num?)?.toDouble() ?? 0.8;
              final src = r['source'] as String? ?? '?';
              final tgt = r['target'] as String? ?? '?';
              final relType = r['relation_type'] as String? ?? 'related_to';
              return _recommendCard(
                checked: _relationChecked[i],
                onChecked: (v) =>
                    setState(() => _relationChecked[i] = v ?? true),
                title: '$src → $tgt',
                subtitle: _relationLabels[relType] ?? relType,
                description: r['description'] as String? ?? '',
                confidence: conf,
                badgeColor: _primaryColor,
                icon: Icons.arrow_right_alt,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title, String count) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _primaryColor),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: _primaryColor,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _aiGold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _aiGold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _recommendCard({
    required bool checked,
    required ValueChanged<bool?> onChecked,
    required String title,
    required String subtitle,
    required String description,
    required double confidence,
    required Color badgeColor,
    required IconData icon,
  }) {
    final confPercent = (confidence * 100).round();
    final confColor = confidence >= 0.8
        ? Colors.green
        : confidence >= 0.6
            ? Colors.orange
            : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: checked
            ? BorderSide(color: _primaryColor.withValues(alpha: 0.3), width: 1)
            : BorderSide.none,
      ),
      elevation: checked ? 2 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChecked(!checked),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: onChecked,
                activeColor: _primaryColor,
              ),
              Icon(icon, size: 20, color: badgeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.psychology, size: 14, color: confColor),
                        const SizedBox(width: 3),
                        Text(
                          '置信度 $confPercent%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: confColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_isLoading || _error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }

    final selectedConcepts =
        _conceptChecked.where((v) => v).length;
    final selectedRelations =
        _relationChecked.where((v) => v).length;
    final totalSelected = selectedConcepts + selectedRelations;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          // 全选/取消按钮
          TextButton.icon(
            onPressed: () {
              final allChecked = _conceptChecked.every((v) => v) &&
                  _relationChecked.every((v) => v);
              setState(() {
                _conceptChecked =
                    List.filled(_recConcepts.length, !allChecked);
                _relationChecked =
                    List.filled(_recRelations.length, !allChecked);
              });
            },
            icon: Icon(
              _conceptChecked.every((v) => v) &&
                      _relationChecked.every((v) => v)
                  ? Icons.deselect
                  : Icons.select_all,
              size: 18,
            ),
            label: Text(
              _conceptChecked.every((v) => v) &&
                      _relationChecked.every((v) => v)
                  ? '取消全选'
                  : '全选',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const Spacer(),
          // 重新推荐
          OutlinedButton.icon(
            onPressed: _fetchRecommendations,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重新推荐', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          // 确认采纳
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _primaryColor),
            onPressed: totalSelected == 0 || _isSaving
                ? null
                : _applySelected,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(
              '采纳选中 ($totalSelected)',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applySelected() async {
    setState(() => _isSaving = true);

    try {
      int addedConcepts = 0;
      int addedRelations = 0;

      // 记录新增概念名 → 数据库 ID 的映射，供关系连接使用
      final newConceptIds = <String, int>{};

      // 已有概念名 → ID 映射
      final existingNameToId = <String, int>{};
      for (final c in widget.existingConcepts) {
        existingNameToId[c['concept_name'] as String? ?? ''] = c['id'] as int;
      }

      // 1. 插入选中的概念
      for (var i = 0; i < _recConcepts.length; i++) {
        if (!_conceptChecked[i]) continue;
        final c = _recConcepts[i];
        final name = c['concept_name'] as String? ?? '';
        if (name.isEmpty || existingNameToId.containsKey(name)) continue;

        final id = await widget.dao.addConcept({
          'concept_name': name,
          'concept_type': c['concept_type'] ?? 'concept',
          'chapter': c['chapter'] ?? 1,
          'importance': c['importance'] ?? 'important',
          'description': c['description'] ?? '',
          'keywords': c['keywords'] ?? '',
        });
        if (id > 0) {
          newConceptIds[name] = id;
          addedConcepts++;
        }
      }

      // 合并名称映射
      final allNameToId = {...existingNameToId, ...newConceptIds};

      // 2. 插入选中的关系
      for (var i = 0; i < _recRelations.length; i++) {
        if (!_relationChecked[i]) continue;
        final r = _recRelations[i];
        final srcName = r['source'] as String? ?? '';
        final tgtName = r['target'] as String? ?? '';
        final srcId = allNameToId[srcName];
        final tgtId = allNameToId[tgtName];
        if (srcId == null || tgtId == null || srcId == tgtId) continue;

        final id = await widget.dao.addRelation({
          'source_concept_id': srcId,
          'target_concept_id': tgtId,
          'relation_type': r['relation_type'] ?? 'related_to',
          'relation_label': r['description'] ?? '',
          'weight': (r['weight'] as num?)?.toDouble() ?? 1.0,
          'description': r['description'] ?? '',
          'ai_generated': 1,
          'confidence': (r['confidence'] as num?)?.toDouble() ?? 0.8,
        });
        if (id > 0) addedRelations++;
      }

      widget.onAccepted();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ 已采纳：$addedConcepts 个概念、$addedRelations 条关系',
            ),
            backgroundColor: _primaryColor,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('采纳失败: $e')),
        );
      }
    }
  }
}
