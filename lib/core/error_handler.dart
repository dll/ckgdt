import 'package:flutter/foundation.dart';

/// 统一异常处理工具集 — 替代项目中散落的 `catch (_) {}` 模式。
///
/// **背景**：项目里曾有 375 处 `catch (_) {}` 静默吞错，调试时根本不知道
/// 哪里挂了。本工具提供三个语义清晰的工具，让"我故意吞错"显式化。
///
/// **使用原则**：
/// - 调用方仍写 `try { ... } catch (e) { swallow(e, tag: 'XxxDao'); }`，
///   长度差不多但**意图明确**且 debug 模式自动 print；
/// - 用 [tag] 字段定位到模块（如 `'AgentCallLogDao'` / `'RagBootstrap'`），
///   便于以后接 Sentry / Crashlytics 时统一打标。
///
/// **三层语义**：
/// - [swallow]：明知无所谓，连日志都不打（如 schema 试探查询表不存在）
/// - [swallowDebug]：debug 模式打日志，release 静默（默认推荐）
/// - [report]：主流程异常，永远打日志（不论 debug/release）
///
/// **示例**：
/// ```dart
/// try {
///   await db.insert('agent_call_logs', row);
/// } catch (e, st) {
///   swallowDebug(e, tag: 'AgentCallLogDao.insert', stack: st);
/// }
/// ```
///
/// 完全静默吞错。仅用于"明知道这里失败也没事"的情况。
///
/// 滥用本函数与 `catch (_) {}` 等价 —— 如果你不能在 30 秒内说清楚
/// "为什么这里失败也没关系"，请用 [swallowDebug] 而非这个。
void swallow(Object _, {String? tag}) {
  // 故意空实现 — 让调用点的"我故意忽略"是显式的
}

/// Debug 模式打日志，release 静默。**项目内绝大多数 catch 应使用本函数。**
///
/// 例如：
/// - 试探性查询某表是否存在（schema 漂移容错）
/// - 异步通知发送失败（不应阻塞主流程）
/// - 缓存写入失败（下次再写就好）
void swallowDebug(Object error, {String? tag, StackTrace? stack}) {
  if (!kDebugMode) return;
  final prefix = tag != null ? '[$tag]' : '[swallow]';
  debugPrint('$prefix swallow: $error');
  if (stack != null) {
    debugPrint(stack.toString());
  }
}

/// 报告异常 —— 永远打日志（含 release 构建）。
///
/// 用于"不阻塞调用方，但开发者必须知道"的情况，比如：
/// - 主业务流的非阻塞副作用（埋点 / 同步 / 通知派发）
/// - 用户已收到结果但后台清理失败
///
/// **不要**用本函数包"用户能感知的失败"—— 那种应 rethrow 让 UI 显示错误。
void report(Object error, {String? tag, StackTrace? stack}) {
  final prefix = tag != null ? '[$tag]' : '[error]';
  debugPrint('$prefix $error');
  if (stack != null) {
    debugPrint(stack.toString());
  }
  // TODO 接 Sentry / Firebase Crashlytics 时在此 hook：
  // ErrorReporting.instance?.captureError(error, stack, tag: tag);
}
