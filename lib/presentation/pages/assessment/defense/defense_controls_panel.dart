import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/design/noir_tokens.dart';

/// 答辩直播控制面板。
class DefenseControlsPanel extends StatelessWidget {
  final bool isBroadcasting;
  final bool isWinCaptureOn;
  final bool isPhoneCaptureOn;
  final bool isCameraOn;
  final String layoutMode;
  final String serverIp;
  final int serverPort;
  final int viewerCount;
  final bool showTeacherCaptureControls;
  final bool showWinCaptureControl;
  final bool showPhoneCaptureControl;
  final VoidCallback onToggleBroadcast;
  final VoidCallback onToggleWinCapture;
  final VoidCallback? onTogglePhoneCapture;
  final VoidCallback onToggleCamera;
  final ValueChanged<String> onLayoutChanged;

  const DefenseControlsPanel({
    super.key,
    required this.isBroadcasting,
    required this.isWinCaptureOn,
    required this.isPhoneCaptureOn,
    required this.isCameraOn,
    required this.layoutMode,
    required this.serverIp,
    required this.serverPort,
    required this.viewerCount,
    this.showTeacherCaptureControls = true,
    this.showWinCaptureControl = true,
    this.showPhoneCaptureControl = false,
    required this.onToggleBroadcast,
    required this.onToggleWinCapture,
    this.onTogglePhoneCapture,
    required this.onToggleCamera,
    required this.onLayoutChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirTokens.ink.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NoirTokens.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              _dot(isBroadcasting),
              const SizedBox(width: 8),
              Text(isBroadcasting ? '直播中' : '未开播',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isBroadcasting ? Colors.green : Colors.grey)),
              const Spacer(),
              Text('$viewerCount 观看',
                  style: TextStyle(
                      color: NoirTokens.paper.withValues(alpha: 0.5),
                      fontSize: 12)),
            ]),
            const SizedBox(height: 12),
            if (isBroadcasting)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                    color: NoirTokens.inkDeep,
                    borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  const Icon(Icons.cast, size: 14, color: NoirTokens.accent),
                  const SizedBox(width: 6),
                  Text('http://$serverIp:$serverPort',
                      style: const TextStyle(
                          color: NoirTokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(
                            text: 'http://$serverIp:$serverPort'));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('已复制')));
                      },
                      child: Icon(Icons.copy,
                          size: 14,
                          color: NoirTokens.paper.withValues(alpha: 0.5))),
                ]),
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _btn(
                  isBroadcasting ? Icons.stop_circle : Icons.play_circle,
                  isBroadcasting ? '停止' : '开始',
                  isBroadcasting ? Colors.red : Colors.green,
                  onToggleBroadcast),
              if (showTeacherCaptureControls) ...[
                if (showWinCaptureControl)
                  _btn(
                      Icons.desktop_windows,
                      '桌面${isWinCaptureOn ? ' ✓' : ''}',
                      isWinCaptureOn ? Colors.blue : Colors.grey,
                      onToggleWinCapture),
                if (showPhoneCaptureControl)
                  _btn(
                      Icons.phone_android,
                      '手机${isPhoneCaptureOn ? ' ✓' : ''}',
                      isPhoneCaptureOn ? Colors.blue : Colors.grey,
                      onTogglePhoneCapture),
                _btn(Icons.videocam, '摄像头${isCameraOn ? ' ✓' : ''}',
                    isCameraOn ? Colors.blue : Colors.grey, onToggleCamera),
              ],
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Text('布局：',
                  style: TextStyle(
                      color: NoirTokens.paper.withValues(alpha: 0.6),
                      fontSize: 12)),
              const SizedBox(width: 8),
              ...['dual', 'winOnly', 'phoneOnly'].map((m) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                          m == 'dual'
                              ? '并排'
                              : m == 'winOnly'
                                  ? '仅桌面'
                                  : '仅手机',
                          style: const TextStyle(fontSize: 11)),
                      selected: layoutMode == m,
                      selectedColor: NoirTokens.accent.withValues(alpha: 0.3),
                      onSelected: (_) => onLayoutChanged(m),
                      visualDensity: VisualDensity.compact,
                    ),
                  )),
            ]),
          ]),
    );
  }

  Widget _dot(bool on) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? Colors.green : Colors.grey,
          boxShadow: on
              ? [
                  BoxShadow(
                      color: Colors.green.withValues(alpha: 0.5), blurRadius: 8)
                ]
              : null,
        ),
      );

  Widget _btn(IconData icon, String label, Color color, VoidCallback? onTap,
      {bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
