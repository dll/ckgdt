import 'package:flutter/material.dart';
import '../../../data/local/knowledge_graph_dao.dart';

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
                        initialValue: selectedType,
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
                              initialValue: selectedChapter,
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
                              initialValue: selectedImportance,
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
                        initialValue: selectedSource,
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
                        initialValue: selectedTarget,
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
                        initialValue: selectedRelType,
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
}
