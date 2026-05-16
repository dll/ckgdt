import 'package:flutter/material.dart';
import '../../../data/local/favorite_dao.dart';
import '../../../data/local/graph_dao.dart';
import '../../../services/auth_service.dart';
import 'graph_detail_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final _favoriteDao = FavoriteDao();
  final _authService = AuthService();

  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _filteredFavorites = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final favorites = await _favoriteDao.getFavorites(user.userId);
        if (!mounted) return;
        setState(() {
          _favorites = favorites;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredFavorites = _favorites;
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredFavorites = _favorites.where((fav) {
        final title = (fav['node_title'] ?? '').toString().toLowerCase();
        final nodeId = (fav['node_id'] ?? '').toString().toLowerCase();
        return title.contains(q) || nodeId.contains(q);
      }).toList();
    }
  }

  Future<void> _removeFavorite(String nodeId) async {
    final user = _authService.currentUser;
    if (user != null) {
      await _favoriteDao.removeFavorite(user.userId, nodeId);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消收藏')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索收藏…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilter();
                          });
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _applyFilter();
                });
              },
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_border, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        '暂无收藏内容',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '在图谱中点击星星图标收藏知识点',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : _filteredFavorites.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            '未找到"$_searchQuery"相关收藏',
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredFavorites.length,
                    itemBuilder: (context, index) {
                      final fav = _filteredFavorites[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.amber[100],
                            child: Icon(Icons.star, color: Colors.amber[700]),
                          ),
                          title: Text(fav['node_title'] ?? ''),
                          subtitle: Text(
                            '收藏时间: ${fav['favorite_time']?.substring(0, 10) ?? ''}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _removeFavorite(fav['node_id']),
                          ),
                          onTap: () async {
                            final nodeId = fav['node_id'] as String?;
                            if (nodeId == null) return;
                            // 查找节点所属图谱
                            final graphDao = GraphDao();
                            final node = await graphDao.getNode(nodeId);
                            if (node == null || !context.mounted) return;
                            final graphId = node.graphId;
                            final graph = await graphDao.getGraph(graphId);
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GraphDetailPage(
                                  graphId: graphId,
                                  graphTitle: graph?.title ?? '知识图谱',
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
