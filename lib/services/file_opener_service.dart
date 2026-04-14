import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';

// 条件导入：仅在原生平台导入 dart:io 相关功能
import 'file_opener_service_stub.dart'
    if (dart.library.io) 'file_opener_service_native.dart' as impl;

/// 文件打开服务
///
/// 提供从 assets 或本地路径打开文件（PDF、PPT、视频等）的工具方法。
/// - Web 平台：仅显示提示信息，不支持文件打开
/// - 原生平台：从 assets 复制到临时目录后用系统应用打开
class FileOpenerService {
  /// 智能打开文件 — 自动判断 asset 路径还是设备路径
  static Future<void> openFile(
    BuildContext context,
    String filePath,
    String fileName,
  ) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Web 平台暂不支持打开文件: $fileName'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 判断是否为 asset 路径
    final isAssetPath = filePath.startsWith('assets/') ||
        filePath.startsWith('assets\\');

    if (isAssetPath) {
      await _openAssetFile(context, filePath, fileName);
    } else {
      // 设备上的绝对路径，直接打开
      await openExternalFile(context, filePath);
    }
  }

  /// 从 assets 打开文件（内部方法）
  static Future<void> _openAssetFile(
    BuildContext context,
    String assetPath,
    String fileName,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // 显示加载提示
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('正在准备文件: $fileName')),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      // 获取临时目录并复制文件
      final tempFilePath = await impl.copyAssetToTemp(assetPath, fileName);
      if (tempFilePath == null) {
        scaffoldMessenger.hideCurrentSnackBar();
        _showAssetNotFoundMessage(scaffoldMessenger, fileName);
        return;
      }

      scaffoldMessenger.hideCurrentSnackBar();
      await impl.openAndHandleResult(scaffoldMessenger, tempFilePath, fileName);
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();

      if (e is FlutterError || e.toString().contains('Unable to load asset')) {
        _showAssetNotFoundMessage(scaffoldMessenger, fileName);
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('打开文件失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 根据角色显示不同的 asset 未找到提示
  static void _showAssetNotFoundMessage(
    ScaffoldMessengerState messenger,
    String fileName,
  ) {
    final authService = AuthService();
    final isAdmin = authService.isAdmin;
    final isTeacher = authService.isTeacher;

    String message;
    if (isAdmin) {
      message = '文件「$fileName」尚未上传。\n'
          '请前往【管理】→【数据管理】→【上传资源】选择文件上传。';
    } else if (isTeacher) {
      message = '文件「$fileName」尚未上传，请联系管理员上传该资源。';
    } else {
      message = '文件「$fileName」尚未上传，请联系教师或管理员获取。';
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// 直接打开设备上已有的文件
  static Future<void> openExternalFile(
    BuildContext context,
    String filePath,
  ) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web 平台暂不支持打开本地文件'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await impl.openExternalFileNative(scaffoldMessenger, filePath);
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('打开文件失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 清除文件缓存
  static Future<void> clearCache() async {
    if (kIsWeb) return;
    await impl.clearCacheNative();
  }
}
