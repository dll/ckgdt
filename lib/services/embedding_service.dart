import 'dart:convert';
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

    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('EmbeddingService: 无 API Key，回退到 hash-based 伪向量');
      return _fallbackHashEmbedding(text);
    }

    final url = '${config.effectiveBaseUrl}/embeddings';
    final model = modelOverride ?? _defaultModel(config.provider);

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
        return _fallbackHashEmbedding(text);
      }

      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      final data = json['data'] as List?;
      if (data == null || data.isEmpty) return _fallbackHashEmbedding(text);
      final emb = (data[0] as Map)['embedding'] as List?;
      if (emb == null) return _fallbackHashEmbedding(text);
      return emb.map((e) => (e as num).toDouble()).toList();
    } catch (e) {
      debugPrint('EmbeddingService: 调用失败 $e → 回退伪向量');
      return _fallbackHashEmbedding(text);
    }
  }

  /// 批量 embed（部分 provider 支持 batch input）
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final results = <List<double>>[];
    for (final t in texts) {
      results.add(await embed(t));
    }
    return results;
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
    // 归一化
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final mag = sum > 0 ? sum : 1;
    for (var i = 0; i < dim; i++) {
      v[i] /= mag;
    }
    return v;
  }
}
