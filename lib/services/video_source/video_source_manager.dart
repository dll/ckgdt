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

  /// 用户开关的内存缓存（platformId → 是否启用）。null 表示未加载。
  /// [loadEnabledPrefs] 启动时灌一次，[setProviderEnabled] 写时同步更新。
  Map<String, bool>? _enabledCache;

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

  /// 从 SharedPreferences 加载全部平台开关到内存缓存。app 启动时调一次。
  Future<void> loadEnabledPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabledCache = {
      for (final id in _providers.keys)
        id: prefs.getBool('$_prefsPrefix$id') ?? true,
    };
  }

  /// 平台是否对用户可用：既要 provider 本身可用（const enabled），
  /// 又要用户未在设置里关掉（prefs，默认开）。缓存未加载时只看 provider.enabled。
  bool _isUserEnabled(VideoSourceProvider p) {
    if (!p.enabled) return false;
    return _enabledCache?[p.platformId] ?? true;
  }

  List<VideoSourceProvider> getEnabledProviders() {
    return _providers.values.where(_isUserEnabled).toList();
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
    // 同步内存缓存，使 getEnabledProviders 立即生效
    (_enabledCache ??= {})[platformId] = enabled;
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
