import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 归档模板（参考案例）资源加载器。
///
/// **设计目标**：把 `data/归档/<期>/模板/*.docx` 经 `tools/convert_archive_templates.py`
/// 预处理后的 .md 资源加载进 LLM prompt 当 **few-shot 风格学习材料**——
/// AI 学结构和行文风格，**不是**填空模板。
///
/// **路径约定**（必须与 Python 脚本 PERIOD_MAP / DOC_TYPE_PATTERNS 对齐）：
///   - `assets/archive_templates/<periodEn>/<docType>.md`           主参考
///   - `assets/archive_templates/<periodEn>/_ref/<docType>/*.md`    副参考（多份历届/兄弟资料）
///
/// **periodEn 取值**：start（期初）/ mid（期中）/ end（期末）/ final（归档）
/// **docType 取值**：syllabus / syllabus_audit / syllabus_review / obe_report /
///                   progress_table / assessment_plan / teaching_handbook /
///                   learning_handbook
///
/// **覆盖策略**：assets 找不到 → 返回 null。Agent 应回退到纯 persona 模式
/// （即不带模板的通用生成），不让一个文件丢导致功能崩。
class ArchiveTemplateLoader {
  ArchiveTemplateLoader._();

  static const String _basePath = 'assets/archive_templates/';

  /// 期间中文名 → 英文 key（与 Python 脚本 PERIOD_MAP 对齐）
  static const Map<String, String> periodKey = {
    '期初': 'start',
    '期中': 'mid',
    '期末': 'end',
    '归档': 'final',
  };

  /// 内存缓存：path → 内容（或 null 表示已确认 assets 中没有）
  static final Map<String, String?> _cache = <String, String?>{};
  static const int _maxCacheSize = 32;

  /// 加载主参考。periodZh 用中文（'期初'）或英文 key（'start'）都行。
  /// 找不到返回 null。
  static Future<String?> loadPrimary({
    required String periodZh,
    required String docType,
  }) async {
    final periodEn = periodKey[periodZh] ?? periodZh;
    final path = '$_basePath$periodEn/$docType.md';
    return _loadCached(path);
  }

  /// 加载某 docType 的全部副参考（_ref/<docType>/*.md）。
  /// 因 Flutter assets 不支持运行时列目录，这里走"约定常用文件名"策略：
  /// 调用方需提前在 pubspec.yaml 声明这些资源路径。当前仅期初有定义。
  ///
  /// 返回 path → content 映射；找不到的 path 不出现在 map 里。
  static Future<Map<String, String>> loadRefs({
    required String periodZh,
    required String docType,
    List<String>? candidateFilenames,
  }) async {
    final periodEn = periodKey[periodZh] ?? periodZh;
    final dir = '$_basePath$periodEn/_ref/$docType/';
    final result = <String, String>{};

    // 没给候选文件名 → 走 AssetManifest 反查（首次加载稍慢，但更准）
    final candidates = candidateFilenames ?? await _discoverRefs(dir);
    for (final fn in candidates) {
      final path = '$dir$fn';
      final c = await _loadCached(path);
      if (c != null) result[path] = c;
    }
    return result;
  }

  /// 加载索引（_index.md），含本期间所有可用 docType 列表
  static Future<String?> loadIndex(String periodZh) async {
    final periodEn = periodKey[periodZh] ?? periodZh;
    return _loadCached('$_basePath$periodEn/_index.md');
  }

  /// 内部：带缓存的 rootBundle.loadString
  static Future<String?> _loadCached(String path) async {
    if (_cache.containsKey(path)) return _cache[path];
    try {
      final content = await rootBundle.loadString(path);
      _cacheSet(path, content);
      return content;
    } catch (e) {
      // assets 不存在 / 解码失败都走这里——记 null 避免重复尝试
      _cacheSet(path, null);
      if (kDebugMode) {
        debugPrint('[ArchiveTemplateLoader] miss: $path ($e)');
      }
      return null;
    }
  }

  static void _cacheSet(String path, String? content) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first); // FIFO 淘汰
    }
    _cache[path] = content;
  }

  /// 通过 AssetManifest 列出某目录下的 .md 文件名（不含路径前缀）。
  /// 用于自动发现 _ref/ 下的所有副参考文件。
  static Future<List<String>> _discoverRefs(String dirPath) async {
    try {
      final manifestStr = await rootBundle.loadString('AssetManifest.json');
      // 解析 manifest 比 jsonDecode 更轻量：直接 substring 匹配 key
      // （key 形如 "assets/archive_templates/start/_ref/syllabus/xxx.md"）
      final result = <String>[];
      final pattern = RegExp(r'"(' + RegExp.escape(dirPath) + r'[^"]+\.md)"');
      for (final m in pattern.allMatches(manifestStr)) {
        final fullPath = m.group(1)!;
        final filename = fullPath.substring(dirPath.length);
        if (!filename.contains('/')) result.add(filename);
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[ArchiveTemplateLoader] manifest read failed: $e');
      return const [];
    }
  }

  /// 测试用：清空缓存
  @visibleForTesting
  static void resetCacheForTest() => _cache.clear();
}
