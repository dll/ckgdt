import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/local/hot_video_dao.dart';
import '../../../data/models/hot_video_model.dart';
import '../../../services/auth_service.dart';
import 'add_video_page.dart';
import '../../widgets/back_button_bar.dart';

class HotVideosPage extends StatefulWidget {
  const HotVideosPage({super.key});

  @override
  State<HotVideosPage> createState() => _HotVideosPageState();
}

class _HotVideosPageState extends State<HotVideosPage> {
  final _dao = HotVideoDao();
  final _authService = AuthService();
  final _searchController = TextEditingController();

  List<HotVideoModel> _videos = [];
  String _selectedPlatform = 'all';
  String _sortBy = 'latest';
  int _totalCount = 0;
  int _favCount = 0;
  bool _loading = true;

  String get _userId => _authService.currentUser?.userId ?? '';

  static const _platforms = <Map<String, dynamic>>[
    {'key': 'all', 'label': '全部分类', 'color': Colors.grey, 'icon': Icons.apps},
    {'key': 'bilibili', 'label': 'B站', 'color': Color(0xFFFB7299), 'icon': Icons.play_circle},
    {'key': 'youtube', 'label': 'YouTube', 'color': Color(0xFFFF0000), 'icon': Icons.ondemand_video},
    {'key': 'douyin', 'label': '抖音', 'color': Colors.black, 'icon': Icons.music_note},
    {'key': 'twitter', 'label': '推特', 'color': Color(0xFF1DA1F2), 'icon': Icons.chat_bubble},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final videos = await _dao.getVideos(
        userId: _userId,
        platform: _selectedPlatform,
        sortBy: _sortBy,
        searchQuery: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      final total = await _dao.getVideoCount(
        platform: _selectedPlatform,
        searchQuery: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      final favs = await _dao.getFavoritedVideos(_userId);
      setState(() {
        _videos = videos;
        _totalCount = total;
        _favCount = favs.length;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite(HotVideoModel video) async {
    try {
      if (video.isFavorited) {
        await _dao.removeFavorite(_userId, video.id!);
      } else {
        await _dao.addFavorite(_userId, video.id!);
      }
      await _loadData();
    } catch (_) {}
  }

  Future<void> _deleteVideo(HotVideoModel video) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除视频'),
        content: Text('确定要删除 "${video.title}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && video.id != null) {
      await _dao.deleteVideo(video.id!);
      await _loadData();
    }
  }

  Future<void> _openVideoUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接，请检查浏览器设置'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_authService.isLoggedIn) {
      return Scaffold(
        appBar: BackButtonBar(title: '推荐视频'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.recommend, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('请先登录', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
    }

    final isOwner = _authService.isTeacher || _authService.isAdmin;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: BackButtonBar(
        title: '推荐视频',
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: '我的收藏',
            onPressed: () => _showFavorites(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索视频标题或来源...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadData();
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _loadData(),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 平台筛选芯片
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _platforms.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final p = _platforms[index];
                final selected = _selectedPlatform == p['key'];
                return FilterChip(
                  selected: selected,
                  avatar: Icon(p['icon'] as IconData, size: 16,
                      color: selected ? Colors.white : p['color'] as Color),
                  label: Text(p['label'] as String),
                  selectedColor: p['color'] as Color,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : null,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() => _selectedPlatform = p['key'] as String);
                    _loadData();
                  },
                );
              },
            ),
          ),

          // 排序 + 统计
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text('共 $_totalCount 个视频  ·  $_favCount 收藏',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const Spacer(),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sortBy,
                    isDense: true,
                    style: TextStyle(fontSize: 12, color: colorScheme.primary),
                    items: const [
                      DropdownMenuItem(value: 'latest', child: Text('最新发布')),
                      DropdownMenuItem(value: 'hottest', child: Text('最多收藏')),
                      DropdownMenuItem(value: 'most_viewed', child: Text('最多播放')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _sortBy = v);
                        _loadData();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // 视频列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _videos.isEmpty
                    ? _buildEmptyState(colorScheme)
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = constraints.maxWidth > 900
                                ? 4
                                : constraints.maxWidth > 600
                                    ? 3
                                    : 2;
                            return GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: 0.72,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _videos.length,
                              itemBuilder: (_, i) => _VideoCard(
                                video: _videos[i],
                                onTap: () => _showVideoDetail(_videos[i]),
                                onFavorite: () => _toggleFavorite(_videos[i]),
                                onDelete: () => _deleteVideo(_videos[i]),
                                isOwner: isOwner,
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => AddVideoPage(userId: _userId)),
          );
          if (result == true) _loadData();
        },
        icon: const Icon(Icons.add),
        label: const Text('添加视频'),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.recommend, size: 80, color: Colors.deepOrange.shade200),
          const SizedBox(height: 16),
          Text('还没有推荐视频', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('点击右下角按钮添加来自B站、YouTube等平台的视频',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  void _showFavorites() async {
    final favs = await _dao.getFavoritedVideos(_userId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FavoritesSheet(
        videos: favs,
        onTap: (video) {
          Navigator.pop(context);
          _showVideoDetail(video);
        },
        onUnfavorite: (video) async {
          await _dao.removeFavorite(_userId, video.id!);
          if (mounted) Navigator.pop(context);
          _loadData();
        },
      ),
    );
  }

  void _showVideoDetail(HotVideoModel video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _VideoDetailSheet(
        video: video,
        onOpenUrl: () => _openVideoUrl(video.videoUrl),
        onFavorite: () => _toggleFavorite(video),
        onDelete: () {
          Navigator.pop(context);
          _deleteVideo(video);
        },
        isOwner: _authService.isTeacher || _authService.isAdmin || video.userId == _userId,
      ),
    );
  }
}

// ── 视频卡片 ──

class _VideoCard extends StatelessWidget {
  final HotVideoModel video;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final bool isOwner;

  const _VideoCard({
    required this.video,
    required this.onTap,
    required this.onFavorite,
    required this.onDelete,
    required this.isOwner,
  });

  static const _platformColors = {
    'bilibili': Color(0xFFFB7299),
    'youtube': Color(0xFFFF0000),
    'douyin': Colors.black,
    'twitter': Color(0xFF1DA1F2),
  };

  static const _platformNames = {
    'bilibili': 'B站',
    'youtube': 'YouTube',
    'douyin': '抖音',
    'twitter': '推特',
  };

  @override
  Widget build(BuildContext context) {
    final platformColor = _platformColors[video.platform] ?? Colors.grey;
    final platformName = _platformNames[video.platform] ?? video.platform;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        onLongPress: isOwner ? onDelete : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图区域
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          platformColor.withValues(alpha: 0.3),
                          platformColor.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(Icons.play_circle_fill,
                          size: 40, color: platformColor.withValues(alpha: 0.6)),
                    ),
                  ),
                  // 平台角标
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: platformColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(platformName,
                          style: const TextStyle(color: Colors.white, fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  // 时长
                  if (video.duration != null && video.duration!.isNotEmpty)
                    Positioned(
                      bottom: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(video.duration!,
                            style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                ],
              ),
            ),

            // 信息
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (video.source != null && video.source!.isNotEmpty)
                      Text(video.source!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    Row(
                      children: [
                        if (video.viewCount != null && video.viewCount!.isNotEmpty)
                          Text(video.viewCount!,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                        const Spacer(),
                        GestureDetector(
                          onTap: onFavorite,
                          child: Icon(
                            video.isFavorited ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: video.isFavorited ? Colors.red : Colors.grey.shade400,
                          ),
                        ),
                        if (video.favoriteCount > 0) ...[
                          const SizedBox(width: 2),
                          Text('${video.favoriteCount}',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 收藏列表 ──

class _FavoritesSheet extends StatelessWidget {
  final List<HotVideoModel> videos;
  final Function(HotVideoModel) onTap;
  final Function(HotVideoModel) onUnfavorite;

  const _FavoritesSheet({
    required this.videos,
    required this.onTap,
    required this.onUnfavorite,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.favorite, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                const Text('我的收藏', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${videos.length} 个', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Expanded(
            child: videos.isEmpty
                ? Center(child: Text('还没有收藏视频', style: TextStyle(color: Colors.grey.shade400)))
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: videos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_circle_outline, size: 28),
                      title: Text(videos[i].title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        icon: const Icon(Icons.favorite, color: Colors.red, size: 20),
                        onPressed: () => onUnfavorite(videos[i]),
                      ),
                      onTap: () => onTap(videos[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 视频详情弹窗 ──

class _VideoDetailSheet extends StatelessWidget {
  final HotVideoModel video;
  final VoidCallback onOpenUrl;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final bool isOwner;

  const _VideoDetailSheet({
    required this.video,
    required this.onOpenUrl,
    required this.onFavorite,
    required this.onDelete,
    required this.isOwner,
  });

  static const _platformNames = {
    'bilibili': 'B站',
    'youtube': 'YouTube',
    'douyin': '抖音',
    'twitter': '推特',
  };

  @override
  Widget build(BuildContext context) {
    final platformName = _platformNames[video.platform] ?? video.platform;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(children: [
            Expanded(child: Text(video.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(
              icon: Icon(video.isFavorited ? Icons.favorite : Icons.favorite_border,
                  color: video.isFavorited ? Colors.red : null),
              onPressed: onFavorite,
            ),
          ]),
          const SizedBox(height: 12),

          _infoRow(Icons.play_circle, '平台', platformName),
          if (video.source != null && video.source!.isNotEmpty)
            _infoRow(Icons.person, '来源', video.source!),
          if (video.duration != null && video.duration!.isNotEmpty)
            _infoRow(Icons.timer, '时长', video.duration!),
          if (video.viewCount != null && video.viewCount!.isNotEmpty)
            _infoRow(Icons.visibility, '播放', video.viewCount!),
          if (video.publishDate != null && video.publishDate!.isNotEmpty)
            _infoRow(Icons.calendar_today, '发布', video.publishDate!),
          if (video.description != null && video.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(video.description!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 16),

          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onOpenUrl,
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('打开原站观看'),
              ),
            ),
            if (isOwner) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: '删除',
              ),
            ],
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }
}
