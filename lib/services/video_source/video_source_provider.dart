abstract class VideoSourceProvider {
  String get platformId;

  String get displayName;

  dynamic get icon;

  int get themeColor;

  bool get enabled;

  Future<List<VideoItem>> getRecommendedVideos({
    int page = 1,
    int pageSize = 20,
    String? keyword,
  });

  Future<VideoItem?> getVideoDetail(String videoId);
}

class VideoItem {
  final String id;
  final String platformId;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? videoUrl;
  final String? author;
  final String? authorAvatar;
  final int viewCount;
  final int likeCount;
  final int durationSeconds;
  final String? publishDate;
  final List<String> tags;
  final double hotScore;

  const VideoItem({
    required this.id,
    required this.platformId,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.videoUrl,
    this.author,
    this.authorAvatar,
    this.viewCount = 0,
    this.likeCount = 0,
    this.durationSeconds = 0,
    this.publishDate,
    this.tags = const [],
    this.hotScore = 0,
  });

  String get formattedDuration {
    final min = durationSeconds ~/ 60;
    final sec = durationSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String get formattedViews {
    if (viewCount >= 10000) {
      return '${(viewCount / 10000).toStringAsFixed(1)}万';
    }
    return viewCount.toString();
  }
}
