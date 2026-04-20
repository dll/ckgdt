import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// QR 码扫描页面 — 移动端扫码连接桌面端
///
/// 扫描成功后将 QR 码内容（JSON 字符串）通过 Navigator.pop 返回。
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _hasResult = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasResult) return;
    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        // 校验是否是我们的 QR 码（包含 app: MADKG）
        if (value.contains('MADKG') || value.contains('qrToken')) {
          _hasResult = true;
          Navigator.pop(context, value);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码连接'),
        actions: [
          // 闪光灯切换
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: '闪光灯',
            onPressed: () => _controller.toggleTorch(),
          ),
          // 前后摄像头切换
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: '切换摄像头',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 相机预览
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // 扫描框叠加层
          CustomPaint(
            painter: _ScanOverlayPainter(
              borderColor: theme.colorScheme.primary,
            ),
            child: Container(),
          ),

          // 底部提示
          Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    '将二维码放入框内扫描',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _showManualInput(),
                  child: const Text(
                    '手动输入连接地址',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showManualInput() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '服务器地址',
            hintText: 'http://192.168.1.x:8765',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                // 构造一个兼容的 QR 数据格式
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  // 手动连接不经过 QR 登录流程，直接返回 URL
                  Navigator.pop(context, url);
                }
              }
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }
}

/// 扫描框叠加层画笔
class _ScanOverlayPainter extends CustomPainter {
  final Color borderColor;

  _ScanOverlayPainter({required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final scanSize = size.width * 0.7;
    final left = (size.width - scanSize) / 2;
    final top = (size.height - scanSize) / 2.5;

    // 半透明遮罩
    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);

    // 上方遮罩
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), maskPaint);
    // 下方遮罩
    canvas.drawRect(
        Rect.fromLTWH(0, top + scanSize, size.width, size.height - top - scanSize),
        maskPaint);
    // 左侧遮罩
    canvas.drawRect(
        Rect.fromLTWH(0, top, left, scanSize), maskPaint);
    // 右侧遮罩
    canvas.drawRect(
        Rect.fromLTWH(left + scanSize, top, size.width - left - scanSize, scanSize),
        maskPaint);

    // 扫描框四角
    final cornerPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const cornerLen = 24.0;

    // 左上
    canvas.drawLine(Offset(left, top), Offset(left + cornerLen, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left, top + cornerLen), cornerPaint);
    // 右上
    canvas.drawLine(
        Offset(left + scanSize, top), Offset(left + scanSize - cornerLen, top), cornerPaint);
    canvas.drawLine(
        Offset(left + scanSize, top), Offset(left + scanSize, top + cornerLen), cornerPaint);
    // 左下
    canvas.drawLine(
        Offset(left, top + scanSize), Offset(left + cornerLen, top + scanSize), cornerPaint);
    canvas.drawLine(
        Offset(left, top + scanSize), Offset(left, top + scanSize - cornerLen), cornerPaint);
    // 右下
    canvas.drawLine(Offset(left + scanSize, top + scanSize),
        Offset(left + scanSize - cornerLen, top + scanSize), cornerPaint);
    canvas.drawLine(Offset(left + scanSize, top + scanSize),
        Offset(left + scanSize, top + scanSize - cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter old) =>
      old.borderColor != borderColor;
}
