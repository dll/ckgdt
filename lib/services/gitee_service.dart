import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Gitee API v5 服务
/// 用于获取仓库列表、分支、提交等信息
class GiteeService {
  static const String _baseUrl = 'https://gitee.com/api/v5';
  static const String _tokenKey = 'gitee_access_token';
  static const String _ownerKey = 'gitee_default_owner';
  static const String _repoPrefixKey = 'gitee_repo_prefix';

  // ── Token 管理 ──────────────────────────────────────────────────────────

  /// 保存 Gitee 私人令牌
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// 获取已保存的 Gitee 私人令牌
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// 保存默认仓库所有者（用户名或组织名）
  Future<void> saveDefaultOwner(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerKey, owner);
  }

  /// 获取默认仓库所有者
  Future<String?> getDefaultOwner() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ownerKey);
  }

  /// 保存仓库名称前缀过滤（逗号分隔，如 cg1,cg2,cg3）
  Future<void> saveRepoPrefix(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_repoPrefixKey, prefix);
  }

  /// 获取仓库名称前缀过滤
  Future<String?> getRepoPrefix() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_repoPrefixKey);
  }

  /// 根据前缀过滤仓库列表
  /// [repos] 仓库列表, [prefix] 逗号分隔的前缀，如 "cg1,cg2,cg3"
  List<Map<String, dynamic>> filterReposByPrefix(
    List<Map<String, dynamic>> repos,
    String? prefix,
  ) {
    if (prefix == null || prefix.trim().isEmpty) return repos;
    final prefixes = prefix
        .split(',')
        .map((p) => p.trim().toLowerCase())
        .where((p) => p.isNotEmpty)
        .toList();
    if (prefixes.isEmpty) return repos;
    return repos.where((r) {
      final name = (r['name']?.toString() ?? '').toLowerCase();
      return prefixes.any((p) => name.startsWith(p));
    }).toList();
  }

  // ── 通用请求 ──────────────────────────────────────────────────────────

  /// 构建带 token 的请求头
  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'token $token',
    };
  }

  /// 通用 GET 请求
  Future<dynamic> _get(String path, {Map<String, String>? queryParams}) async {
    final token = await getToken();
    final params = <String, String>{};
    if (token != null && token.isNotEmpty) {
      params['access_token'] = token;
    }
    if (queryParams != null) {
      params.addAll(queryParams);
    }

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: params);
    debugPrint('GiteeService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      final body = utf8.decode(response.bodyBytes);
      throw GiteeApiException(
        statusCode: response.statusCode,
        message: '请求失败: $body',
      );
    }
  }

  // ── 连接测试 ──────────────────────────────────────────────────────────

  /// 测试 Token 是否有效（获取当前用户信息）
  Future<Map<String, dynamic>> testConnection() async {
    final result = await _get('/user');
    return Map<String, dynamic>.from(result);
  }

  // ── 仓库 API ──────────────────────────────────────────────────────────

  /// 获取当前认证用户的仓库列表（推荐，不受限流影响）
  Future<List<Map<String, dynamic>>> getMyRepos({
    int page = 1,
    int perPage = 100,
    String sort = 'full_name',
    String direction = 'asc',
  }) async {
    final result = await _get(
      '/user/repos',
      queryParams: {
        'page': '$page',
        'per_page': '$perPage',
        'sort': sort,
        'direction': direction,
        'type': 'all',
      },
    );
    return List<Map<String, dynamic>>.from(
      (result as List).map((r) => Map<String, dynamic>.from(r)),
    );
  }

  /// 获取指定用户的仓库列表
  Future<List<Map<String, dynamic>>> getUserRepos(
    String username, {
    int page = 1,
    int perPage = 20,
    String sort = 'pushed',
    String direction = 'desc',
  }) async {
    final result = await _get(
      '/users/$username/repos',
      queryParams: {
        'page': '$page',
        'per_page': '$perPage',
        'sort': sort,
        'direction': direction,
        'type': 'all',
      },
    );
    return List<Map<String, dynamic>>.from(
      (result as List).map((r) => Map<String, dynamic>.from(r)),
    );
  }

  /// 获取仓库详情
  Future<Map<String, dynamic>> getRepoDetail(
      String owner, String repo) async {
    final result = await _get('/repos/$owner/$repo');
    return Map<String, dynamic>.from(result);
  }

  // ── 分支 API ──────────────────────────────────────────────────────────

  /// 获取仓库的分支列表
  Future<List<Map<String, dynamic>>> getBranches(
    String owner,
    String repo, {
    int page = 1,
    int perPage = 100,
  }) async {
    final result = await _get(
      '/repos/$owner/$repo/branches',
      queryParams: {
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    return List<Map<String, dynamic>>.from(
      (result as List).map((r) => Map<String, dynamic>.from(r)),
    );
  }

  // ── 提交 API ──────────────────────────────────────────────────────────

  /// 获取仓库的提交列表
  Future<List<Map<String, dynamic>>> getCommits(
    String owner,
    String repo, {
    String? sha,
    int page = 1,
    int perPage = 20,
    String? since,
    String? until,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    if (sha != null) params['sha'] = sha;
    if (since != null) params['since'] = since;
    if (until != null) params['until'] = until;

    final result = await _get(
      '/repos/$owner/$repo/commits',
      queryParams: params,
    );
    return List<Map<String, dynamic>>.from(
      (result as List).map((r) => Map<String, dynamic>.from(r)),
    );
  }

  // ── 贡献者/成员 API ──────────────────────────────────────────────────

  /// 获取仓库贡献者
  Future<List<Map<String, dynamic>>> getContributors(
    String owner,
    String repo,
  ) async {
    try {
      final result = await _get('/repos/$owner/$repo/contributors');
      return List<Map<String, dynamic>>.from(
        (result as List).map((r) => Map<String, dynamic>.from(r)),
      );
    } catch (e) {
      debugPrint('GiteeService: getContributors error: $e');
      return [];
    }
  }

  /// 获取仓库协作者/成员列表
  Future<List<Map<String, dynamic>>> getCollaborators(
    String owner,
    String repo, {
    int page = 1,
    int perPage = 100,
  }) async {
    try {
      final result = await _get(
        '/repos/$owner/$repo/collaborators',
        queryParams: {
          'page': '$page',
          'per_page': '$perPage',
        },
      );
      return List<Map<String, dynamic>>.from(
        (result as List).map((r) => Map<String, dynamic>.from(r)),
      );
    } catch (e) {
      debugPrint('GiteeService: getCollaborators error: $e');
      return [];
    }
  }

  /// 获取仓库所有提交（自动分页获取全部）
  Future<List<Map<String, dynamic>>> getAllCommits(
    String owner,
    String repo, {
    String? since,
    String? until,
  }) async {
    final allCommits = <Map<String, dynamic>>[];
    int page = 1;
    const perPage = 100;

    while (true) {
      final batch = await getCommits(
        owner, repo,
        page: page,
        perPage: perPage,
        since: since,
        until: until,
      );
      allCommits.addAll(batch);
      if (batch.length < perPage) break;
      page++;
      // 安全限制：最多获取 1000 条
      if (allCommits.length >= 1000) break;
    }
    return allCommits;
  }

  // ── 统计/Release API ──────────────────────────────────────────────────

  /// 获取单次提交的详细信息（包含 additions / deletions / files）
  Future<Map<String, dynamic>> getCommitDetail(
    String owner,
    String repo,
    String sha,
  ) async {
    final result = await _get('/repos/$owner/$repo/commits/$sha');
    return Map<String, dynamic>.from(result);
  }

  /// 批量获取提交详情（带 additions/deletions）
  /// [shas] 最多获取前 maxCount 条的详情，避免过多请求
  Future<List<Map<String, dynamic>>> getCommitDetails(
    String owner,
    String repo,
    List<String> shas, {
    int maxCount = 50,
  }) async {
    final limited = shas.take(maxCount).toList();
    final details = <Map<String, dynamic>>[];
    for (final sha in limited) {
      try {
        final detail = await getCommitDetail(owner, repo, sha);
        details.add(detail);
      } catch (e) {
        debugPrint('GiteeService: getCommitDetail($sha) error: $e');
      }
    }
    return details;
  }

  /// 获取仓库 Releases
  Future<List<Map<String, dynamic>>> getReleases(
    String owner,
    String repo, {
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final result = await _get(
        '/repos/$owner/$repo/releases',
        queryParams: {
          'page': '$page',
          'per_page': '$perPage',
        },
      );
      return List<Map<String, dynamic>>.from(
        (result as List).map((r) => Map<String, dynamic>.from(r)),
      );
    } catch (e) {
      debugPrint('GiteeService: getReleases error: $e');
      return [];
    }
  }

  // ── 辅助方法 ──────────────────────────────────────────────────────────

  /// 从仓库 URL 解析 owner 和 repo 名
  /// 支持: https://gitee.com/owner/repo.git 或 https://gitee.com/owner/repo
  static ({String owner, String repo})? parseRepoUrl(String url) {
    try {
      String cleaned = url.trim();
      if (cleaned.endsWith('.git')) {
        cleaned = cleaned.substring(0, cleaned.length - 4);
      }
      final uri = Uri.parse(cleaned);
      final segments = uri.pathSegments;
      if (segments.length >= 2) {
        return (owner: segments[0], repo: segments[1]);
      }
    } catch (_) {}
    return null;
  }

  /// 从多个仓库 URL 批量获取仓库信息
  Future<List<Map<String, dynamic>>> getReposFromUrls(
      List<String> urls) async {
    final repos = <Map<String, dynamic>>[];
    for (final url in urls) {
      final parsed = parseRepoUrl(url);
      if (parsed != null) {
        try {
          final detail = await getRepoDetail(parsed.owner, parsed.repo);
          repos.add(detail);
        } catch (e) {
          debugPrint('GiteeService: Failed to get repo from $url: $e');
          // 添加一个简化的错误记录
          repos.add({
            'name': parsed.repo,
            'full_name': '${parsed.owner}/${parsed.repo}',
            'html_url': url,
            '_error': true,
            '_error_message': '$e',
          });
        }
      }
    }
    return repos;
  }
}

/// Gitee API 异常
class GiteeApiException implements Exception {
  final int statusCode;
  final String message;

  GiteeApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'GiteeApiException($statusCode): $message';
}
