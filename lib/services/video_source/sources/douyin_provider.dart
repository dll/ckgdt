import 'package:flutter/material.dart';
import '../../../core/error_handler.dart';
import '../video_source_provider.dart';

class DouyinProvider implements VideoSourceProvider {
  @override
  String get platformId => 'douyin';

  @override
  String get displayName => '抖音';

  @override
  dynamic get icon => Icons.music_video;

  @override
  int get themeColor => 0xFF000000;

  @override
  bool get enabled => false;

  final List<VideoItem> _mockVideos = [
    const VideoItem(
      id: 'douyin_001',
      platformId: 'douyin',
      title: 'Flutter 3.x Widget 详解 — 从基础到进阶',
      description: '一套视频带你吃透 Flutter 所有核心 Widget，含 Container、Row、Column、Stack 等布局组件实战',
      thumbnailUrl:
          'https://picsum.photos/seed/douyin_001/480/360',
      videoUrl: 'https://www.douyin.com/video/001',
      author: '移动开发小助手',
      authorAvatar:
          'https://picsum.photos/seed/avatar_dy1/100/100',
      viewCount: 23400,
      likeCount: 1850,
      durationSeconds: 780,
      tags: ['Flutter', 'Widget', '移动开发'],
      hotScore: 67.3,
    ),
    const VideoItem(
      id: 'douyin_002',
      platformId: 'douyin',
      title: '30天搞定Android开发 — 零基础入门路线',
      description: '零基础学Android，30天从环境搭建到独立开发简单App，每日一练循序渐进',
      thumbnailUrl:
          'https://picsum.photos/seed/douyin_002/480/360',
      videoUrl: 'https://www.douyin.com/video/002',
      author: '码农阿飞',
      authorAvatar:
          'https://picsum.photos/seed/avatar_dy2/100/100',
      viewCount: 156000,
      likeCount: 12300,
      durationSeconds: 960,
      tags: ['Android', '入门', 'Java'],
      hotScore: 92.5,
    ),
    const VideoItem(
      id: 'douyin_003',
      platformId: 'douyin',
      title: '微信小程序从0到1上线全流程',
      description: '从注册账号到提交审核，手把手带你完成第一个微信小程序的上线发布',
      thumbnailUrl:
          'https://picsum.photos/seed/douyin_003/480/360',
      videoUrl: 'https://www.douyin.com/video/003',
      author: '前端小姐姐',
      authorAvatar:
          'https://picsum.photos/seed/avatar_dy3/100/100',
      viewCount: 89400,
      likeCount: 7650,
      durationSeconds: 1320,
      tags: ['小程序', '微信', '前端'],
      hotScore: 78.2,
    ),
    const VideoItem(
      id: 'douyin_004',
      platformId: 'douyin',
      title: 'Dart语言核心语法速通 — 10分钟上手',
      description: '用最短时间掌握 Dart 语言核心特性：异步编程、空安全、集合操作、类与混入',
      thumbnailUrl:
          'https://picsum.photos/seed/douyin_004/480/360',
      videoUrl: 'https://www.douyin.com/video/004',
      author: '编程小王子',
      authorAvatar:
          'https://picsum.photos/seed/avatar_dy4/100/100',
      viewCount: 34100,
      likeCount: 4200,
      durationSeconds: 600,
      tags: ['Dart', '语法', 'Flutter'],
      hotScore: 55.8,
    ),
    const VideoItem(
      id: 'douyin_005',
      platformId: 'douyin',
      title: 'iOS SwiftUI实战 — 仿写知乎日报App',
      description: '用 SwiftUI 完整复刻知乎日报，涵盖列表、详情、网络请求与本地缓存',
      thumbnailUrl:
          'https://picsum.photos/seed/douyin_005/480/360',
      videoUrl: 'https://www.douyin.com/video/005',
      author: '小林coding',
      authorAvatar:
          'https://picsum.photos/seed/avatar_dy5/100/100',
      viewCount: 52100,
      likeCount: 3890,
      durationSeconds: 1560,
      tags: ['iOS', 'SwiftUI', 'Swift'],
      hotScore: 71.4,
    ),
    const VideoItem(
      id: 'douyin_006',
      platformId: 'douyin',
      title: '鸿蒙HarmonyOS应用开发快速入门',
      description: '华为鸿蒙应用开发环境搭建 + ArkUI 基础组件 + 页面路由，30分钟上手',
      thumbnailUrl:
          'https://picsum.photos/seed/douyin_006/480/360',
      videoUrl: 'https://www.douyin.com/video/006',
      author: '李老师讲编程',
      authorAvatar:
          'https://picsum.photos/seed/avatar_dy6/100/100',
      viewCount: 121000,
      likeCount: 9850,
      durationSeconds: 1800,
      tags: ['鸿蒙', 'HarmonyOS', 'ArkUI'],
      hotScore: 88.9,
    ),
    const VideoItem(
      id: 'douyin_007',
      platformId: 'douyin',
      title: 'Flutter状态管理Provider vs Riverpod对比',
      description: '深入分析 Flutter 两大状态管理方案的设计理念、使用场景与性能差异',
      thumbnailUrl:
          'https://picsum.photos/seed/douyin_007/480/360',
      videoUrl: 'https://www.douyin.com/video/007',
      author: '程序员小张',
      authorAvatar:
          'https://picsum.photos/seed/avatar_dy7/100/100',
      viewCount: 18200,
      likeCount: 2150,
      durationSeconds: 1140,
      tags: ['Flutter', '状态管理', 'Provider', 'Riverpod'],
      hotScore: 45.6,
    ),
    const VideoItem(
      id: 'douyin_008',
      platformId: 'douyin',
      title: '移动端UI设计规范与适配技巧',
      description: '移动端UI设计核心规范：布局适配、图片切图、字体缩放、暗黑模式适配',
      thumbnailUrl:
          'https://picsum.photos/seed/douyin_008/480/360',
      videoUrl: 'https://www.douyin.com/video/008',
      author: '小鹿编程',
      authorAvatar:
          'https://picsum.photos/seed/avatar_dy8/100/100',
      viewCount: 46200,
      likeCount: 5340,
      durationSeconds: 900,
      tags: ['UI设计', '适配', '移动端'],
      hotScore: 62.1,
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
      swallowDebug(e, tag: 'DouyinProvider.getVideoDetail', stack: st);
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
