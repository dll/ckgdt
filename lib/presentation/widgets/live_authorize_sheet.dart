import 'package:flutter/material.dart';

import '../../core/design/noir_tokens.dart';
import '../../core/error_handler.dart';
import '../../core/network_utils.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/live_broadcast_service.dart';
import '../../services/notification_service.dart';

/// 教师端「直播授权」面板 — 勾选学生可以开播答辩直播。
///
/// 只显示进行中班级的学生，已归档班级（计科221/222）的学生不显示。
class LiveAuthorizeSheet extends StatefulWidget {
  final String? className;
  const LiveAuthorizeSheet({super.key, this.className});

  static void show(BuildContext context, {String? className}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NoirTokens.ink,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LiveAuthorizeSheet(className: className),
    );
  }

  @override
  State<LiveAuthorizeSheet> createState() => _LiveAuthorizeSheetState();
}

class _LiveAuthorizeSheetState extends State<LiveAuthorizeSheet> {
  final _auth = AuthService();
  List<UserModel> _displayedStudents = [];
  final Set<String> _authorized = {};
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _activeClasses = [];
  String _selectedClass = 'all';
  Set<String> _activeClassStudentIds = {};

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.className ?? 'all';
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // 1. 加载所有进行中的班级（排除归档班级）
      final classes = await db.query('classes',
          where: 'is_archived = ?',
          whereArgs: [0],
          orderBy: 'name');

      // 2. 获取所有进行中班级的学生ID
      final activeClassIds = classes.map((c) => c['id'] as int).toList();
      Set<String> activeStudentIds = {};

      if (activeClassIds.isNotEmpty) {
        final placeholders = List.filled(activeClassIds.length, '?').join(',');
        final members = await db.rawQuery(
          'SELECT DISTINCT user_id FROM class_members WHERE class_id IN ($placeholders)',
          activeClassIds,
        );
        activeStudentIds = members.map((m) => m['user_id'] as String).toSet();
      }

      // 3. 加载已授权名单
      final authorized =
          await LiveBroadcastService.instance.getAuthorizedIds();

      // 4. 只保留属于进行中班级的授权
      final validAuthorized = authorized.where((uid) => activeStudentIds.contains(uid)).toSet();

      if (mounted) {
        setState(() {
          _activeClasses = classes;
          _activeClassStudentIds = activeStudentIds;
          _authorized
            ..clear()
            ..addAll(validAuthorized);
          _loading = false;
        });
        await _filterStudents();
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveAuthorize.load', stack: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _filterStudents() async {
    try {
      final db = await DatabaseHelper.instance.database;

      if (_selectedClass == 'all') {
        // 显示所有进行中班级的学生
        if (_activeClassStudentIds.isEmpty) {
          setState(() => _displayedStudents = []);
          return;
        }

        final placeholders = List.filled(_activeClassStudentIds.length, '?').join(',');
        final userMaps = await db.rawQuery(
          'SELECT * FROM users WHERE user_id IN ($placeholders) AND role = ? ORDER BY user_id',
          [..._activeClassStudentIds.toList(), 'student'],
        );

        setState(() {
          _displayedStudents = userMaps.map((m) => UserModel.fromMap(m)).toList();
        });
      } else {
        // 显示指定班级的学生
        final classRows = await db.query('classes',
            where: 'name = ? AND is_archived = ?',
            whereArgs: [_selectedClass, 0],
            limit: 1);

        if (classRows.isEmpty) {
          setState(() => _displayedStudents = []);
          return;
        }

        final classId = classRows.first['id'] as int;
        final members = await db.query('class_members',
            where: 'class_id = ?', whereArgs: [classId]);
        final userIds = members.map((m) => m['user_id'] as String).toList();

        if (userIds.isEmpty) {
          setState(() => _displayedStudents = []);
          return;
        }

        final placeholders = List.filled(userIds.length, '?').join(',');
        final userMaps = await db.rawQuery(
          'SELECT * FROM users WHERE user_id IN ($placeholders) AND role = ? ORDER BY user_id',
          [...userIds, 'student'],
        );

        setState(() {
          _displayedStudents = userMaps.map((m) => UserModel.fromMap(m)).toList();
        });
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveAuthorize.filter', stack: st);
      setState(() => _displayedStudents = []);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final previousAuthorized = await LiveBroadcastService.instance.getAuthorizedIds();
    final ok = await LiveBroadcastService.instance
        .setAuthorizedIds(_authorized.toList());
    if (!mounted) return;
    setState(() => _saving = false);

    // 发送通知给新授权的学生
    if (ok) {
      final newlyAuthorized = _authorized.difference(previousAuthorized.toSet());
      final notificationService = NotificationService();

      // 获取教师本机 IP 用于局域网答辩
      final serverIp = await NetworkUtils.getLocalIp();

      for (final uid in newlyAuthorized) {
        final student = _displayedStudents.where((s) => s.userId == uid).firstOrNull;
        notificationService.notifyDefenseAuthorized(
          studentId: uid,
          studentName: student?.realName ?? uid,
          serverIp: serverIp,
        );
      }
    }

    if (!mounted) return;
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
                    child: Text('直播授权 · 进行中班级学生',
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
            // 班级选择器（只显示进行中的班级）
            if (_activeClasses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    ChoiceChip(
                      label: const Text('全部', style: TextStyle(fontSize: 11)),
                      selected: _selectedClass == 'all',
                      selectedColor: NoirTokens.accent.withValues(alpha: 0.3),
                      onSelected: (_) {
                        setState(() => _selectedClass = 'all');
                        _filterStudents();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    ..._activeClasses.map((c) {
                      final name = c['name'] as String? ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(name, style: const TextStyle(fontSize: 11)),
                          selected: _selectedClass == name,
                          selectedColor: NoirTokens.accent.withValues(alpha: 0.3),
                          onSelected: (_) {
                            setState(() => _selectedClass = name);
                            _filterStudents();
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: NoirTokens.accent))
                  : _displayedStudents.isEmpty
                      ? Center(
                          child: Text('该班级暂无学生',
                              style: TextStyle(
                                  color: NoirTokens.paper
                                      .withValues(alpha: 0.5))))
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: _displayedStudents.length,
                          itemBuilder: (_, i) {
                            final s = _displayedStudents[i];
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
