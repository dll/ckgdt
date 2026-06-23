import 'package:flutter/material.dart';
import '../../../core/error_handler.dart';
import '../video_source_provider.dart';

class XiaohongshuProvider implements VideoSourceProvider {
  @override
  String get platformId => 'xiaohongshu';

  @override
  String get displayName => '小红书';

  @override
  dynamic get icon => Icons.explore;

  @override
  int get themeColor => 0xFFFF2442;

  @override
  bool get enabled => false;

  final List<VideoItem> _mockVideos = [
    const VideoItem(
      id: 'xhs_001',
      platformId: 'xiaohongshu',
      title: '自学编程一年｜从零到独立开发App上线',
      description: '分享我自学编程一年的心路历程，从选择方向到项目实践，最终成功上线自己的第一个App',
      thumbnailUrl:
          'https://picsum.photos/seed/xhs_001/480/360',
      videoUrl: 'https://www.xiaohongshu.com/video/001',
      author: '编程小橘',
      authorAvatar:
          'https://picsum.photos/seed/avatar_xhs1/100/100',
      viewCount: 235000,
      likeCount: 18500,
      durationSeconds: 900,
      tags: ['自学编程', '经验分享', 'App开发'],
      hotScore: 95.2,
    ),
    const VideoItem(
      id: 'xhs_002',
      platformId: 'xiaohongshu',
      title: '我的Flutter桌面端开发环境搭建',
      description: '手把手教你配置 Flutter 桌面开发环境，IDE 插件推荐、调试技巧、热重载实战',
      thumbnailUrl:
          'https://picsum.photos/seed/xhs_002/480/360',
      videoUrl: 'https://www.xiaohongshu.com/video/002',
      author: '小鹿的编程笔记',
      authorAvatar:
          'https://picsum.photos/seed/avatar_xhs2/100/100',
      viewCount: 123000,
      likeCount: 9870,
      durationSeconds: 720,
      tags: ['Flutter', '桌面端', '开发环境'],
      hotScore: 88.4,
    ),
    const VideoItem(
      id: 'xhs_003',
      platformId: 'xiaohongshu',
      title: '程序员必备的8款效率工具推荐',
      description: '提升开发效率的神器：截图工具、API调试、笔记管理、代码片段管理等实用工具',
      thumbnailUrl:
          'https://picsum.photos/seed/xhs_003/480/360',
      videoUrl: 'https://www.xiaohongshu.com/video/003',
      author: '码农日记',
      authorAvatar:
          'https://picsum.photos/seed/avatar_xhs3/100/100',
      viewCount: 187000,
      likeCount: 15200,
      durationSeconds: 480,
      tags: ['效率工具', '程序员', '推荐'],
      hotScore: 91.7,
    ),
    const VideoItem(
      id: 'xhs_004',
      platformId: 'xiaohongshu',
      title: '零基础转行IT｜学习路线全分享',
      description: '从机械专业转行到移动开发，我的完整学习路线图：编程基础→Android→Flutter→项目实战',
      thumbnailUrl:
          'https://picsum.photos/seed/xhs_004/480/360',
      videoUrl: 'https://www.xiaohongshu.com/video/004',
      author: 'IT小葵',
      authorAvatar:
          'https://picsum.photos/seed/avatar_xhs4/100/100',
      viewCount: 452000,
      likeCount: 32100,
      durationSeconds: 1140,
      tags: ['转行IT', '学习路线', '零基础'],
      hotScore: 98.5,
    ),
    const VideoItem(
      id: 'xhs_005',
      platformId: 'xiaohongshu',
      title: '移动开发面试高频100题解析',
      description: '大厂移动端面试高频题汇总：四大组件、消息机制、性能优化、算法与数据结构',
      thumbnailUrl:
          'https://picsum.photos/seed/xhs_005/480/360',
      videoUrl: 'https://www.xiaohongshu.com/video/005',
      author: '程序媛小美',
      authorAvatar:
          'https://picsum.photos/seed/avatar_xhs5/100/100',
      viewCount: 98200,
      likeCount: 7650,
      durationSeconds: 2100,
      tags: ['面试', '移动开发', '题库'],
      hotScore: 84.3,
    ),
    const VideoItem(
      id: 'xhs_006',
      platformId: 'xiaohongshu',
      title: '用Flutter写了一个番茄钟App｜附源码',
      description: 'Flutter 番茄钟应用开发全过程：UI设计、计时逻辑、通知提醒、数据持久化',
      thumbnailUrl:
          'https://picsum.photos/seed/xhs_006/480/360',
      videoUrl: 'https://www.xiaohongshu.com/video/006',
      author: '小A学编程',
      authorAvatar:
          'https://picsum.photos/seed/avatar_xhs6/100/100',
      viewCount: 64500,
      likeCount: 5230,
      durationSeconds: 1500,
      tags: ['Flutter', '番茄钟', '开源'],
      hotScore: 72.6,
    ),
    const VideoItem(
      id: 'xhs_007',
      platformId: 'xiaohongshu',
      title: '产品经理如何与开发团队高效沟通',
      description: '从需求文档撰写到PRD评审，产品经理与开发团队协作的最佳实践与沟通技巧',
      thumbnailUrl:
          'https://picsum.photos/seed/xhs_007/480/360',
      videoUrl: 'https://www.xiaohongshu.com/video/007',
      author: '产品经理小陈',
      authorAvatar:
          'https://picsum.photos/seed/avatar_xhs7/100/100',
      viewCount: 151000,
      likeCount: 12800,
      durationSeconds: 660,
      tags: ['产品经理', '沟通', '团队协作'],
      hotScore: 87.9,
    ),
    const VideoItem(
      id: 'xhs_008',
      platformId: 'xiaohongshu',
      title: '2025年移动开发趋势与技术展望',
      description: '跨平台框架演进、AI辅助编程、鸿蒙生态崛起、小程序云开发——未来方向全面解读',
      thumbnailUrl:
          'https://picsum.photos/seed/xhs_008/480/360',
      videoUrl: 'https://www.xiaohongshu.com/video/008',
      author: '技术小林',
      authorAvatar:
          'https://picsum.photos/seed/avatar_xhs8/100/100',
      viewCount: 82600,
      likeCount: 6540,
      durationSeconds: 840,
      tags: ['趋势', '移动开发', '2025'],
      hotScore: 79.8,
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
      swallowDebug(e, tag: 'XiaohongshuProvider.getVideoDetail', stack: st);
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
