import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../../data/local/feedback_dao.dart';
import '../../../services/auth_service.dart';

/// 全局截图 Key — 在 main.dart 中用 RepaintBoundary 包裹应用内容
final GlobalKey feedbackScreenshotKey = GlobalKey();

/// 问题反馈对话框
class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key});

  /// 弹出反馈对话框
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const FeedbackDialog(),
    );
  }

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _contentController = TextEditingController();
  final _suggestionController = TextEditingController();
  final _feedbackDao = FeedbackDao();
  final _authService = AuthService();

  String? _screenshotPath;
  String? _attachmentPath;
  bool _isSubmitting = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    // 自动截取当前页面截图
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureScreenshot();
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _suggestionController.dispose();
    super.dispose();
  }

  /// 使用 RepaintBoundary 截取当前界面
  Future<void> _captureScreenshot() async {
    setState(() => _isCapturing = true);
    try {
      final boundary = feedbackScreenshotKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('FeedbackDialog: RepaintBoundary not found');
        setState(() => _isCapturing = false);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        setState(() => _isCapturing = false);
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final feedbackDir = Directory('${dir.path}/feedback_images');
      if (!await feedbackDir.exists()) await feedbackDir.create(recursive: true);
      final file = File(
          '${feedbackDir.path}/feedback_screenshot_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        setState(() {
          _screenshotPath = file.path;
          _isCapturing = false;
        });
      }
    } catch (e) {
      debugPrint('FeedbackDialog: Screenshot error: $e');
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// 从文件选择器添加图片附件
  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          // 复制到应用持久化目录
          final dir = await getApplicationDocumentsDirectory();
          final feedbackDir = Directory('${dir.path}/feedback_images');
          if (!await feedbackDir.exists()) await feedbackDir.create(recursive: true);
          final destPath =
              '${feedbackDir.path}/feedback_attach_${DateTime.now().millisecondsSinceEpoch}.${file.extension ?? 'png'}';
          await File(file.path!).copy(destPath);
          if (mounted) setState(() => _attachmentPath = destPath);
        }
      }
    } catch (e) {
      debugPrint('FeedbackDialog: pickImage error: $e');
    }
  }

  /// 提交反馈
  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写问题描述')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = _authService.currentUser;

      // 合并截图和附件路径
      final paths = <String>[];
      if (_screenshotPath != null) paths.add(_screenshotPath!);
      if (_attachmentPath != null) paths.add(_attachmentPath!);
      final screenshotStr = paths.isNotEmpty ? paths.join('|') : null;

      await _feedbackDao.addFeedback(
        userId: user?.userId ?? 'unknown',
        userName: user?.realName ?? user?.userId,
        userRole: user?.role ?? 'student',
        content: content,
        suggestion: _suggestionController.text.trim().isNotEmpty
            ? _suggestionController.text.trim()
            : null,
        screenshotPath: screenshotStr,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('感谢您的反馈！我们会认真处理每一条意见。'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 拖拽指示器
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // 标题
                  Row(
                    children: [
                      Icon(Icons.feedback_outlined, color: primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        '问题反馈',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '感谢您帮助我们改进系统！请描述您遇到的问题或提出改进建议。',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 用户信息（只读）
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: primaryColor,
                          child: Text(
                            (user?.realName ?? user?.userId ?? 'U')
                                .substring(0, 1),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.realName ?? user?.userId ?? '未知用户',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                '${user?.role == 'admin' ? '管理员' : user?.role == 'teacher' ? '教师' : '学生'}'
                                '  |  ${DateTime.now().toString().substring(0, 16)}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 问题描述
                  Text('问题描述 *',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.grey[800])),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _contentController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: '请详细描述您遇到的问题，例如：\n• 在哪个页面？\n• 做了什么操作？\n• 出现了什么异常？',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 改进建议
                  Text('改进建议',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.grey[800])),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _suggestionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: '您认为可以如何改进？（可选）',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 截图预览
                  Text('截图',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.grey[800])),
                  const SizedBox(height: 6),

                  Row(
                    children: [
                      // 自动截图预览
                      Expanded(
                        child: _buildScreenshotPreview(
                          path: _screenshotPath,
                          label: '自动截图',
                          isLoading: _isCapturing,
                          onRetake: _captureScreenshot,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 手动添加图片
                      Expanded(
                        child: _buildScreenshotPreview(
                          path: _attachmentPath,
                          label: '添加图片',
                          isLoading: false,
                          onAdd: _pickImage,
                          onRemove: () =>
                              setState(() => _attachmentPath = null),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 提交按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send),
                      label: Text(_isSubmitting ? '提交中...' : '提交反馈'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '您的反馈对我们非常重要，感谢您的支持！',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建截图预览卡片
  Widget _buildScreenshotPreview({
    required String? path,
    required String label,
    required bool isLoading,
    VoidCallback? onRetake,
    VoidCallback? onAdd,
    VoidCallback? onRemove,
  }) {
    return GestureDetector(
      onTap: path == null ? (onAdd ?? onRetake) : null,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.grey[300]!,
            style: path == null ? BorderStyle.solid : BorderStyle.none,
          ),
        ),
        child: isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(height: 6),
                    Text('截图中...', style: TextStyle(fontSize: 11)),
                  ],
                ),
              )
            : path != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image, size: 32)),
                        ),
                      ),
                      // 查看/删除按钮
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onRetake != null)
                              _miniButton(Icons.refresh, onRetake),
                            if (onRemove != null)
                              _miniButton(Icons.close, onRemove),
                          ],
                        ),
                      ),
                      // 标签
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10)),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          onAdd != null
                              ? Icons.add_photo_alternate
                              : Icons.camera_alt,
                          color: Colors.grey[400],
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          onAdd != null ? '点击添加' : '点击截图',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _miniButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }
}
