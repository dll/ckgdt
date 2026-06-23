import 'package:flutter/material.dart';
import '../../../core/error_handler.dart';
import '../video_source_provider.dart';

class YoutubeProvider implements VideoSourceProvider {
  @override
  String get platformId => 'youtube';

  @override
  String get displayName => 'YouTube';

  @override
  dynamic get icon => Icons.play_circle_fill;

  @override
  int get themeColor => 0xFFFF0000;

  @override
  bool get enabled => false;

  final List<VideoItem> _mockVideos = [
    const VideoItem(
      id: 'yt_001',
      platformId: 'youtube',
      title: 'Flutter Masterclass 2025 — Full Course for Beginners',
      description:
          'Complete Flutter course covering Dart basics, Widget tree, state management, navigation, and building production-ready apps.',
      thumbnailUrl: 'https://picsum.photos/seed/yt_001/480/360',
      videoUrl: 'https://www.youtube.com/watch?v=yt001',
      author: 'Flutter Official',
      authorAvatar: 'https://picsum.photos/seed/avatar_yt1/100/100',
      viewCount: 1250000,
      likeCount: 89000,
      durationSeconds: 4500,
      tags: ['Flutter', 'Beginner', 'Tutorial'],
      hotScore: 97.8,
    ),
    const VideoItem(
      id: 'yt_002',
      platformId: 'youtube',
      title: 'The Complete Dart Language Guide for Flutter',
      description:
          'Deep dive into Dart programming language: null safety, generics, async/await, isolates, and metaprogramming.',
      thumbnailUrl: 'https://picsum.photos/seed/yt_002/480/360',
      videoUrl: 'https://www.youtube.com/watch?v=yt002',
      author: 'TechWithTim',
      authorAvatar: 'https://picsum.photos/seed/avatar_yt2/100/100',
      viewCount: 890000,
      likeCount: 62000,
      durationSeconds: 3600,
      tags: ['Dart', 'Programming', 'Flutter'],
      hotScore: 92.4,
    ),
    const VideoItem(
      id: 'yt_003',
      platformId: 'youtube',
      title: 'Build a Full Stack App with Flutter & Firebase',
      description:
          'Step-by-step tutorial building a full-stack mobile app using Flutter frontend and Firebase backend authentication, Firestore, storage.',
      thumbnailUrl: 'https://picsum.photos/seed/yt_003/480/360',
      videoUrl: 'https://www.youtube.com/watch?v=yt003',
      author: 'Fireship',
      authorAvatar: 'https://picsum.photos/seed/avatar_yt3/100/100',
      viewCount: 2100000,
      likeCount: 156000,
      durationSeconds: 2400,
      tags: ['Flutter', 'Firebase', 'Full Stack'],
      hotScore: 99.1,
    ),
    const VideoItem(
      id: 'yt_004',
      platformId: 'youtube',
      title: 'Android Development for Complete Beginners 2025',
      description:
          'Start your Android journey here! Learn Kotlin basics, Android Studio, layouts, activities, and build your first app.',
      thumbnailUrl: 'https://picsum.photos/seed/yt_004/480/360',
      videoUrl: 'https://www.youtube.com/watch?v=yt004',
      author: 'Google Developers',
      authorAvatar: 'https://picsum.photos/seed/avatar_yt4/100/100',
      viewCount: 3400000,
      likeCount: 245000,
      durationSeconds: 5400,
      tags: ['Android', 'Kotlin', 'Beginner'],
      hotScore: 99.8,
    ),
    const VideoItem(
      id: 'yt_005',
      platformId: 'youtube',
      title: 'iOS SwiftUI Advanced Patterns & Architecture',
      description:
          'Advanced SwiftUI techniques: MVVM architecture, dependency injection, complex animations, and performance optimization.',
      thumbnailUrl: 'https://picsum.photos/seed/yt_005/480/360',
      videoUrl: 'https://www.youtube.com/watch?v=yt005',
      author: 'CS Dojo',
      authorAvatar: 'https://picsum.photos/seed/avatar_yt5/100/100',
      viewCount: 670000,
      likeCount: 48000,
      durationSeconds: 2800,
      tags: ['iOS', 'SwiftUI', 'Advanced'],
      hotScore: 88.5,
    ),
    const VideoItem(
      id: 'yt_006',
      platformId: 'youtube',
      title: 'Flutter Animations — Everything You Need to Know',
      description:
          'Master Flutter animations: implicit animations, explicit animations, custom painters, hero animations, and physics-based motion.',
      thumbnailUrl: 'https://picsum.photos/seed/yt_006/480/360',
      videoUrl: 'https://www.youtube.com/watch?v=yt006',
      author: 'The Net Ninja',
      authorAvatar: 'https://picsum.photos/seed/avatar_yt6/100/100',
      viewCount: 450000,
      likeCount: 34000,
      durationSeconds: 3200,
      tags: ['Flutter', 'Animations', 'UI'],
      hotScore: 85.3,
    ),
    const VideoItem(
      id: 'yt_007',
      platformId: 'youtube',
      title: 'Microservices Architecture for Mobile Backend',
      description:
          'Designing scalable microservices architecture for mobile applications: API gateway, service discovery, message queues.',
      thumbnailUrl: 'https://picsum.photos/seed/yt_007/480/360',
      videoUrl: 'https://www.youtube.com/watch?v=yt007',
      author: 'Academind',
      authorAvatar: 'https://picsum.photos/seed/avatar_yt7/100/100',
      viewCount: 520000,
      likeCount: 39000,
      durationSeconds: 3900,
      tags: ['Backend', 'Microservices', 'Architecture'],
      hotScore: 86.7,
    ),
    const VideoItem(
      id: 'yt_008',
      platformId: 'youtube',
      title: 'React Native vs Flutter — Which One to Choose in 2025?',
      description:
          'In-depth comparison of React Native and Flutter: performance, developer experience, ecosystem, job market, and learning curve.',
      thumbnailUrl: 'https://picsum.photos/seed/yt_008/480/360',
      videoUrl: 'https://www.youtube.com/watch?v=yt008',
      author: 'Traversy Media',
      authorAvatar: 'https://picsum.photos/seed/avatar_yt8/100/100',
      viewCount: 780000,
      likeCount: 56000,
      durationSeconds: 1800,
      tags: ['React Native', 'Flutter', 'Comparison'],
      hotScore: 90.2,
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
      swallowDebug(e, tag: 'YoutubeProvider.getVideoDetail', stack: st);
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
