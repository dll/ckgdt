import 'package:shared_preferences/shared_preferences.dart';
import 'video_source_provider.dart';
import 'sources/bilibili_provider.dart';
import 'sources/douyin_provider.dart';
import 'sources/kuaishou_provider.dart';
import 'sources/xiaohongshu_provider.dart';
import 'sources/youtube_provider.dart';
import 'sources/twitter_provider.dart';

class VideoSourceManager {
  VideoSourceManager._();

  static final VideoSourceManager instance = VideoSourceManager._();

  static const String _prefsPrefix = 'video_source_enabled_';

  final Map<String, VideoSourceProvider> _providers = {};

  void registerDefaults() {
    final providers = <VideoSourceProvider>[
      BilibiliProvider(),
      DouyinProvider(),
      KuaishouProvider(),
      XiaohongshuProvider(),
      YoutubeProvider(),
      TwitterProvider(),
    ];
    for (final p in providers) {
      _providers[p.platformId] = p;
    }
  }

  void registerProvider(VideoSourceProvider provider) {
    _providers[provider.platformId] = provider;
  }

  List<VideoSourceProvider> getEnabledProviders() {
    return _providers.values.where((p) => p.enabled).toList();
  }

  VideoSourceProvider? getProvider(String platformId) {
    return _providers[platformId];
  }

  List<VideoSourceProvider> getAllProviders() {
    return _providers.values.toList();
  }

  Future<void> setProviderEnabled(String platformId, bool enabled) async {
    final provider = _providers[platformId];
    if (provider == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefsPrefix$platformId', enabled);
  }

  Future<bool> loadProviderEnabled(String platformId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefsPrefix$platformId') ?? true;
  }

  Future<List<VideoItem>> getVideosFromAllEnabled({
    int page = 1,
    int pageSize = 20,
    String? keyword,
  }) async {
    final results = <VideoItem>[];
    final enabled = getEnabledProviders();
    for (final provider in enabled) {
      final videos = await provider.getRecommendedVideos(
        page: page,
        pageSize: pageSize,
        keyword: keyword,
      );
      results.addAll(videos);
    }
    return results;
  }

  Future<List<VideoItem>> getVideosFrom(
    String platformId, {
    int page = 1,
    int pageSize = 20,
    String? keyword,
  }) async {
    final provider = _providers[platformId];
    if (provider == null) return [];
    return provider.getRecommendedVideos(
      page: page,
      pageSize: pageSize,
      keyword: keyword,
    );
  }
}
