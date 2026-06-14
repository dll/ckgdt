import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../core/error_handler.dart';
import 'database_helper.dart';

/// RAG 向量索引 DAO（rag_embeddings 表）。
///
/// **设计**：用 BLOB 存 Float32 向量，纯 Dart 算余弦相似度 top-k。
/// 不依赖 sqlite-vss 等原生扩展，全平台一致。
///
/// **容量假设**：教学场景文档分片 100-500 条够用；纯 Dart 计算 < 50ms。
/// 真要扩到万级，再升级到原生向量扩展。
class RagEmbeddingDao {
  RagEmbeddingDao._();
  static final RagEmbeddingDao instance = RagEmbeddingDao._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 插入一条向量记录。content 是原文片段，embedding 是浮点向量。
  Future<int> insert({
    required String docId,
    required String chunkId,
    required String content,
    required List<double> embedding,
    String? meta,
  }) async {
    try {
      final db = await _dbHelper.database;
      return await db.insert('rag_embeddings', {
        'doc_id': docId,
        'chunk_id': chunkId,
        'content': content,
        'embedding': _encodeVector(embedding),
        'dim': embedding.length,
        'meta': meta,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e, st) {
      report(e, tag: 'RagEmbeddingDao.insert', stack: st);
      return -1;
    }
  }

  /// 检索：返回与 [queryEmbedding] 相似度最高的 [topK] 条。
  ///
  /// 维度自动按 [queryEmbedding.length] 过滤（避免不同 embedding 模型混用）。
  Future<List<RagSearchResult>> search(
    List<double> queryEmbedding, {
    int topK = 6,
    String? docIdFilter,
    String? docIdPrefix,
  }) async {
    try {
      final db = await _dbHelper.database;
      final where = StringBuffer('dim = ?');
      final args = <Object?>[queryEmbedding.length];
      if (docIdFilter != null) {
        where.write(' AND doc_id = ?');
        args.add(docIdFilter);
      }
      if (docIdPrefix != null) {
        where.write(' AND doc_id LIKE ?');
        args.add('$docIdPrefix%');
      }
      final rows = await db.query(
        'rag_embeddings',
        where: where.toString(),
        whereArgs: args,
      );
      // 计算余弦相似度
      final qNorm = _norm(queryEmbedding);
      if (qNorm == 0) return [];
      final scored = <RagSearchResult>[];
      for (final r in rows) {
        final blob = r['embedding'] as List<int>?;
        if (blob == null) continue;
        final vec = _decodeVector(Uint8List.fromList(blob));
        final score = _cosine(queryEmbedding, vec, qNorm);
        scored.add(RagSearchResult(
          docId: r['doc_id'] as String? ?? '',
          chunkId: r['chunk_id'] as String? ?? '',
          content: r['content'] as String? ?? '',
          score: score,
          meta: r['meta'] as String?,
        ));
      }
      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored.take(topK).toList();
    } catch (e, st) {
      report(e, tag: 'RagEmbeddingDao.search', stack: st);
      return [];
    }
  }

  /// 删除某文档的所有向量片段（重新索引前调用）
  Future<int> deleteByDoc(String docId) async {
    try {
      final db = await _dbHelper.database;
      return await db
          .delete('rag_embeddings', where: 'doc_id = ?', whereArgs: [docId]);
    } catch (e) {
      swallowDebug(e, tag: 'RagEmbeddingDao.deleteByDoc');
      return 0;
    }
  }

  Future<int> count() async {
    try {
      final db = await _dbHelper.database;
      final r = await db.rawQuery('SELECT COUNT(*) as c FROM rag_embeddings');
      return (r.first['c'] as int?) ?? 0;
    } catch (e) {
      swallowDebug(e, tag: 'RagEmbeddingDao.count');
      return 0;
    }
  }

  // ── 私有：向量编解码 + 相似度 ──────────────────────────────────

  /// 把 List<double> 序列化为 Float32 BLOB（4 bytes/value），减小磁盘占用。
  Uint8List _encodeVector(List<double> v) {
    final bd = ByteData(v.length * 4);
    for (var i = 0; i < v.length; i++) {
      bd.setFloat32(i * 4, v[i], Endian.little);
    }
    return bd.buffer.asUint8List();
  }

  List<double> _decodeVector(Uint8List bytes) {
    final n = bytes.length ~/ 4;
    final bd = ByteData.sublistView(bytes);
    return List<double>.generate(
      n,
      (i) => bd.getFloat32(i * 4, Endian.little),
    );
  }

  double _norm(List<double> v) {
    var s = 0.0;
    for (final x in v) {
      s += x * x;
    }
    return math.sqrt(s);
  }

  double _cosine(List<double> a, List<double> b, double aNorm) {
    if (a.length != b.length) return 0;
    var dot = 0.0;
    var bSq = 0.0;
    // 一次循环同时算 dot 和 b 的范数 — 避免外层 search 还要单独再扫 b
    for (var i = 0; i < a.length; i++) {
      final ai = a[i];
      final bi = b[i];
      dot += ai * bi;
      bSq += bi * bi;
    }
    if (bSq == 0) return 0;
    return dot / (aNorm * math.sqrt(bSq));
  }
}

class RagSearchResult {
  final String docId;
  final String chunkId;
  final String content;
  final double score; // 0..1
  final String? meta;

  const RagSearchResult({
    required this.docId,
    required this.chunkId,
    required this.content,
    required this.score,
    this.meta,
  });
}
