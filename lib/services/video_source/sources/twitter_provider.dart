import 'package:flutter/material.dart';
import '../../../core/error_handler.dart';
import '../video_source_provider.dart';

class TwitterProvider implements VideoSourceProvider {
  @override
  String get platformId => 'twitter';

  @override
  String get displayName => 'Twitter';

  @override
  dynamic get icon => Icons.alternate_email;

  @override
  int get themeColor => 0xFF1DA1F2;

  @override
  bool get enabled => false;

  final List<VideoItem> _mockVideos = [
    const VideoItem(
      id: 'tw_001',
      platformId: 'twitter',
      title: 'Flutter Widget 生命周期全解析 🧵',
      description:
          '深入分析 Flutter Widget 从创建到销毁的完整生命周期，以及每个阶段的最佳实践',
      thumbnailUrl: 'https://picsum.photos/seed/tw_001/480/360',
      videoUrl: 'https://twitter.com/i/status/001',
      author: '@flutterDev',
      authorAvatar: 'https://picsum.photos/seed/avatar_tw1/100/100',
      viewCount: 25000,
      likeCount: 3200,
      durationSeconds: 300,
      tags: ['Flutter', 'Widget', '生命周期'],
      hotScore: 55.3,
    ),
    const VideoItem(
      id: 'tw_002',
      platformId: 'twitter',
      title: 'Dart 3.7 新特性全面解读',
      description:
          'Dart 3.7 发布！新增模式匹配增强、宏机制预览、性能优化等重磅功能，一帖看懂',
      thumbnailUrl: 'https://picsum.photos/seed/tw_002/480/360',
      videoUrl: 'https://twitter.com/i/status/002',
      author: '@dart_lang',
      authorAvatar: 'https://picsum.photos/seed/avatar_tw2/100/100',
      viewCount: 18000,
      likeCount: 2400,
      durationSeconds: 240,
      tags: ['Dart', '新特性', '编程语言'],
      hotScore: 48.7,
    ),
    const VideoItem(
      id: 'tw_003',
      platformId: 'twitter',
      title: '对于大型项目，Riverpod 比 Provider 更优的5个理由',
      description:
          '深度对比 Flutter 两大状态管理方案，Riverpod 的编译安全、自动释放、族修饰器完胜',
      thumbnailUrl: 'https://picsum.photos/seed/tw_003/480/360',
      videoUrl: 'https://twitter.com/i/status/003',
      author: '@codeWithMe',
      authorAvatar: 'https://picsum.photos/seed/avatar_tw3/100/100',
      viewCount: 32000,
      likeCount: 4100,
      durationSeconds: 360,
      tags: ['Riverpod', 'Provider', '状态管理'],
      hotScore: 62.8,
    ),
    const VideoItem(
      id: 'tw_004',
      platformId: 'twitter',
      title: '我的第一个开源 Flutter 包突破 1k Star！',
      description:
          '分享从零开始开发 Flutter 开源包的经历：选题、开发、文档、推广，以及学到的经验教训',
      thumbnailUrl: 'https://picsum.photos/seed/tw_004/480/360',
      videoUrl: 'https://twitter.com/i/status/004',
      author: '@programmingDog',
      authorAvatar: 'https://picsum.photos/seed/avatar_tw4/100/100',
      viewCount: 8500,
      likeCount: 1200,
      durationSeconds: 180,
      tags: ['开源', 'Flutter', 'Package'],
      hotScore: 38.4,
    ),
    const VideoItem(
      id: 'tw_005',
      platformId: 'twitter',
      title: '移动端系统设计 — 缓存策略深度解析',
      description:
          '多级缓存架构：内存缓存、磁盘缓存、分布式缓存，以及缓存一致性和淘汰策略详解',
      thumbnailUrl: 'https://picsum.photos/seed/tw_005/480/360',
      videoUrl: 'https://twitter.com/i/status/005',
      author: '@alexxubyte',
      authorAvatar: 'https://picsum.photos/seed/avatar_tw5/100/100',
      viewCount: 41500,
      likeCount: 5200,
      durationSeconds: 420,
      tags: ['系统设计', '缓存', '移动端'],
      hotScore: 68.9,
    ),
    const VideoItem(
      id: 'tw_006',
      platformId: 'twitter',
      title: 'Flutter Web vs React — 2025 性能基准测试',
      description:
          '同页面下 Flutter Web 与 React 的首次渲染、交互延迟、内存占用等多项指标定量对比',
      thumbnailUrl: 'https://picsum.photos/seed/tw_006/480/360',
      videoUrl: 'https://twitter.com/i/status/006',
      author: '@rauchg',
      authorAvatar: 'https://picsum.photos/seed/avatar_tw6/100/100',
      viewCount: 12800,
      likeCount: 1650,
      durationSeconds: 300,
      tags: ['Flutter Web', 'React', '性能对比'],
      hotScore: 42.6,
    ),
  ];

  @override
  Future<List<VideoItem>> getRecommendedVideos({
    int page = 1,
    int pageSize = 20,
    String? keyword,
  }) async {
    final filtered = _filterByKeyword(_mockVideos, keyword);
    final start = (page - 1) * pageSize;
    final end = start + pageSize;
    if (start >= filtered.length) return [];
    return filtered.sublist(start, end > filtered.length ? filtered.length : end);
  }

  @override
  Future<VideoItem?> getVideoDetail(String videoId) async {
    try {
      return _mockVideos.firstWhere((v) => v.id == videoId);
    } catch (e, st) {
      swallowDebug(e, tag: 'TwitterProvider.getVideoDetail', stack: st);
      return null;
    }
  }

  List<VideoItem> _filterByKeyword(List<VideoItem> items, String? keyword) {
    if (keyword == null || keyword.trim().isEmpty) return items;
    final kw = keyword.toLowerCase();
    return items.where((v) {
      return v.title.toLowerCase().contains(kw) ||
          (v.description?.toLowerCase().contains(kw) ?? false) ||
          v.tags.any((t) => t.toLowerCase().contains(kw));
    }).toList();
  }
}
