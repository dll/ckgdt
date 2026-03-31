import 'package:flutter/material.dart';
import '../../../data/local/graph_dao.dart';
import '../../../data/models/graph_model.dart';
import 'graph_detail_page.dart';

/// 图谱列表页 — 层级树形展示
/// 根节点: "移动应用开发图谱" (graph_main_overview)
/// 子节点: 6 个分类图谱 (graph_detail_XX-...)
class GraphListPage extends StatefulWidget {
  const GraphListPage({super.key});

  @override
  State<GraphListPage> createState() => _GraphListPageState();
}

class _GraphListPageState extends State<GraphListPage>
    with SingleTickerProviderStateMixin {
  final GraphDao _graphDao = GraphDao();

  bool _isLoading = true;
  GraphModel? _mainGraph; // 总图谱
  List<GraphModel> _categoryGraphs = []; // 6 个分类图谱
  Map<String, Map<String, int>> _stats = {}; // graphId → {nodes, edges}
  bool _isExpanded = false; // 子图谱展开状态

  // 总统计
  int _totalNodes = 0;
  int _totalEdges = 0;

  // 分类颜色映射
  static const _categoryColors = <String, Color>{
    '课程图谱': Color(0xFFE53935),
    '技术栈图谱': Color(0xFF1E88E5),
    '实验图谱': Color(0xFFFB8C00),
    '项目图谱': Color(0xFF43A047),
    '教学图谱': Color(0xFF8E24AA),
    '学习图谱': Color(0xFF00897B),
  };

  // 分类图标映射
  static const _categoryIcons = <String, IconData>{
    '课程图谱': Icons.school,
    '技术栈图谱': Icons.layers,
    '实验图谱': Icons.science,
    '项目图谱': Icons.work,
    '教学图谱': Icons.cast_for_education,
    '学习图谱': Icons.auto_stories,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final allGraphs = await _graphDao.getAllGraphs();

      // 分离总图谱和分类图谱
      _mainGraph = allGraphs
          .where((g) => g.id == 'graph_main_overview')
          .firstOrNull;
      _categoryGraphs = allGraphs
          .where((g) =>
              g.id.startsWith('graph_detail_') && g.graphType == 'md_import')
          .toList();

      // 按分类名排序
      _categoryGraphs.sort((a, b) => a.id.compareTo(b.id));

      // 加载统计数据
      final allIds = <String>[];
      if (_mainGraph != null) allIds.add(_mainGraph!.id);
      allIds.addAll(_categoryGraphs.map((g) => g.id));

      _stats = await _graphDao.getGraphStats(allIds);

      // 计算总统计
      _totalNodes = 0;
      _totalEdges = 0;
      for (final s in _stats.values) {
        _totalNodes += s['nodes'] ?? 0;
        _totalEdges += s['edges'] ?? 0;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('=== GraphListPage: Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Color _getCategoryColor(String title) {
    for (final entry in _categoryColors.entries) {
      if (title.contains(entry.key)) return entry.value;
    }
    return const Color(0xFF667eea);
  }

  IconData _getCategoryIcon(String title) {
    for (final entry in _categoryIcons.entries) {
      if (title.contains(entry.key)) return entry.value;
    }
    return Icons.account_tree;
  }

  String _getCategoryShortName(String title) {
    // "课程图谱详细图谱" → "课程图谱"
    return title.replaceAll('详细图谱', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mainGraph == null && _categoryGraphs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('暂无图谱数据',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadData, child: const Text('刷新')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 根节点卡片：移动应用开发图谱 ──
          _buildRootCard(),
          const SizedBox(height: 12),

          // ── 展开/收起子图谱 ──
          if (_isExpanded) ...[
            // 连接线和子图谱列表
            ..._buildCategoryCards(),
          ],
        ],
      ),
    );
  }

  // ── 根节点卡片 ──────────────────────────────────────────────────────────

  Widget _buildRootCard() {
    final mainStats = _stats[_mainGraph?.id] ?? {'nodes': 0, 'edges': 0};

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() => _isExpanded = !_isExpanded);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.hub, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '移动应用开发图谱',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '6大分类 · ${_categoryGraphs.length}个子图谱',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 展开/收起指示器
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(Icons.expand_more,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 统计卡片行
              Row(
                children: [
                  _miniStatCard(Icons.circle, '总节点', '$_totalNodes'),
                  const SizedBox(width: 10),
                  _miniStatCard(Icons.timeline, '总关系', '$_totalEdges'),
                  const SizedBox(width: 10),
                  _miniStatCard(Icons.category, '子图谱',
                      '${_categoryGraphs.length}'),
                  const SizedBox(width: 10),
                  _miniStatCard(Icons.account_tree, '总图谱',
                      '${mainStats['nodes']}节点'),
                ],
              ),
              const SizedBox(height: 12),

              // 查看总图谱按钮
              if (_mainGraph != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _navigateToGraph(_mainGraph!),
                    icon: const Icon(Icons.visibility,
                        size: 16, color: Colors.white),
                    label: const Text('查看总图谱',
                        style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStatCard(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── 子图谱卡片列表 ───────────────────────────────────────────────────

  List<Widget> _buildCategoryCards() {
    final widgets = <Widget>[];
    for (int i = 0; i < _categoryGraphs.length; i++) {
      final graph = _categoryGraphs[i];
      final isLast = i == _categoryGraphs.length - 1;
      widgets.add(_buildCategoryCard(graph, i, isLast));
    }
    return widgets;
  }

  Widget _buildCategoryCard(GraphModel graph, int index, bool isLast) {
    final shortName = _getCategoryShortName(graph.title);
    final color = _getCategoryColor(graph.title);
    final icon = _getCategoryIcon(graph.title);
    final stats = _stats[graph.id] ?? {'nodes': 0, 'edges': 0};
    final nodeCount = stats['nodes'] ?? 0;
    final edgeCount = stats['edges'] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(left: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 树形连接线
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: isLast ? 40 : 90,
                  color: const Color(0xFF667eea).withValues(alpha: 0.3),
                ),
                if (isLast)
                  Container(
                    width: 2,
                    height: 0,
                  ),
              ],
            ),
          ),
          // 水平连接线 + 圆点
          Column(
            children: [
              const SizedBox(height: 36),
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 2,
                    color: const Color(0xFF667eea).withValues(alpha: 0.3),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 8),
          // 卡片内容
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _navigateToGraph(graph),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      // 分类图标
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 12),
                      // 信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(shortName,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _statBadge(
                                    Icons.circle, '$nodeCount', color),
                                const SizedBox(width: 8),
                                _statBadge(
                                    Icons.timeline, '$edgeCount',
                                    Colors.grey),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 箭头
                      Icon(Icons.chevron_right,
                          color: Colors.grey.shade400, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(fontSize: 11, color: color,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _navigateToGraph(GraphModel graph) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GraphDetailPage(
          graphId: graph.id,
          graphTitle: graph.title,
        ),
      ),
    ).then((_) => _loadData()); // 返回时刷新
  }
}
