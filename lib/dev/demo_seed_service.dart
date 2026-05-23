import '../data/local/database_helper.dart';
import '../data/local/agent_call_log_dao.dart';
import '../data/local/class_qa_dao.dart';
import '../data/models/class_qa_model.dart';
import '../services/rag_bootstrap_service.dart';

/// Demo 录制专用的"一键造数据"服务。
///
/// **使用场景**：录 demo 视频前用，让 Dashboard / 班级问答 / AI 调用排行榜
/// 有可见内容；录完一键撤销恢复干净状态。
///
/// **生产保护**：
/// - 入口仅管理员可见（home_page _AdminToolsPage）；
/// - 所有种入数据都带 `meta='demo_seed'` 或 `prompt_summary` 前缀 `[DEMO]`，
///   方便 [revertSeed] 精准撤销。
///
/// **不会种入**：lab_submissions / quiz_results 等真业务表 — 这些应靠手动操作
/// 检验，避免 demo 数据污染正常业务流（比如教师误把假实验当真实验批了）。
class DemoSeedService {
  DemoSeedService._();
  static final DemoSeedService instance = DemoSeedService._();

  /// 唯一识别串：种入的 agent_call_logs / class_qa 都用此前缀，便于撤销。
  static const String seedTag = '[DEMO_SEED]';

  /// 一键造数据。返回种入的记录数概览。
  ///
  /// release 构建也允许调用 — 评比演示需要现场种数据；安全靠管理员入口限定，
  /// 数据带 [seedTag] 标记可一键 [revertSeed]。
  Future<Map<String, int>> seedAll() async {
    final logsCount = await _seedAgentCallLogs();
    final qaCount = await _seedClassQa();
    // 守 RAG 索引已建（DataLoadingService 启动时会调）
    await RagBootstrapService.instance.ensureIndexed();
    return {
      'agent_call_logs': logsCount,
      'class_qa': qaCount,
    };
  }

  /// 撤销：删除所有 [seedTag] 标记的记录。
  Future<Map<String, int>> revertSeed() async {
    final db = await DatabaseHelper.instance.database;
    final logs = await db.delete('agent_call_logs',
        where: 'prompt_summary LIKE ?', whereArgs: ['$seedTag%']);
    // class_qa：按 body 前缀删；replies 通过 qa_id 级联
    final qaRows = await db.query('class_qa',
        where: 'body LIKE ?', whereArgs: ['$seedTag%'], columns: ['id']);
    var replies = 0;
    for (final r in qaRows) {
      replies += await db.delete('class_qa_replies',
          where: 'qa_id = ?', whereArgs: [r['id']]);
    }
    final qa = await db
        .delete('class_qa', where: 'body LIKE ?', whereArgs: ['$seedTag%']);
    return {
      'agent_call_logs': logs,
      'class_qa': qa,
      'class_qa_replies': replies,
    };
  }

  // ── 私有：分模块种入 ────────────────────────────────────────────

  /// 30 条 agent_call_logs，含 5 条 Orchestrator chain 链路。
  Future<int> _seedAgentCallLogs() async {
    var inserted = 0;
    // 单 Agent 调用分布（按真实调用频次模拟）
    const distribution = <String, int>{
      'tutor': 8,
      'lab_grading': 6,
      'safety': 4,
      'ethics': 4,
      'quiz': 3,
      'mobile_expert': 3,
      'works_grading': 2,
    };
    for (final entry in distribution.entries) {
      for (var i = 0; i < entry.value; i++) {
        await AgentCallLogDao.instance.insert(
          agentId: entry.key,
          agentName: _agentName(entry.key),
          promptSummary: '$seedTag 演示用 ${entry.key} 调用 #$i',
          responseSummary: '这是一条用于 demo 录制的模拟回复，长度约 100 字。'
              '实际生产中会是 Agent 的真实输出。',
          durationMs: 800 + (i * 137) % 2000,
          promptChars: 200 + i * 30,
          responseChars: 500 + i * 60,
          provider: i % 2 == 0 ? 'deepseek' : 'zhipu',
          model: i % 2 == 0 ? 'deepseek-chat' : 'glm-4-flash',
        );
        inserted++;
      }
    }

    // 5 条 Orchestrator 链（safety → lab_grading → ethics）
    for (var c = 0; c < 5; c++) {
      final chainId = '${seedTag.toLowerCase()}-chn-$c';
      const chain = ['safety', 'lab_grading', 'ethics'];
      for (var step = 0; step < chain.length; step++) {
        await AgentCallLogDao.instance.insert(
          agentId: chain[step],
          agentName: _agentName(chain[step]),
          chainId: chainId,
          chainStep: step,
          promptSummary:
              '$seedTag 链 $c 步 $step (${chain[step]})',
          responseSummary: '链 $c 步 $step 输出（demo）',
          durationMs: 1200 + step * 400,
          promptChars: 300 + step * 80,
          responseChars: 800 + step * 100,
          provider: 'deepseek',
          model: 'deepseek-chat',
        );
        inserted++;
      }
    }
    return inserted;
  }

  /// 3 个示范问题 + 4 条回复（含 1 个教师采纳）。
  Future<int> _seedClassQa() async {
    final now = DateTime.now();
    var inserted = 0;
    final dao = ClassQaDao.instance;

    final qa1 = await dao.create(ClassQaModel(
      authorId: 'demo_stuA',
      authorName: '示范学生甲',
      authorRole: 'student',
      title: 'Flutter 动画掉帧严重怎么排查？',
      body: '$seedTag 我做的列表滑动有时会掉到 30fps，profile 显示是 build 在主线程。'
          '这种情况怎么定位是过度重建还是 widget 构造太重？',
      visibility: 'class',
      status: 'open',
      createdAt: now.subtract(const Duration(hours: 4)).toIso8601String(),
      updatedAt: now.subtract(const Duration(hours: 4)).toIso8601String(),
    ));
    if (qa1 > 0) inserted++;

    final qa2 = await dao.create(ClassQaModel(
      authorId: 'demo_stuB',
      authorName: '示范学生乙',
      authorRole: 'student',
      title: '微信小程序的 setData 性能瓶颈',
      body: '$seedTag 文档说 setData 不超过 256KB，但我的页面经常更新一个 50KB 的列表，'
          '感觉慢。怎么优化？',
      visibility: 'class',
      status: 'answered',
      createdAt: now.subtract(const Duration(hours: 2)).toIso8601String(),
      updatedAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
    ));
    if (qa2 > 0) inserted++;

    final qa3 = await dao.create(ClassQaModel(
      authorId: 'demo_stuC',
      authorName: '示范学生丙',
      authorRole: 'student',
      title: 'HarmonyOS ArkTS 与 TypeScript 的差异',
      body: '$seedTag 我看 ArkTS 文档说不能用 any 和动态属性，那它和 TypeScript 严格模式相比少了什么？',
      visibility: 'class',
      status: 'open',
      createdAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
      updatedAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
    ));
    if (qa3 > 0) inserted++;

    // qa1 一条学生互助回复
    await dao.addReply(ClassQaReplyModel(
      qaId: qa1,
      authorId: 'demo_stuB',
      authorName: '示范学生乙',
      authorRole: 'student',
      body: '我之前类似问题是 ListView.builder 的 itemBuilder 里漏写 const，'
          '导致每次滚动都重建整个 itemTile。',
      isTeacher: false,
      createdAt: now.subtract(const Duration(hours: 3)).toIso8601String(),
    ));

    // qa2 教师回复 + 采纳
    final teacherReply = await dao.addReply(ClassQaReplyModel(
      qaId: qa2,
      authorId: 'demo_tea1',
      authorName: '示范教师',
      authorRole: 'teacher',
      body: '小程序 setData 慢的核心是数据 diff + 跨线程 IPC。'
          '建议：① 拆分长列表用虚拟列表组件；② setData 时只传 diff（如 `{"list[0].name": "..."}`）；'
          '③ 频繁更新合并为一次 batch。',
      isTeacher: true,
      createdAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
    ));
    if (teacherReply > 0) {
      await dao.updateStatus(qa2,
          status: 'closed', acceptedReplyId: teacherReply);
    }

    return inserted;
  }

  String _agentName(String id) {
    const names = {
      'tutor': '课堂助教 小助',
      'lab_grading': '实验批阅专家',
      'safety': '安全监控中心',
      'ethics': '思政伦理导师 明德',
      'quiz': '测验教练 考官',
      'mobile_expert': '移动开发专家 全栈通',
      'works_grading': '作品评审专家',
    };
    return names[id] ?? id;
  }
}
