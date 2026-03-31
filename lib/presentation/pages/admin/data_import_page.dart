import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/data_service.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/database_helper.dart';

class DataImportPage extends StatefulWidget {
  const DataImportPage({super.key});

  @override
  State<DataImportPage> createState() => _DataImportPageState();
}

class _DataImportPageState extends State<DataImportPage> {
  bool _isLoading = false;
  String? _message;
  bool _isSuccess = false;

  Future<void> _exportGrades() async {
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

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/grades_$timestamp.csv');
      await file.writeAsString(buffer.toString());

      setState(() {
        _isSuccess = true;
        _message = '成绩导出成功！\n文件位置: ${file.path}\n\n请使用Excel打开CSV文件';
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '导出失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importStudentsFromExcel() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量导入学生'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请按以下格式输入学生信息（每行一个学生）：'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '学号,姓名,密码\n'
                '2024001,张三,123456\n'
                '2024002,李四,123456',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '粘贴学生信息...',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Excel导入功能开发中，请手动添加学生')),
              );
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData() async {
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

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请将备份的JSON文件内容粘贴到下方：'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '粘贴JSON内容...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入JSON内容')),
                );
                return;
              }

              Navigator.pop(context);
              await _importData(controller.text);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _importData(String jsonString) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final success = await DataService.importFromJSON(jsonString);
      if (success) {
        setState(() {
          _isSuccess = true;
          _message = '导入成功！请重启应用';
        });
      } else {
        setState(() {
          _isSuccess = false;
          _message = '导入失败，请检查JSON格式';
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '导入失败: $e';
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

  void _showAddResourceDialog(String fileType, String targetDir) {
    final nameController = TextEditingController();
    final pathController = TextEditingController();

    pathController.text = 'assets/$targetDir/';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            '添加${fileType == 'video' ? 'video' : (fileType == 'pdf' ? 'PDF' : 'PPT')}资源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '文件名',
                hintText: '例如: 第一章 移动应用开发技术体系1.mp4',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              decoration: InputDecoration(
                labelText: '文件路径',
                hintText: 'assets/video/xxx.mp4',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '提示：请先将文件复制到 assets/$targetDir/ 目录',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;

              Navigator.pop(context);
              await _addResource(
                  fileType, nameController.text, pathController.text);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _addResource(
      String fileType, String fileName, String filePath) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final db = await DatabaseHelper.instance.database;

      final chapter = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

      await db.insert('resource_files', {
        'file_name': fileName,
        'file_path': filePath,
        'file_type': fileType,
        'chapter': chapter,
        'description': fileType == 'video'
            ? '视频教程'
            : (fileType == 'pdf' ? 'PDF课件' : 'PPT课件'),
      });

      setState(() {
        _isSuccess = true;
        _message = '成功添加 $fileName';
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '添加失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showUploadDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加学习资源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.orange),
              title: const Text('添加视频'),
              subtitle: const Text('保存到 assets/video/'),
              onTap: () {
                Navigator.pop(context);
                _showAddResourceDialog('video', 'video');
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('添加PDF'),
              subtitle: const Text('保存到 assets/pdf/'),
              onTap: () {
                Navigator.pop(context);
                _showAddResourceDialog('pdf', 'pdf');
              },
            ),
            ListTile(
              leading: const Icon(Icons.slideshow, color: Colors.blue),
              title: const Text('添加PPT'),
              subtitle: const Text('保存到 assets/ppt/'),
              onTap: () {
                Navigator.pop(context);
                _showAddResourceDialog('ppt', 'ppt');
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 导出卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.download, size: 48, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text('导出数据',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('将当前数据导出为JSON备份文件',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _exportData,
                    icon: const Icon(Icons.upload),
                    label: const Text('导出备份'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 导入卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.upload,
                      size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text('导入数据',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('从JSON备份文件导入数据',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _showImportDialog,
                    icon: const Icon(Icons.download),
                    label: const Text('导入备份'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 上传资源卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.cloud_upload,
                      size: 48, color: Colors.purple),
                  const SizedBox(height: 16),
                  const Text('上传学习资源',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('上传视频、PDF、PPT到指定目录',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _showUploadDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('上传资源'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 数据库位置卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.folder, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text('手动迁移',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('直接复制数据库文件进行迁移',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _showDBPath,
                    icon: const Icon(Icons.info),
                    label: const Text('查看数据库位置'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 成绩导出卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.assessment, size: 48, color: Colors.blue),
                  const SizedBox(height: 16),
                  const Text('导出成绩',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('将学生成绩导出为CSV文件',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _exportGrades,
                    icon: const Icon(Icons.download),
                    label: const Text('导出成绩'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 批量导入学生卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.group_add, size: 48, color: Colors.purple),
                  const SizedBox(height: 16),
                  const Text('批量导入学生',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('从文本批量添加学生账号',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _importStudentsFromExcel,
                    icon: const Icon(Icons.upload),
                    label: const Text('导入学生'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
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
}
