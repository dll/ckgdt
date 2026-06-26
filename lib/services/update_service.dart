import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/build_info.dart';
import '../core/error_handler.dart';

class UpdateInfo {
  final String version;
  final String tagName;
  final String releaseName;
  final String releaseNotes;
  final String downloadUrl;
  final String assetName;
  final int assetSize;
  final String publishedAt;

  UpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.assetName,
    required this.assetSize,
    required this.publishedAt,
  });

  String get formattedSize {
    if (assetSize < 1024 * 1024) {
      return '${(assetSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(assetSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 自动更新服务 — 检查 GitHub Release、下载、安装
///
/// 仓库：https://github.com/dll/mad-kgdt
/// API：GitHub Releases API v3
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String _githubOwner = 'dll';
  static const String _githubRepo = 'mad-kgdt';
  static const String _prefLastCheckKey = 'update_last_check_date';
  static const String _prefIgnoredVersionKey = 'update_ignored_version';

  bool _isChecking = false;
  bool _isDownloading = false;

  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;

  Future<UpdateInfo?> checkForUpdate() async {
    if (_isChecking) return null;
    _isChecking = true;
    try {
      final uri = Uri.parse(
          'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest');
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'CKGDT-App/$_githubOwner',
        },
      );
      if (response.statusCode != 200) {
        debugPrint('UpdateService: GitHub API 返回 ${response.statusCode}');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      if (tagName.isEmpty) return null;
      final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (!_isNewerVersion(version, BuildInfo.appVersion)) return null;
      final assets = data['assets'] as List<dynamic>? ?? [];
      final platformKeyword = _getPlatformKeyword();
      Map<String, dynamic>? targetAsset;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.contains(platformKeyword)) {
          targetAsset = asset as Map<String, dynamic>;
          break;
        }
      }
      if (targetAsset == null && assets.isNotEmpty) {
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk') ||
              name.endsWith('.zip') ||
              name.endsWith('.exe')) {
            targetAsset = asset as Map<String, dynamic>;
            break;
          }
        }
      }
      if (targetAsset == null) return null;
      return UpdateInfo(
        version: version,
        tagName: tagName,
        releaseName: data['name'] as String? ?? tagName,
        releaseNotes: data['body'] as String? ?? '暂无更新说明',
        downloadUrl: targetAsset['browser_download_url'] as String? ?? '',
        assetName: targetAsset['name'] as String? ?? '',
        assetSize: targetAsset['size'] as int? ?? 0,
        publishedAt: data['published_at'] as String? ?? '',
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'UpdateService.checkForUpdate', stack: st);
      return null;
    } finally {
      _isChecking = false;
    }
  }

  Future<String?> downloadUpdate(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (_isDownloading) return null;
    _isDownloading = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/updates');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final filePath = '${downloadDir.path}/${info.assetName}';
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(info.downloadUrl));
        final response = await client.send(request);
        if (response.statusCode != 200) {
          debugPrint('UpdateService: 下载失败 ${response.statusCode}');
          return null;
        }
        final contentLength = response.contentLength ?? 0;
        int received = 0;
        final sink = file.openWrite(mode: FileMode.write);
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (contentLength > 0 && onProgress != null) {
              onProgress(received / contentLength);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        return filePath;
      } finally {
        client.close();
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'UpdateService.downloadUpdate', stack: st);
      return null;
    } finally {
      _isDownloading = false;
    }
  }

  Future<bool> installUpdate(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      if (kIsWeb) return false;
      final result = await OpenFilex.open(filePath);
      return result.type == ResultType.done;
    } catch (e, st) {
      swallowDebug(e, tag: 'UpdateService.installUpdate', stack: st);
      return false;
    }
  }

  Future<void> openReleasePage() async {
    try {
      final uri = Uri.parse(
          'https://github.com/$_githubOwner/$_githubRepo/releases/latest');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'UpdateService.openReleasePage', stack: st);
    }
  }

  Future<String> getDownloadDirectoryPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/updates');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  Future<bool> backgroundCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getString(_prefLastCheckKey);
    if (lastCheck != null) {
      final lastDate = DateTime.tryParse(lastCheck);
      if (lastDate != null &&
          DateTime.now().difference(lastDate).inHours < 24) {
        return false;
      }
    }
    final info = await checkForUpdate();
    if (info == null) {
      await prefs.setString(
          _prefLastCheckKey, DateTime.now().toIso8601String());
      return false;
    }
    final ignoredVersion = prefs.getString(_prefIgnoredVersionKey);
    if (ignoredVersion == info.version) return false;
    await prefs.setString(_prefLastCheckKey, DateTime.now().toIso8601String());
    return true;
  }

  Future<void> ignoreVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefIgnoredVersionKey, version);
  }

  String _getPlatformKeyword() {
    if (kIsWeb) return '+web+';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return '+android+';
      case TargetPlatform.iOS:
        return '+ios+';
      case TargetPlatform.windows:
        return '+windows+';
      case TargetPlatform.macOS:
        return '+macos+';
      case TargetPlatform.linux:
        return '+linux+';
      default:
        return '+windows+';
    }
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts =
          latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      final currentParts =
          current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      for (int i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (e, st) {
      swallowDebug(e, tag: 'UpdateService._compareVersions', stack: st);
      return false;
    }
  }
}
