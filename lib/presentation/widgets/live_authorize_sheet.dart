import 'package:flutter/material.dart';

import '../../core/design/noir_tokens.dart';
import '../../core/error_handler.dart';
import '../../data/models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/live_broadcast_service.dart';

/// 教师端「直播授权」面板 — 勾选哪些学生可以开播答辩直播。
///
/// 授权名单写入 Gitee `live/authorized.json`，开播端开播前校验。
/// 教师/管理员本身恒可开播，无需在此勾选。
class LiveAuthorizeSheet extends StatefulWidget {
  const LiveAuthorizeSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NoirTokens.ink,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const LiveAuthorizeSheet(),
    );
  }

  @override
  State<LiveAuthorizeSheet> createState() => _LiveAuthorizeSheetState();
}

class _LiveAuthorizeSheetState extends State<LiveAuthorizeSheet> {
  final _auth = AuthService();
  List<UserModel> _students = [];
  final Set<String> _authorized = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final students = await _auth.getStudents();
      final authorized =
          await LiveBroadcastService.instance.getAuthorizedIds();
      if (mounted) {
        setState(() {
          _students = students;
          _authorized
            ..clear()
            ..addAll(authorized);
          _loading = false;
        });
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveAuthorize.load', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await LiveBroadcastService.instance
        .setAuthorizedIds(_authorized.toList());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '授权已保存（${_authorized.length} 人可开播）' : '保存失败，请检查网络'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: NoirTokens.paper.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.cast_connected,
                      color: NoirTokens.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('直播授权 · 选择可开播的学生',
                        style: TextStyle(
                            color: NoirTokens.paper,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                  Text('${_authorized.length} 人',
                      style: TextStyle(
                          color: NoirTokens.paper.withValues(alpha: 0.6),
                          fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: NoirTokens.accent))
                  : _students.isEmpty
                      ? Center(
                          child: Text('暂无学生数据',
                              style: TextStyle(
                                  color: NoirTokens.paper
                                      .withValues(alpha: 0.5))))
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: _students.length,
                          itemBuilder: (_, i) {
                            final s = _students[i];
                            final on = _authorized.contains(s.userId);
                            return SwitchListTile(
                              value: on,
                              activeThumbColor: NoirTokens.accent,
                              title: Text(s.realName ?? s.userId,
                                  style:
                                      const TextStyle(color: NoirTokens.paper)),
                              subtitle: Text(s.userId,
                                  style: TextStyle(
                                      color: NoirTokens.paper
                                          .withValues(alpha: 0.5),
                                      fontSize: 12)),
                              onChanged: (v) => setState(() {
                                if (v) {
                                  _authorized.add(s.userId);
                                } else {
                                  _authorized.remove(s.userId);
                                }
                              }),
                            );
                          },
                        ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).viewPadding.bottom + 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_saving ? '保存中…' : '保存授权'),
                  style: FilledButton.styleFrom(
                    backgroundColor: NoirTokens.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
