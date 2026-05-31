import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/design/noir_tokens.dart';
import '../../core/error_handler.dart';
import '../../services/live_broadcast_service.dart';

/// 直播观看面板 — 展示正在进行的答辩直播快照（每隔几秒自动刷新）。
///
/// 受限于无实时服务器，这里展示的是开播端每 ~4s 上传到 Gitee 的画面快照，
/// 而非连续视频流；标注"准实时"提示用户。
class LiveViewerSheet extends StatelessWidget {
  final List<LiveSession> sessions;
  const LiveViewerSheet({super.key, required this.sessions});

  static void show(BuildContext context, List<LiveSession> sessions) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NoirTokens.ink,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LiveViewerSheet(sessions: sessions),
    );
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
                  const Icon(Icons.sensors, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text('答辩直播（准实时快照）',
                      style: TextStyle(
                          color: NoirTokens.paper,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: sessions.length,
                itemBuilder: (_, i) => _LiveTile(session: sessions[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 单场直播：标题 + 自动刷新的快照图。
class _LiveTile extends StatefulWidget {
  final LiveSession session;
  const _LiveTile({required this.session});

  @override
  State<_LiveTile> createState() => _LiveTileState();
}

class _LiveTileState extends State<_LiveTile> {
  String? _url;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // 每 5s 刷新一次快照（在 url 后加时间戳破缓存）
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final base =
          await LiveBroadcastService.instance.snapshotUrl(widget.session);
      if (mounted) {
        setState(() =>
            _url = '$base&_t=${DateTime.now().millisecondsSinceEpoch}');
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LiveViewer.refresh', stack: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Card(
      color: NoirTokens.inkDeep,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: NoirTokens.accent.withValues(alpha: 0.2),
                  child: Text(
                    s.userName.isNotEmpty ? s.userName.characters.first : '?',
                    style: const TextStyle(
                        color: NoirTokens.accent,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.userName,
                      style: TextStyle(
                          color: NoirTokens.paper,
                          fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.red, size: 8),
                      SizedBox(width: 4),
                      Text('LIVE',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: _url == null
                  ? Container(
                      color: Colors.black,
                      child: const Center(
                          child: CircularProgressIndicator(
                              color: NoirTokens.accent)),
                    )
                  : Image.network(
                      _url!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.black,
                        child: Center(
                          child: Text('等待画面…',
                              style: TextStyle(
                                  color: NoirTokens.paper
                                      .withValues(alpha: 0.5))),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
