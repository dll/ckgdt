import '../models/hot_video_model.dart';
import 'database_helper.dart';

class HotVideoDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ── 视频 CRUD ──

  Future<int> addVideo({
    required String userId,
    required String platform,
    required String videoUrl,
    required String title,
    String? thumbnailUrl,
    String? description,
    String? viewCount,
    String? duration,
    String? source,
    String? publishDate,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('hot_videos', {
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
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateVideo({
    required int id,
    required String userId,
    String? platform,
    String? videoUrl,
    String? title,
    String? thumbnailUrl,
    String? description,
    String? viewCount,
    String? duration,
    String? source,
    String? publishDate,
  }) async {
    final db = await _dbHelper.database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (platform != null) updates['platform'] = platform;
    if (videoUrl != null) updates['video_url'] = videoUrl;
    if (title != null) updates['title'] = title;
    if (thumbnailUrl != null) updates['thumbnail_url'] = thumbnailUrl;
    if (description != null) updates['description'] = description;
    if (viewCount != null) updates['view_count'] = viewCount;
    if (duration != null) updates['duration'] = duration;
    if (source != null) updates['source'] = source;
    if (publishDate != null) updates['publish_date'] = publishDate;
    await db.update(
      'hot_videos',
      updates,
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<void> deleteVideo(int id) async {
    final db = await _dbHelper.database;
    await db.delete('hot_videos', where: 'id = ?', whereArgs: [id]);
  }

  Future<HotVideoModel?> getVideo(int id, {String? userId}) async {
    final db = await _dbHelper.database;
    final rows = await db.query('hot_videos',
        where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final model = HotVideoModel.fromMap(rows.first);
    if (userId != null) {
      final isFav = await isFavorited(userId, id);
      final favCount = await getFavoriteCount(id);
      return model.copyWith(isFavorited: isFav, favoriteCount: favCount);
    }
    return model;
  }

  Future<List<HotVideoModel>> getVideos({
    String? userId,
    String? platform,
    String? sortBy,
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    final db = await _dbHelper.database;

    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (platform != null && platform != 'all') {
      where.add('platform = ?');
      whereArgs.add(platform);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      where.add('(title LIKE ? OR source LIKE ?)');
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }

    String? orderBy;
    switch (sortBy) {
      case 'most_viewed':
        orderBy = 'view_count DESC';
        break;
      case 'hottest':
        orderBy = 'updated_at DESC';
        break;
      case 'latest':
      default:
        orderBy = 'created_at DESC';
        break;
    }

    final rows = await db.query(
      'hot_videos',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    final result = <HotVideoModel>[];
    for (final row in rows) {
      final video = HotVideoModel.fromMap(row);
      if (userId != null) {
        final isFav = await isFavorited(userId, video.id!);
        final favCount = await getFavoriteCount(video.id!);
        result.add(video.copyWith(isFavorited: isFav, favoriteCount: favCount));
      } else {
        result.add(video);
      }
    }
    return result;
  }

  Future<int> getVideoCount({String? platform, String? searchQuery}) async {
    final db = await _dbHelper.database;

    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (platform != null && platform != 'all') {
      where.add('platform = ?');
      whereArgs.add(platform);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      where.add('(title LIKE ? OR source LIKE ?)');
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM hot_videos${where.isNotEmpty ? ' WHERE ${where.join(' AND ')}' : ''}',
      whereArgs.isEmpty ? null : whereArgs,
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ── 收藏 ──

  Future<int> addFavorite(String userId, int videoId) async {
    final db = await _dbHelper.database;
    final existing = await db.query(
      'hot_video_favorites',
      where: 'user_id = ? AND video_id = ?',
      whereArgs: [userId, videoId],
    );
    if (existing.isNotEmpty) {
      return (existing.first['id'] as int?) ?? 0;
    }
    return await db.insert('hot_video_favorites', {
      'user_id': userId,
      'video_id': videoId,
      'favorite_time': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeFavorite(String userId, int videoId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'hot_video_favorites',
      where: 'user_id = ? AND video_id = ?',
      whereArgs: [userId, videoId],
    );
  }

  Future<bool> isFavorited(String userId, int videoId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'hot_video_favorites',
      where: 'user_id = ? AND video_id = ?',
      whereArgs: [userId, videoId],
    );
    return result.isNotEmpty;
  }

  Future<List<HotVideoModel>> getFavoritedVideos(String userId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT hv.*, 1 as is_favorited,
        (SELECT COUNT(*) FROM hot_video_favorites hvf WHERE hvf.video_id = hv.id) as favorite_count
      FROM hot_videos hv
      INNER JOIN hot_video_favorites hvf ON hv.id = hvf.video_id AND hvf.user_id = ?
      ORDER BY hvf.favorite_time DESC
    ''', [userId]);
    return rows.map((r) => HotVideoModel.fromMap(r)).toList();
  }

  Future<int> getFavoriteCount(int videoId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM hot_video_favorites WHERE video_id = ?',
      [videoId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> incrementViewCount(int videoId) async {
    final db = await _dbHelper.database;
    await db.rawUpdate(
      'UPDATE hot_videos SET view_count = CAST(COALESCE(view_count, \'0\') AS INTEGER) + 1 WHERE id = ?',
      [videoId],
    );
  }
}
