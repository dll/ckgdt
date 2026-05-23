import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/local/ai_config_dao.dart';

/// 向量化嵌入服务 — 把文本转为 embedding 向量。
///
/// 依赖当前激活的 AiConfig 的 `effectiveBaseUrl` + `effectiveApiKey`，
/// 走 OpenAI 兼容协议 `POST /embeddings`。
///
/// **支持的 provider**（OpenAI 兼容 embeddings 端点）：
/// - DeepSeek: 暂未提供 embeddings，会回退到 dummy（hash-based）模式
/// - 智谱 GLM: 支持，用 `embedding-3` 等模型
/// - Ollama 本地: 支持，用 `nomic-embed-text` 等
/// - vLLM 本地: 支持，需启动 embeddings 服务
///
/// **回退策略**：远程调用失败 → 用 hash-based 伪向量保底（保证 RAG 流程不中断，
/// 但准确率会下降，仅作开发/演示）。
class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  final _configDao = AiConfigDao();

  /// 内存 LRU 缓存：(provider|model|text) → embedding。
  ///
  /// **设计权衡**：纯内存、进程内 — 不持久化（rag_embeddings 表已是磁盘缓存）。
  /// 主要避免短期内 indexDocument 重复 chunk + agent 多轮对话同一 query 的
  /// 重复网络往返。容量 64 条对应 ~64×128×8B ≈ 64KB（小语义模型）/ 1MB
  /// （主流 1024 维），都在可接受范围。命中后用 LinkedHashMap 重排到末尾。
  final Map<String, List<double>> _cache = <String, List<double>>{};
  static const _maxCacheSize = 64;

  /// 默认 embedding 模型（按 provider 切换）
  static String _defaultModel(String provider) {
    switch (provider) {
      case 'zhipu':
        return 'embedding-3';
      case 'ollama':
        return 'nomic-embed-text';
      case 'vllm':
        return 'BAAI/bge-large-zh';
      default:
        return 'text-embedding-ada-002'; // OpenAI 兼容默认
    }
  }

  /// 把单段文本转为 embedding。失败时回退到 hash-based 伪向量（128 维）。
  Future<List<double>> embed(String text, {String? modelOverride}) async {
    final config = await _configDao.getConfig();
    final isLocal = config.provider == 'ollama' || config.provider == 'vllm';
    final apiKey = config.effectiveApiKey ?? (isLocal ? 'local-no-key' : null);
    final model = modelOverride ?? _defaultModel(config.provider);
    final cacheKey = '${config.provider}|$model|$text';

    // LRU 命中：移到末尾后返回
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }

    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('EmbeddingService: 无 API Key，回退到 hash-based 伪向量');
      final v = _fallbackHashEmbedding(text);
      _putCache(cacheKey, v);
      return v;
    }

    final url = '${config.effectiveBaseUrl}/embeddings';

    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'input': text,
        }),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        debugPrint('EmbeddingService: HTTP ${resp.statusCode} → 回退伪向量');
        final v = _fallbackHashEmbedding(text);
        _putCache(cacheKey, v);
        return v;
      }

      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      final data = json['data'] as List?;
      if (data == null || data.isEmpty) {
        final v = _fallbackHashEmbedding(text);
        _putCache(cacheKey, v);
        return v;
      }
      final emb = (data[0] as Map)['embedding'] as List?;
      if (emb == null) {
        final v = _fallbackHashEmbedding(text);
        _putCache(cacheKey, v);
        return v;
      }
      final v = emb.map((e) => (e as num).toDouble()).toList();
      _putCache(cacheKey, v);
      return v;
    } catch (e) {
      debugPrint('EmbeddingService: 调用失败 $e → 回退伪向量');
      final v = _fallbackHashEmbedding(text);
      _putCache(cacheKey, v);
      return v;
    }
  }

  void _putCache(String key, List<double> v) {
    _cache[key] = v;
    if (_cache.length > _maxCacheSize) {
      // 淘汰最旧的（LinkedHashMap 第一个 key）
      _cache.remove(_cache.keys.first);
    }
  }

  /// 测试用：清空缓存
  @visibleForTesting
  void clearCache() => _cache.clear();

  /// 批量 embed。当前实现为并行调用（不是 provider 的 batch input 协议）—
  /// 多数 provider 接受 input 字符串数组，可以省一次往返；这里为保持
  /// 兼容性 + 简单性使用并行单次调用。
  /// **注意**：并行度太高可能触发 provider 限流；> 20 条建议分批。
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map((t) => embed(t)));
  }

  /// 伪向量：把字符串哈希成稳定 128 维向量（仅作 graceful degradation）。
  /// 同一文本产出相同向量；语义相似度退化为字面相似度。
  List<double> _fallbackHashEmbedding(String text) {
    const dim = 128;
    final v = List<double>.filled(dim, 0);
    if (text.isEmpty) return v;
    final norm = text.toLowerCase();
    for (var i = 0; i < norm.length; i++) {
      final code = norm.codeUnitAt(i);
      final bucket = code % dim;
      v[bucket] += 1.0 / (1 + i / 10);
    }
    // 归一化（向量除以 L2 范数）
    var sumSq = 0.0;
    for (final x in v) {
      sumSq += x * x;
    }
    final mag = sumSq > 0 ? math.sqrt(sumSq) : 1.0;
    for (var i = 0; i < dim; i++) {
      v[i] /= mag;
    }
    return v;
  }
}
