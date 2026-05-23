import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Agent system prompt 异步加载器（按 agentId）。
///
/// **设计目标**：让 24 个 Agent 的 prompt 可以放在 `assets/agent_prompts/{id}.md`
/// 中维护，迭代 prompt 不再 = 改源码 + 发版。
///
/// **加载顺序**：
/// 1. 内存缓存命中 → 直接返回
/// 2. 尝试从 assets 加载 → 命中则缓存并返回
/// 3. 找不到 → 返回 null（调用方应回退到 [AgentConfig.persona]）
///
/// **覆盖策略**：assets 文件存在 = 覆盖代码中 const persona。这样可以增量迁移：
/// 最先把改动频繁的 prompt 抽成 .md（如 tutor / quiz），其它保持 const。
class PromptLoader {
  PromptLoader._();

  static const String _basePath = 'assets/agent_prompts/';

  /// 内存缓存：agentId → prompt 文本（或 null 表示已确认 assets 中没有）
  static final Map<String, String?> _cache = {};

  /// 加载指定 agentId 的 prompt；若 assets 中无对应文件，返回 null。
  static Future<String?> load(String agentId) async {
    if (_cache.containsKey(agentId)) return _cache[agentId];

    try {
      final text = await rootBundle.loadString('$_basePath$agentId.md');
      final trimmed = text.trim();
      _cache[agentId] = trimmed.isEmpty ? null : trimmed;
      return _cache[agentId];
    } on FlutterError {
      // assets 中没有这个文件 — 标记为 null 防止反复尝试
      _cache[agentId] = null;
      return null;
    } catch (_) {
      _cache[agentId] = null;
      return null;
    }
  }

  /// 清除缓存（用于热更场景：下次访问会重新读 assets）
  static void invalidate([String? agentId]) {
    if (agentId == null) {
      _cache.clear();
    } else {
      _cache.remove(agentId);
    }
  }

  @visibleForTesting
  static int get cacheSize => _cache.length;
}
