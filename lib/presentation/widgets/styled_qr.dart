import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 带纸感外框的二维码组件 — 统一三处 QR 块（同步服务器 / Web 公网入口 / 登录扫码）
/// 的视觉语言。外框样式由调用方通过颜色/半径参数定制，QR 渲染本身由 [QrImageView] 完成。
class StyledQr extends StatelessWidget {
  final String data;
  final double size;
  final Color background;
  final Color borderColor;
  final Color eyeColor;
  final Color moduleColor;
  final double cornerRadius;
  final double padding;

  const StyledQr({
    super.key,
    required this.data,
    this.size = 160,
    this.background = Colors.white,
    this.borderColor = const Color(0x33000000),
    this.eyeColor = const Color(0xFF1A1A1A),
    this.moduleColor = const Color(0xFF1A1A1A),
    this.cornerRadius = 12,
    this.padding = 10,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(cornerRadius),
          border: Border.all(color: borderColor),
        ),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: eyeColor,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: moduleColor,
          ),
        ),
      ),
    );
  }
}
