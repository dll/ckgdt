import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/auth_service.dart';
import '../../widgets/back_button_bar.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

/// "我的数据"页 — 学生 / 教师都可访问的隐私权利入口。
///
/// **设计权衡**：
/// - "删除"只清本地表，**不去 Gitee 远程主动 force-delete**：Gitee 仓库是教学过程
///   档案（教师批阅、班级问答历史等），删了别人也跟着丢；隐私声明已说明"所有学生
///   共用一个仓库"，用户应理解平台是教学闭环而非私域；
/// - 真要彻底从 Gitee 也清除，请联系管理员手工处理（后续可加"提交清除请求"按钮）；
/// - 直接 `db.rawQuery` 而非走 DAO 层 — 22 张表逐个加 `purgeForUser` / `dumpForUser`
///   方法成本高于本页本身，目前选择集中收口在此处。
class MyDataPage extends StatefulWidget {
  const MyDataPage({super.key});

  @override
  State<MyDataPage> createState() => _MyDataPageState();
}

class _MyDataPageState extends State<MyDataPage> {
  final _auth = AuthService();
  final _dbHelper = DatabaseHelper.instance;

  Map<String, int> _tableCounts = {};
  bool _loading = true;
  bool _busy = false;

  /// 涉及"用户数据"的表清单 — 单一事实源（表名 → 友好名）。
  ///
  /// 删除时按这里的 keys 做 DELETE WHERE user_id=? OR author_id=?；
  /// **特意排除**：users（账号本身）、班级 / 课程 / 题库等共享数据。
  static const Map<String, String> _userTables = {
    'quiz_results': '测验记录',
    'learning_records': '学习记录',
    'wrong_answers': '错题本',
    'favorites': '收藏夹',
    'lab_submissions': '实验提交',
    'student_reports': '实验报告',
    'assessment_reports': '考核报告',
    'student_works': '学生作品',
    'work_comments': '作品评论',
    'work_likes': '作品点赞',
    'achievement_scores': '成绩记录',
    'contribution_scores': '贡献分',
    'feedback': '我的反馈',
    'ai_chat_history': 'AI 对话历史',
    'agent_call_logs': 'AI 调用日志',
    'class_qa': '我发的问题',
    'class_qa_replies': '我的回复',
    'survey_responses': '问卷答卷',
    'collaboration_messages': '协作消息',
    'peer_reviews': '同行评审',
    'concept_progress': '知识点进度',
    'skill_results': '技能测评',
    'notification_recipients': '通知接收记录',
  };

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final userId = _auth.currentUser?.userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    final db = await _dbHelper.database;
    // 22 表并行 COUNT — 比串行 22 次往返快 ~10x
    final results = await Future.wait(_userTables.keys.map((table) async {
      try {
        final rows = await db.rawQuery(
            'SELECT COUNT(*) as c FROM $table WHERE user_id = ? OR author_id = ?',
            [userId, userId]);
        return MapEntry(table, (rows.first['c'] as int?) ?? 0);
      } catch (_) {
        return MapEntry(table, 0);
      }
    }));
    if (!mounted) return;
    setState(() {
      _tableCounts = {
        for (final e in results)
          if (e.value > 0) e.key: e.value,
      };
      _loading = false;
    });
  }

  Future<void> _runBusy(
    Future<void> Function() body, {
    required String onErrorPrefix,
  }) async {
    setState(() => _busy = true);
    try {
      await body();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$onErrorPrefix: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportData() => _runBusy(_doExport, onErrorPrefix: '导出失败');

  Future<void> _doExport() async {
    final userId = _auth.currentUser?.userId;
    if (userId == null) return;
    final db = await _dbHelper.database;
    final exportedAt = DateTime.now();
    // 只查 _loadCounts 已发现非空的表 — 跳过 22 表里大多数是空的
    final tablesToDump = _tableCounts.keys.toList();
    final dump = <String, dynamic>{
      '_meta': {
        'exported_at': exportedAt.toIso8601String(),
        'user_id': userId,
        'platform': 'CKGDT',
        'note': '本文件包含您在 CKGDT 平台上的全部个人数据。请妥善保管。',
      },
    };
    // 并行 SELECT
    final dumps = await Future.wait(tablesToDump.map((table) async {
      try {
        final rows = await db.rawQuery(
            'SELECT * FROM $table WHERE user_id = ? OR author_id = ?',
            [userId, userId]);
        return MapEntry(table, rows);
      } catch (_) {
        return MapEntry(table, const <Map<String, dynamic>>[]);
      }
    }));
    for (final e in dumps) {
      if (e.value.isNotEmpty) dump[e.key] = e.value;
    }

    final json = const JsonEncoder.withIndent('  ').convert(dump);
    final fileName =
        'ckgdt-mydata-$userId-${exportedAt.millisecondsSinceEpoch}.json';

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web 平台已将数据复制到剪贴板，请粘贴到本地文件保存'),
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }

    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    await File(path).writeAsString(json);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已导出到：$path'),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _deleteMyData() async {
    final userId = _auth.currentUser?.userId;
    if (userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber, color: Colors.orange, size: 48),
        title: const Text('确认删除我的数据？'),
        content: const Text(
          '该操作会清空你在本设备上的：\n\n'
          '· 所有测验记录与错题本\n'
          '· 所有实验提交与作品\n'
          '· AI 对话历史与调用日志\n'
          '· 班级问答（自己发的内容）\n'
          '· 收藏 / 学习记录 / 反馈\n\n'
          '账号本身保留可重新登录。\n'
          '注意：教师已批阅并核准的成绩**不会**删除（属教学档案）。\n'
          '注意：本操作不影响 Gitee 远程仓库的同步副本，如需彻底清除请联系管理员。',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runBusy(() async {
      final userId = _auth.currentUser!.userId;
      final db = await _dbHelper.database;
      // 单事务 + 串行 DELETE — 事务内并行不可用（sqflite 不支持），
      // 但单事务比 22 次独立 commit 节省 ~95% 的 fsync 开销。
      var deletedRows = 0;
      await db.transaction((txn) async {
        for (final table in _userTables.keys) {
          try {
            // 教师已核准的成绩属教学档案 — 不删 achievement_scores 中已有 score 的行
            if (table == 'achievement_scores') {
              deletedRows += await txn.delete(table,
                  where: 'user_id = ? AND (score IS NULL OR score = 0)',
                  whereArgs: [userId]);
              continue;
            }
            deletedRows += await txn.delete(
              table,
              where: 'user_id = ? OR author_id = ?',
              whereArgs: [userId, userId],
            );
          } catch (e) {
            swallowDebug(e, tag: 'my_data_page');
          }
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已删除 $deletedRows 条本地记录'),
            duration: const Duration(seconds: 4)),
      );
      // 删除后本地 _tableCounts 清空，无需再跑一次 22 表 COUNT
      setState(() => _tableCounts = {});
    }, onErrorPrefix: '删除失败');
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final theme = Theme.of(context);

    if (user == null) {
      return const Scaffold(
        appBar: BackButtonBar(title: '我的数据'),
        body: Center(child: Text('请先登录')),
      );
    }

    return Scaffold(
      appBar: const BackButtonBar(title: '我的数据'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                theme.colorScheme.primary.withOpacity(0.15),
                            child: Icon(Icons.person,
                                color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${user.realName ?? user.userId} (${user.userId})',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                Text('角色: ${user.role}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.outline)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('我的本地数据（${_tableCounts.length} 类）',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (_tableCounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('本地暂无属于您的数据',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    Card(
                      child: Column(
                        children: _tableCounts.entries.map((e) {
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.table_chart,
                                size: 18, color: Colors.indigo),
                            title: Text(_userTables[e.key] ?? e.key,
                                style: const TextStyle(fontSize: 13)),
                            trailing: Text('${e.value} 条',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _exportData,
                      icon: const Icon(Icons.download),
                      label: const Text('导出我的全部数据（JSON）'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '导出后会生成一个 JSON 文件，包含您本地所有学习记录与提交内容，可作为隐私权利下"数据可携带性"的证明。',
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _deleteMyData,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('删除我的本地数据',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '该操作不可撤销。教师已核准的成绩属教学档案，不会删除；Gitee 仓库的同步副本不受影响。',
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
    );
  }
}
