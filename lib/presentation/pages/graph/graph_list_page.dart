import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../data/local/graph_dao.dart';
import '../../../data/models/graph_model.dart';
import 'graph_detail_page.dart';

class GraphListPage extends StatefulWidget {
  const GraphListPage({super.key});

  @override
  State<GraphListPage> createState() => _GraphListPageState();
}

class _GraphListPageState extends State<GraphListPage> {
  final GraphDao _graphDao = GraphDao();
  List<GraphModel> _graphs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGraphs();
  }

  Future<void> _loadGraphs() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('=== GraphListPage: Loading graphs...');
      final graphs = await _graphDao.getAllGraphs();
      debugPrint('=== GraphListPage: Got ${graphs.length} graphs');
      setState(() {
        _graphs = graphs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('=== GraphListPage: Error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_graphs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_tree_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '暂无图谱数据',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadGraphs,
              child: const Text('刷新'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGraphs,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _graphs.length,
        itemBuilder: (context, index) {
          final graph = _graphs[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF667eea),
                child: const Icon(Icons.account_tree, color: Colors.white),
              ),
              title: Text(
                graph.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(graph.graphType ?? '图谱'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GraphDetailPage(
                      graphId: graph.id,
                      graphTitle: graph.title,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
