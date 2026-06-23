import 'package:flutter/material.dart';
import '../../../core/error_handler.dart';
import '../video_source_provider.dart';

class KuaishouProvider implements VideoSourceProvider {
  @override
  String get platformId => 'kuaishou';

  @override
  String get displayName => '快手';

  @override
  dynamic get icon => Icons.video_library;

  @override
  int get themeColor => 0xFFFF4906;

  @override
  bool get enabled => false;

  final List<VideoItem> _mockVideos = [
    const VideoItem(
      id: 'kuaishou_001',
      platformId: 'kuaishou',
      title: '从零开发一个Flutter天气预报App',
      description: '完整项目实战：Flutter + 高德地图API + 城市搜索，打包发布全流程',
      thumbnailUrl:
          'https://picsum.photos/seed/kuaishou_001/480/360',
      videoUrl: 'https://www.kuaishou.com/video/001',
      author: '老王讲IT',
      authorAvatar:
          'https://picsum.photos/seed/avatar_ks1/100/100',
      viewCount: 67200,
      likeCount: 5430,
      durationSeconds: 2100,
      tags: ['Flutter', '项目实战', '天气App'],
      hotScore: 73.4,
    ),
    const VideoItem(
      id: 'kuaishou_002',
      platformId: 'kuaishou',
      title: 'Android Jetpack全家桶实战指南',
      description: 'ViewModel + LiveData + Room + Navigation + Compose 一套打通',
      thumbnailUrl:
          'https://picsum.photos/seed/kuaishou_002/480/360',
      videoUrl: 'https://www.kuaishou.com/video/002',
      author: '小黑课堂',
      authorAvatar:
          'https://picsum.photos/seed/avatar_ks2/100/100',
      viewCount: 43100,
      likeCount: 3210,
      durationSeconds: 1800,
      tags: ['Android', 'Jetpack', 'Kotlin'],
      hotScore: 68.7,
    ),
    const VideoItem(
      id: 'kuaishou_003',
      platformId: 'kuaishou',
      title: 'Python后端与移动端API设计最佳实践',
      description: 'RESTful API 设计规范、认证鉴权、接口文档生成，Flutter端优雅调用',
      thumbnailUrl:
          'https://picsum.photos/seed/kuaishou_003/480/360',
      videoUrl: 'https://www.kuaishou.com/video/003',
      author: '程序员老李',
      authorAvatar:
          'https://picsum.photos/seed/avatar_ks3/100/100',
      viewCount: 32400,
      likeCount: 2870,
      durationSeconds: 1440,
      tags: ['Python', 'API', '后端'],
      hotScore: 58.9,
    ),
    const VideoItem(
      id: 'kuaishou_004',
      platformId: 'kuaishou',
      title: 'Flutter动画系统深入解析',
      description: 'AnimationController、Tween、Hero、隐式动画、自定义Painter动画全解析',
      thumbnailUrl:
          'https://picsum.photos/seed/kuaishou_004/480/360',
      videoUrl: 'https://www.kuaishou.com/video/004',
      author: '阿杰教编程',
      authorAvatar:
          'https://picsum.photos/seed/avatar_ks4/100/100',
      viewCount: 21500,
      likeCount: 1980,
      durationSeconds: 1680,
      tags: ['Flutter', '动画', '高级'],
      hotScore: 52.3,
    ),
    const VideoItem(
      id: 'kuaishou_005',
      platformId: 'kuaishou',
      title: '移动端性能优化实战指南',
      description: '内存泄漏检测、布局层级优化、图片缓存策略、启动速度优化，让你的App飞起来',
      thumbnailUrl:
          'https://picsum.photos/seed/kuaishou_005/480/360',
      videoUrl: 'https://www.kuaishou.com/video/005',
      author: '数码小新',
      authorAvatar:
          'https://picsum.photos/seed/avatar_ks5/100/100',
      viewCount: 78300,
      likeCount: 6540,
      durationSeconds: 1200,
      tags: ['性能优化', '移动端', 'Android', 'iOS'],
      hotScore: 81.2,
    ),
    const VideoItem(
      id: 'kuaishou_006',
      platformId: 'kuaishou',
      title: 'React Native vs Flutter 2025全方位对比',
      description: '从开发效率、性能、生态、学习成本多维度对比两大跨平台框架',
      thumbnailUrl:
          'https://picsum.photos/seed/kuaishou_006/480/360',
      videoUrl: 'https://www.kuaishou.com/video/006',
      author: '编程大明白',
      authorAvatar:
          'https://picsum.photos/seed/avatar_ks6/100/100',
      viewCount: 55200,
      likeCount: 4320,
      durationSeconds: 960,
      tags: ['React Native', 'Flutter', '对比'],
      hotScore: 76.8,
    ),
    const VideoItem(
      id: 'kuaishou_007',
      platformId: 'kuaishou',
      title: '从零搭建个人博客App（Flutter全栈）',
      description: 'Flutter + Supabase 全栈开发个人博客系统，涵盖文章管理、评论、用户系统',
      thumbnailUrl:
          'https://picsum.photos/seed/kuaishou_007/480/360',
      videoUrl: 'https://www.kuaishou.com/video/007',
      author: '老张讲代码',
      authorAvatar:
          'https://picsum.photos/seed/avatar_ks7/100/100',
      viewCount: 92300,
      likeCount: 8120,
      durationSeconds: 2400,
      tags: ['Flutter', '全栈', '博客'],
      hotScore: 85.6,
    ),
    const VideoItem(
      id: 'kuaishou_008',
      platformId: 'kuaishou',
      title: '移动应用安全防护最佳实践',
      description: '代码混淆、数据加密、HTTPS证书绑定、防逆向调试、隐私合规检测',
      thumbnailUrl:
          'https://picsum.photos/seed/kuaishou_008/480/360',
      videoUrl: 'https://www.kuaishou.com/video/008',
      author: '小C编程日记',
      authorAvatar:
          'https://picsum.photos/seed/avatar_ks8/100/100',
      viewCount: 15600,
      likeCount: 1340,
      durationSeconds: 1080,
      tags: ['安全', '加密', '移动开发'],
      hotScore: 42.1,
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
      swallowDebug(e, tag: 'KuaishouProvider.getVideoDetail', stack: st);
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
