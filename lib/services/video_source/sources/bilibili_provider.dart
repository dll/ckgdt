import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/error_handler.dart';
import '../../../data/local/database_helper.dart';
import '../video_source_provider.dart';

class BilibiliProvider implements VideoSourceProvider {
  @override
  String get platformId => 'bilibili';

  @override
  String get displayName => 'B站';

  @override
  dynamic get icon => Icons.videocam;

  @override
  int get themeColor => 0xFFFB7299;

  @override
  bool get enabled => true;

  @override
  Future<List<VideoItem>> getRecommendedVideos({
    int page = 1,
    int pageSize = 20,
    String? keyword,
  }) async {
    try {
      final query = keyword ?? 'Flutter 移动开发';
      final url = Uri.parse(
        'https://api.bilibili.com/x/web-interface/search/type?'
        'search_type=video&keyword=${Uri.encodeComponent(query)}&page=$page',
      );
      final response = await http.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['data']?['result'];
        if (result is List) {
          return result.take(pageSize).map((item) {
            final aid = item['aid'];
            final bvid = item['bvid'];
            return VideoItem(
              id: 'bili_${aid ?? bvid}',
              platformId: 'bilibili',
              title: item['title']
                      ?.toString()
                      .replaceAll(RegExp(r'<[^>]*>'), '') ??
                  '',
              description: item['description'] as String?,
              thumbnailUrl: item['pic'] as String?,
              videoUrl:
                  'https://www.bilibili.com/video/${bvid ?? aid}',
              author: item['author'] as String?,
              viewCount: (item['play'] as num?)?.toInt() ??
                  (item['view'] as num?)?.toInt() ??
                  0,
              likeCount: (item['like'] as num?)?.toInt() ?? 0,
              durationSeconds: _parseDuration(item['duration'] as String?),
              publishDate: item['pubdate']?.toString(),
              tags: item['tag']?.toString().split(',') ?? [],
              hotScore:
                  ((item['play'] as num?)?.toDouble() ?? 0) / 10000,
            );
          }).toList();
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'BilibiliProvider.getRecommendedVideos', stack: st);
    }
    return _fallbackToLocal(keyword);
  }

  Future<List<VideoItem>> _fallbackToLocal(String? keyword) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final whereParts = <String>['file_type = ?'];
      final whereArgs = <dynamic>['video'];

      try {
        whereParts.add('platform_source = ?');
        whereArgs.add('bilibili');
      } catch (e) {
        swallow(e, tag: 'BilibiliProvider._fallbackToLocal');
      }

      if (keyword != null && keyword.isNotEmpty) {
        whereParts.add(
            '(file_name LIKE ? OR description LIKE ? OR chapter LIKE ?)');
        final like = '%$keyword%';
        whereArgs.addAll([like, like, like]);
      }

      final result = await db.query(
        'resource_files',
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'chapter',
        limit: 20,
      );

      return result.asMap().entries.map((entry) {
        final i = entry.key;
        final row = entry.value;
        return VideoItem(
          id: (row['id'] ?? '').toString(),
          platformId: platformId,
          title: row['file_name'] as String? ?? '视频 ${i + 1}',
          description: row['description'] as String?,
          thumbnailUrl: row['thumbnail'] as String?,
          videoUrl: row['file_path'] as String?,
          author: row['author'] as String?,
          authorAvatar: null,
          viewCount: (row['view_count'] as num?)?.toInt() ?? 0,
          likeCount: 0,
          durationSeconds: (row['duration'] as num?)?.toInt() ?? 0,
          publishDate: null,
          tags: [],
          hotScore: (row['hot_score'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
    } catch (e, st) {
      swallowDebug(e, tag: 'BilibiliProvider._fallbackToLocal', stack: st);
      return [];
    }
  }

  int _parseDuration(String? dur) {
    if (dur == null) return 0;
    final parts = dur.split(':');
    int seg(int i) => i < parts.length ? (int.tryParse(parts[i].trim()) ?? 0) : 0;
    if (parts.length == 2) {
      return seg(0) * 60 + seg(1);
    }
    if (parts.length == 3) {
      return seg(0) * 3600 + seg(1) * 60 + seg(2);
    }
    return int.tryParse(dur) ?? 0;
  }

  @override
  Future<VideoItem?> getVideoDetail(String videoId) async {
    return null;
  }
}
