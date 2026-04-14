import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../services/data_service.dart';
import '../../../services/auth_service.dart';
import '../../../core/constants/role_guard.dart';
import '../../../data/local/quiz_dao.dart';

// 条件导入
import 'data_import_page_stub.dart'
    if (dart.library.io) 'data_import_page_native.dart' as impl;

class DataImportPage extends StatefulWidget {
  const DataImportPage({super.key});

  @override
  State<DataImportPage> createState() => _DataImportPageState();
}

class _DataImportPageState extends State<DataImportPage> {
  bool _isLoading = false;
  String? _message;
  bool _isSuccess = false;

  // ── 成绩导出 ──────────────────────────────────────────────────────────────

  Future<void> _exportGrades() async {
    if (kIsWeb) {
      setState(() {
        _isSuccess = false;
        _message = 'Web 平台暂不支持成绩导出到文件';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final quizDao = QuizDao();
      final results = await quizDao.getAllQuizResults();

      if (results.isEmpty) {
        setState(() {
          _isSuccess = false;
          _message = '暂无成绩数据';
        });
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('学生ID,章节,分数,正确题数,总题数,正确率,完成时间');

      for (final result in results) {
        final accuracy = result.numTotal > 0
            ? (result.numCorrect / result.numTotal * 100).toStringAsFixed(1)
            : '0.0';
        buffer.writeln(
            '${result.userId},${result.chapter ?? "未知"},${result.score},${result.numCorrect},${result.numTotal},$accuracy%,${result.completedAt ?? ""}');
      }

      final filePath = await impl.saveStringToFile(buffer.toString(), 'grades');
      if (filePath != null) {
        setState(() {
          _isSuccess = true;
          _message = '成绩导出成功！\n文件位置: $filePath\n\n请使用Excel打开CSV文件';
        });
      } else {
        setState(() {
          _isSuccess = false;
          _message = '导出失败';
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '导出失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── 从 xlsx 导入学生 ──────────────────────────────────────────────────────

  Future<void> _importStudentsFromXlsx() async {
    if (kIsWeb) {
      setState(() {
        _isSuccess = false;
        _message = 'Web 平台暂不支持 xlsx 文件导入';
      });
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        dialogTitle: '选择学生名单 xlsx 文件',
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      setState(() {
        _isLoading = true;
        _message = null;
      });

      final importResult = await impl.importStudentsFromFile(filePath);
      setState(() {
        _isSuccess = importResult['success'] as bool;
        _message = importResult['message'] as String;
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '导入失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 安全读取单元格值 — 保留给 native 实现使用

  // ── JSON 数据导出 ─────────────────────────────────────────────────────────

  Future<void> _exportData() async {
    if (kIsWeb) {
      setState(() {
        _isSuccess = false;
        _message = 'Web 平台暂不支持数据导出到文件';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final path = await DataService.exportToJSON();
      if (path != null) {
        setState(() {
          _isSuccess = true;
          _message = '导出成功！\n文件位置: $path\n\n请将此文件复制到电脑备份';
        });
      } else {
        setState(() {
          _isSuccess = false;
          _message = '导出失败';
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '导出失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── JSON 数据导入 ─────────────────────────────────────────────────────────

  Future<void> _importJsonFromFile() async {
    if (kIsWeb) {
      setState(() {
        _isSuccess = false;
        _message = 'Web 平台暂不支持从文件导入数据';
      });
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择 JSON 备份文件',
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      setState(() {
        _isLoading = true;
        _message = null;
      });

      final jsonString = await impl.readFileAsString(filePath);
      if (jsonString == null) {
        setState(() {
          _isSuccess = false;
          _message = '无法读取文件';
        });
        return;
      }
      final success = await DataService.importFromJSON(jsonString);
      setState(() {
        _isSuccess = success;
        _message = success ? '导入成功！请重启应用' : '导入失败，请检查JSON格式';
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '导入失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── 上传资源文件（file_picker 选择） ──────────────────────────────────────

  void _showUploadDialog() {
    if (kIsWeb) {
      setState(() {
        _isSuccess = false;
        _message = 'Web 平台暂不支持上传资源文件';
      });
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('上传学习资源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.orange),
              title: const Text('上传视频'),
              subtitle: const Text('选择 mp4/avi/mkv 文件'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadResource('video', ['mp4', 'avi', 'mkv', 'mov']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('上传 PDF'),
              subtitle: const Text('选择 pdf 文件'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadResource('pdf', ['pdf']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.slideshow, color: Colors.blue),
              title: const Text('上传 PPT'),
              subtitle: const Text('选择 pptx/ppt 文件'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadResource('ppt', ['pptx', 'ppt']);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 通过 file_picker 选择文件并上传（复制到应用文档目录）
  Future<void> _pickAndUploadResource(
      String fileType, List<String> extensions) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        allowMultiple: true,
        dialogTitle: '选择${fileType == 'video' ? '视频' : (fileType == 'pdf' ? 'PDF' : 'PPT')}文件',
      );
      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isLoading = true;
        _message = null;
      });

      final uploadResult = await impl.uploadResourceFiles(result.files, fileType);
      setState(() {
        _isSuccess = uploadResult['success'] as bool;
        _message = uploadResult['message'] as String;
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '上传失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showDBPath() async {
    final path = await DataService.getDBPath();
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('数据库位置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('数据库文件位置：'),
              const SizedBox(height: 8),
              SelectableText(path, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              const Text('使用方法：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('1. 复制原项目的 learning_data.db 到此位置'),
              const Text('2. 重命名为 knowledge_graph.db'),
              const Text('3. 重启应用'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 权限守卫：仅管理员可访问
    final role = AuthService().currentUser?.role ?? 'student';
    if (!RoleGuard.canImportData(role)) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('无权限访问', style: TextStyle(fontSize: 18, color: Colors.grey)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 上传资源卡片（最重要，放最上面）
          _buildActionCard(
            icon: Icons.cloud_upload,
            iconColor: Colors.purple,
            title: '上传学习资源',
            desc: '选择视频、PDF、PPT文件上传',
            buttonText: '选择文件上传',
            buttonColor: Colors.purple,
            onPressed: _isLoading ? null : _showUploadDialog,
          ),
          const SizedBox(height: 16),

          // 批量导入学生卡片
          _buildActionCard(
            icon: Icons.group_add,
            iconColor: Colors.teal,
            title: '导入学生名单',
            desc: '从 xlsx 文件批量导入学生（支持学号、姓名、角色等列）',
            buttonText: '选择 xlsx 文件',
            buttonColor: Colors.teal,
            onPressed: _isLoading ? null : _importStudentsFromXlsx,
          ),
          const SizedBox(height: 16),

          // 成绩导出卡片
          _buildActionCard(
            icon: Icons.assessment,
            iconColor: Colors.blue,
            title: '导出成绩',
            desc: '将学生成绩导出为 CSV 文件',
            buttonText: '导出成绩',
            buttonColor: Colors.blue,
            onPressed: _isLoading ? null : _exportGrades,
          ),
          const SizedBox(height: 16),

          // 导出备份卡片
          _buildActionCard(
            icon: Icons.download,
            iconColor: Colors.green,
            title: '导出数据备份',
            desc: '将全部数据导出为 JSON 备份文件',
            buttonText: '导出备份',
            buttonColor: Colors.green,
            onPressed: _isLoading ? null : _exportData,
          ),
          const SizedBox(height: 16),

          // 导入备份卡片
          _buildActionCard(
            icon: Icons.upload,
            iconColor: Theme.of(context).colorScheme.primary,
            title: '导入数据备份',
            desc: '从 JSON 备份文件恢复数据',
            buttonText: '选择 JSON 文件',
            buttonColor: Theme.of(context).colorScheme.primary,
            onPressed: _isLoading ? null : _importJsonFromFile,
          ),
          const SizedBox(height: 16),

          // 数据库位置卡片
          _buildActionCard(
            icon: Icons.folder,
            iconColor: Colors.orange,
            title: '手动迁移',
            desc: '直接复制数据库文件进行迁移',
            buttonText: '查看数据库位置',
            buttonColor: Colors.orange,
            onPressed: _showDBPath,
            isOutlined: true,
          ),

          // 消息提示
          if (_message != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isSuccess ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: _isSuccess ? Colors.green : Colors.red),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_isSuccess ? Icons.check_circle : Icons.error,
                      color: _isSuccess ? Colors.green : Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_message!)),
                ],
              ),
            ),
          ],

          // 加载指示器
          if (_isLoading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required String buttonText,
    required Color buttonColor,
    required VoidCallback? onPressed,
    bool isOutlined = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(desc,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            isOutlined
                ? OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.info),
                    label: Text(buttonText),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.file_upload),
                    label: Text(buttonText),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
