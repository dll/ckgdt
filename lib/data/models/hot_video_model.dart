/// 热门视频数据模型
class HotVideoModel {
  final int? id;
  final String userId;
  final String platform;
  final String videoUrl;
  final String title;
  final String? thumbnailUrl;
  final String? description;
  final String? viewCount;
  final String? duration;
  final String? source;
  final String? publishDate;
  final String createdAt;
  final String? updatedAt;

  final bool isFavorited;
  final int favoriteCount;

  HotVideoModel({
    this.id,
    required this.userId,
    required this.platform,
    required this.videoUrl,
    required this.title,
    this.thumbnailUrl,
    this.description,
    this.viewCount,
    this.duration,
    this.source,
    this.publishDate,
    required this.createdAt,
    this.updatedAt,
    this.isFavorited = false,
    this.favoriteCount = 0,
  });

  factory HotVideoModel.fromMap(Map<String, dynamic> map) {
    return HotVideoModel(
      id: map['id'] as int?,
      userId: map['user_id']?.toString() ?? '',
      platform: map['platform']?.toString() ?? 'other',
      videoUrl: map['video_url']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      thumbnailUrl: map['thumbnail_url']?.toString(),
      description: map['description']?.toString(),
      viewCount: map['view_count']?.toString(),
      duration: map['duration']?.toString(),
      source: map['source']?.toString(),
      publishDate: map['publish_date']?.toString(),
      createdAt: map['created_at']?.toString() ?? '',
      updatedAt: map['updated_at']?.toString(),
      isFavorited: map['is_favorited'] != null
          ? (map['is_favorited'] as int? ?? 0) == 1
          : false,
      favoriteCount: map['favorite_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'platform': platform,
      'video_url': videoUrl,
      'title': title,
      'thumbnail_url': thumbnailUrl,
      'description': description,
      'view_count': viewCount,
      'duration': duration,
      'source': source,
      'publish_date': publishDate,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  HotVideoModel copyWith({
    int? id,
    String? userId,
    String? platform,
    String? videoUrl,
    String? title,
    String? thumbnailUrl,
    String? description,
    String? viewCount,
    String? duration,
    String? source,
    String? publishDate,
    String? createdAt,
    String? updatedAt,
    bool? isFavorited,
    int? favoriteCount,
  }) {
    return HotVideoModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      platform: platform ?? this.platform,
      videoUrl: videoUrl ?? this.videoUrl,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      description: description ?? this.description,
      viewCount: viewCount ?? this.viewCount,
      duration: duration ?? this.duration,
      source: source ?? this.source,
      publishDate: publishDate ?? this.publishDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorited: isFavorited ?? this.isFavorited,
      favoriteCount: favoriteCount ?? this.favoriteCount,
    );
  }
}
