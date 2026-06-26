part of '../lab_tasks_page.dart';

class _MaterialCategory {
  final String title;
  final IconData icon;
  final Color color;
  final String assetDir;
  final String description;
  final bool teacherCanAdd;

  const _MaterialCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.assetDir,
    required this.description,
    this.teacherCanAdd = false,
  });
}

class _MaterialsTab extends StatefulWidget {
  final AuthService authService;
  const _MaterialsTab({required this.authService});

  @override
  State<_MaterialsTab> createState() => _MaterialsTabState();
}

class _MaterialsTabState extends State<_MaterialsTab> {
  static const _categories = [
    _MaterialCategory(
      title: '实验教程',
      icon: Icons.school,
      color: Color(0xFF1677FF),
      assetDir: 'data/实验/实验教程/',
      description: '6 个实验的详细步骤教程，包含核心任务、操作指南和成功标准',
    ),
    _MaterialCategory(
      title: '移动技术栈',
      icon: Icons.layers,
      color: Color(0xFF0958D9),
      assetDir: 'data/实验/移动技术栈/',
      description: '覆盖 Kotlin/Swift/Flutter/ArkUI/Uniapp/MAUI 等主流技术的完整手册',
    ),
    _MaterialCategory(
      title: '实验指导',
      icon: Icons.menu_book,
      color: Colors.teal,
      assetDir: 'data/实验/实验指导/',
      description: '实验指导书及 UML 设计文档参考',
      teacherCanAdd: true,
    ),
    _MaterialCategory(
      title: '报告模板',
      icon: Icons.assignment,
      color: Colors.orange,
      assetDir: 'data/实验/报告模板/',
      description: '每个实验对应的报告模板，按格式填写后提交',
    ),
  ];

  /// 每个分类下发现的文件列表
  final Map<int, List<_MaterialFile>> _files = {};
  /// 教师新增的指导文件（存储在本地）
  List<_MaterialFile> _localGuides = [];
  bool _isLoading = true;

  bool get _isTeacherOrAdmin =>
      widget.authService.isTeacher || widget.authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  /// Gitee 资料仓库配置
  static const _dataRepoOwner = 'osgisOne';
  static const _dataRepoName = 'mad-data';
  static const _dataRepoBranch = 'master';

  Future<void> _loadMaterials() async {
    setState(() => _isLoading = true);
    try {
      // 用 getTree 一次性获取整个仓库文件树（contents API 对中文路径返回空）
      final gitee = GiteeService();
      bool loadedFromGitee = false;

      try {
        final tree = await gitee.getTree(
          _dataRepoOwner,
          _dataRepoName,
          sha: _dataRepoBranch,
          recursive: true,
        );

        for (int i = 0; i < _categories.length; i++) {
          final dir = _categories[i].assetDir;
          // Gitee 仓库路径去掉 'data/' 前缀
          final giteePrefix = dir.startsWith('data/') ? dir.substring(5) : dir;

          final files = tree
              .where((e) {
                final path = e['path'] as String? ?? '';
                final type = e['type'] as String? ?? '';
                return type == 'blob' &&
                    path.startsWith(giteePrefix) &&
                    (path.endsWith('.md') || path.endsWith('.puml'));
              })
              .map((e) {
                final path = e['path'] as String;
                final name = path.split('/').last;
                final displayName = name
                    .replaceAll('_new.md', '')
                    .replaceAll('.md', '')
                    .replaceAll('.puml', '');
                return _MaterialFile(
                  giteePath: path,
                  fileName: name,
                  displayName: displayName,
                );
              })
              .toList();

          files.sort((a, b) => a.displayName.compareTo(b.displayName));
          _files[i] = files;
          if (files.isNotEmpty) loadedFromGitee = true;
        }
      } catch (e) {
        debugPrint('从 Gitee getTree 加载失败: $e');
      }

      // Gitee 全部失败时回退到本地 asset
      if (!loadedFromGitee) {
        debugPrint('Gitee 加载失败，回退到本地 asset');
        await _loadMaterialsFromAssets();
      }

      // 加载教师新增的本地指导文件
      await _loadLocalGuides();
    } catch (e) {
      debugPrint('加载实验材料失败: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// 从 Flutter assets 加载（离线 fallback）
  Future<void> _loadMaterialsFromAssets() async {
    try {
      Map<String, dynamic> manifest = {};
      try {
        final content = await rootBundle.loadString('AssetManifest.json');
        manifest = json.decode(content) as Map<String, dynamic>;
      } catch (e) { swallowDebug(e, tag: 'materials_tab'); }

      for (int i = 0; i < _categories.length; i++) {
        final dir = _categories[i].assetDir;
        var files = manifest.keys.where((k) {
          final decoded = Uri.decodeFull(k);
          return (decoded.startsWith(dir) || k.startsWith(dir)) &&
              (k.endsWith('.md') || k.endsWith('.puml'));
        }).map((assetPath) {
          final fileName = Uri.decodeFull(assetPath.split('/').last);
          final displayName = fileName
              .replaceAll('_new.md', '')
              .replaceAll('.md', '')
              .replaceAll('.puml', '');
          return _MaterialFile(
            assetPath: assetPath,
            fileName: fileName,
            displayName: displayName,
          );
        }).toList();

        if (files.isEmpty) {
          files = await _tryLoadKnownAssets(dir);
        }

        files.sort((a, b) => a.displayName.compareTo(b.displayName));
        _files[i] = files;
      }
    } catch (e) {
      debugPrint('本地 asset 加载失败: $e');
    }
  }

  Future<void> _loadLocalGuides() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final guidesDir = Directory('${dir.path}/lab_guides');
      if (await guidesDir.exists()) {
        final files = await guidesDir
            .list()
            .where((f) => f.path.endsWith('.md'))
            .toList();
        _localGuides = files
            .map((f) => _MaterialFile(
                  filePath: f.path,
                  fileName: f.path.split(Platform.pathSeparator).last,
                  displayName: f.path
                      .split(Platform.pathSeparator)
                      .last
                      .replaceAll('.md', ''),
                  isLocal: true,
                ))
            .toList();
      }
    } catch (e) { swallowDebug(e, tag: 'materials_tab'); }
  }

  /// 当 AssetManifest 匹配失败时，尝试直接加载已知的 asset 文件
  Future<List<_MaterialFile>> _tryLoadKnownAssets(String dir) async {
    // 硬编码的已知文件列表（与 data/实验/ 目录一致）
    const knownFiles = <String, List<String>>{
      'data/实验/实验教程/': [
        '实验一 开发环境搭建_new.md',
        '实验二 原生应用开发_new.md',
        '实验三 跨平台应用开发_new.md',
        '实验四 微信小程序开发_new.md',
        '实验五 鸿蒙多端应用开发_new.md',
        '实验六 跨平台综合项目实战_new.md',
      ],
      'data/实验/移动技术栈/': [
        'ArkUI开发鸿蒙多端应用技术栈手册.md',
        'Cordova开发混合应用技术栈手册.md',
        'Flutter开发跨平台应用技术栈手册.md',
        'Java开发Android应用技术栈手册.md',
        'Kotlin开发Android应用技术栈手册.md',
        'MAUI开发跨平台应用技术栈手册.md',
        'Swift开发iOS应用技术栈手册.md',
        'Uniapp开发跨平台应用技术栈手册.md',
        '嵌入式C-C++开发技术栈手册.md',
      ],
      'data/实验/实验指导/': [
        '移动应用开发实验指导书_new.md',
        'MVVM模型图_StarUML.puml',
        '交互顺序图_StarUML.puml',
        '组件模型图_StarUML.puml',
        '部署模型图_StarUML.puml',
      ],
      'data/实验/报告模板/': [
        '实验一 开发环境搭建报告模板.md',
        '实验二 原生应用开发报告模板.md',
        '实验三 跨平台应用开发报告模板.md',
        '实验四 微信小程序开发报告模板.md',
        '实验五 鸿蒙多端应用开发报告模板.md',
        '实验六 跨平台综合项目实战报告模板.md',
      ],
    };

    final fileNames = knownFiles[dir];
    if (fileNames == null) return [];

    final result = <_MaterialFile>[];
    for (final fn in fileNames) {
      final assetPath = '$dir$fn';
      // 验证 asset 确实存在
      try {
        await rootBundle.loadString(assetPath);
        final displayName = fn
            .replaceAll('_new.md', '')
            .replaceAll('.md', '')
            .replaceAll('.puml', '');
        result.add(_MaterialFile(
          assetPath: assetPath,
          fileName: fn,
          displayName: displayName,
        ));
      } catch (e, st) {
        swallowDebug(e, tag: 'materials_tab._tryLoadKnownAssets', stack: st);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadMaterials,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _categories.length,
        itemBuilder: (context, catIdx) {
          final cat = _categories[catIdx];
          final files = _files[catIdx] ?? [];

          // 实验指导分类合并本地文件
          final allFiles = catIdx == 2
              ? [...files, ..._localGuides]
              : files;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cat.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cat.icon, color: cat.color, size: 22),
              ),
              title: Row(
                children: [
                  Text(cat.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: cat.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${allFiles.length}',
                        style: TextStyle(fontSize: 11, color: cat.color)),
                  ),
                ],
              ),
              subtitle: Text(cat.description,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              initiallyExpanded: catIdx == 0,
              children: [
                ...allFiles.map((file) => _buildFileItem(file, cat)),
                // 教师/管理员可上传新材料到任意分类
                if (_isTeacherOrAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: OutlinedButton.icon(
                      onPressed: () => _uploadMaterial(catIdx),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text('上传${cat.title}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cat.color,
                      ),
                    ),
                  ),
                if (allFiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('暂无材料',
                        style: TextStyle(color: Colors.grey[400])),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileItem(_MaterialFile file, _MaterialCategory cat) {
    final agentId = _isTeacherOrAdmin ? 'lab_grading' : 'lab';

    return ListTile(
      dense: true,
      leading: Icon(
        file.isLocal ? Icons.note_add : Icons.article,
        color: file.isLocal ? Colors.teal : cat.color,
        size: 20,
      ),
      title: Text(
        file.displayName,
        style: const TextStyle(fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: file.isLocal
          ? const Text('教师自建',
              style: TextStyle(fontSize: 10, color: Colors.teal))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 预览按钮
          IconButton(
            icon: Icon(Icons.visibility, size: 18, color: cat.color),
            tooltip: '在线预览',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LabMaterialPreviewPage(
                    assetPath: file.assetPath,
                    filePath: file.filePath,
                    giteePath: file.giteePath,
                    title: file.displayName,
                    agentId: agentId,
                  ),
                ),
              );
            },
          ),
          // 下载按钮
          IconButton(
            icon: const Icon(Icons.download, size: 18, color: Colors.grey),
            tooltip: '下载到本地',
            onPressed: () => _downloadFile(file),
          ),
          // 教师：编辑 Gitee 文件
          if (_isTeacherOrAdmin && file.giteePath != null)
            IconButton(
              icon: Icon(Icons.edit, size: 18, color: cat.color),
              tooltip: '编辑',
              onPressed: () => _editGiteeFile(file),
            ),
          // 教师：删除 Gitee 文件或本地文件
          if (_isTeacherOrAdmin && (file.giteePath != null || file.isLocal))
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Colors.red),
              tooltip: '删除',
              onPressed: () {
                if (file.isLocal) {
                  _deleteLocalGuide(file);
                } else {
                  _deleteGiteeFile(file);
                }
              },
            ),
        ],
      ),
    );
  }

  /// 上传新材料到 Gitee 仓库
  Future<void> _uploadMaterial(int categoryIndex) async {
    final cat = _categories[categoryIndex];
    final giteeDir = (cat.assetDir.startsWith('data/')
            ? cat.assetDir.substring(5)
            : cat.assetDir)
        .replaceAll(RegExp(r'/$'), '');

    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('上传材料到「${cat.title}」'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '文件名 *',
                  hintText: '例如：实验补充指南',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Markdown 内容 *',
                  hintText: '支持 Markdown 格式...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('上传'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final title = titleCtrl.text.trim();
    final content = contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) return;

    try {
      final gitee = GiteeService();
      final fileName = '$title.md';
      final remotePath = '$giteeDir/$fileName';

      await gitee.createOrUpdateFile(
        owner: _dataRepoOwner,
        repo: _dataRepoName,
        path: remotePath,
        content: content,
        message: '上传实验材料: $fileName',
        branch: _dataRepoBranch,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('上传成功'), backgroundColor: Colors.green),
        );
        _loadMaterials(); // 刷新
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 编辑 Gitee 文件内容
  Future<void> _editGiteeFile(_MaterialFile file) async {
    if (file.giteePath == null) return;

    // 先加载现有内容
    String? currentContent;
    try {
      final gitee = GiteeService();
      currentContent = await gitee.getFileContent(
        _dataRepoOwner, _dataRepoName, file.giteePath!,
        ref: _dataRepoBranch,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!mounted) return;
    final contentCtrl = TextEditingController(text: currentContent ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑: ${file.displayName}'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: TextField(
            controller: contentCtrl,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Markdown 内容',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newContent = contentCtrl.text;

    try {
      final gitee = GiteeService();
      await gitee.createOrUpdateFile(
        owner: _dataRepoOwner,
        repo: _dataRepoName,
        path: file.giteePath!,
        content: newContent,
        message: '编辑实验材料: ${file.fileName}',
        branch: _dataRepoBranch,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 删除 Gitee 文件
  Future<void> _deleteGiteeFile(_MaterialFile file) async {
    if (file.giteePath == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${file.displayName}」吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final gitee = GiteeService();
      await gitee.deleteFile(
        owner: _dataRepoOwner,
        repo: _dataRepoName,
        path: file.giteePath!,
        message: '删除实验材料: ${file.fileName}',
        branch: _dataRepoBranch,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除'), backgroundColor: Colors.green),
        );
        _loadMaterials(); // 刷新
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadFile(_MaterialFile file) async {
    try {
      String content;
      if (file.giteePath != null) {
        final gitee = GiteeService();
        content = await gitee.getFileContent(
              _dataRepoOwner, _dataRepoName, file.giteePath!,
              ref: _dataRepoBranch,
            ) ??
            '';
      } else if (file.assetPath != null) {
        content = await rootBundle.loadString(file.assetPath!);
      } else {
        content = await File(file.filePath!).readAsString();
      }

      final dir = await getApplicationDocumentsDirectory();
      final labDir = Directory('${dir.path}/lab_materials');
      if (!await labDir.exists()) {
        await labDir.create(recursive: true);
      }

      final saveName =
          file.displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final saveFile = File('${labDir.path}/$saveName.md');
      await saveFile.writeAsString(content);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下载: ${saveFile.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteLocalGuide(_MaterialFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除"${file.displayName}"？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && file.filePath != null) {
      await File(file.filePath!).delete();
      await _loadLocalGuides();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    }
  }
}

class _MaterialFile {
  final String? assetPath;
  final String? filePath;
  /// Gitee 远程仓库中的路径（如 'data/实验/实验教程/xxx.md'）
  final String? giteePath;
  final String fileName;
  final String displayName;
  final bool isLocal;

  const _MaterialFile({
    this.assetPath,
    this.filePath,
    this.giteePath,
    required this.fileName,
    required this.displayName,
    this.isLocal = false,
  });
}
