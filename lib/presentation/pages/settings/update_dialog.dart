import 'package:flutter/material.dart';
import '../../../core/build_info.dart';
import '../../../services/update_service.dart';
import '../../widgets/back_button_bar.dart';

/// 更新相关对话框集合
class UpdateDialog {
  UpdateDialog._();

  static final UpdateService _updateService = UpdateService();

  static Future<bool?> showUpdateAvailable(
    BuildContext context,
    UpdateInfo info,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateAvailableDialog(info: info),
    );
  }

  static Future<bool?> showCheckUpdate(BuildContext context) async {
    final info = await _updateService.checkForUpdate();
    if (!context.mounted) return null;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('当前已是最新版本'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '知道了',
            onPressed: () {},
          ),
        ),
      );
      return null;
    }
    return showUpdateAvailable(context, info);
  }
}

class _UpdateAvailableDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateAvailableDialog({required this.info});

  @override
  State<_UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<_UpdateAvailableDialog> {
  final UpdateService _updateService = UpdateService();
  bool _isDownloading = false;
  double _progress = 0;
  String? _filePath;
  String? _error;

  String get _currentVersion => BuildInfo.appVersion;
  String get _newVersion => widget.info.version;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _error = null;
    });
    final path = await _updateService.downloadUpdate(
      widget.info,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (path != null) {
      setState(() {
        _filePath = path;
        _isDownloading = false;
        _progress = 1.0;
      });
    } else {
      setState(() {
        _error = '下载失败，请稍后重试';
        _isDownloading = false;
      });
    }
  }

  Future<void> _install() async {
    if (_filePath == null) return;
    final success = await _updateService.installUpdate(_filePath!);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('更新文件已打开，请按照系统提示完成安装'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      final dir = await _updateService.getDownloadDirectoryPath();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已下载到：$dir，请手动安装'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openReleasePage() async {
    await _updateService.openReleasePage();
  }

  Future<void> _ignore() async {
    await _updateService.ignoreVersion(widget.info.version);
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('发现新版本')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVersionInfo(theme),
            const SizedBox(height: 12),
            if (_error != null) _buildError(theme),
            if (_isDownloading) _buildProgress(theme),
            if (_filePath != null && !_isDownloading)
              _buildDownloaded(theme),
            if (!_isDownloading && _filePath == null && _error == null)
              _buildReleaseNotes(theme),
          ],
        ),
      ),
      actions: _buildActions(theme),
    );
  }

  Widget _buildVersionInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前版本',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'v$_currentVersion',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.arrow_forward,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最新版本',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'v$_newVersion',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (widget.info.assetSize > 0)
            Text(
              widget.info.formattedSize,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReleaseNotes(ThemeData theme) {
    final notes = widget.info.releaseNotes;
    final lines = notes.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '更新内容',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            child: Text(
              lines.take(30).join('\n'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: _progress > 0 ? _progress : null,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 6),
        Text(
          _progress > 0
              ? '下载中 ${(_progress * 100).toStringAsFixed(0)}%'
              : '正在准备下载...',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloaded(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '下载完成（${widget.info.formattedSize}）',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: theme.colorScheme.error, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(ThemeData theme) {
    if (_filePath != null && !_isDownloading) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.install_mobile, size: 18),
          label: const Text('立即安装'),
          onPressed: _install,
        ),
      ];
    }
    if (_isDownloading) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('后台下载'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _ignore,
        child: const Text('忽略此版本'),
      ),
      TextButton(
        onPressed: _openReleasePage,
        child: const Text('查看详情'),
      ),
      if (!_isDownloading)
        FilledButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text('立即更新'),
          onPressed: _startDownload,
        ),
    ];
  }
}

/// 更新进度页面（全屏版本，支持在通知中跳转后使用）
class UpdateProgressPage extends StatefulWidget {
  final UpdateInfo info;
  const UpdateProgressPage({super.key, required this.info});

  @override
  State<UpdateProgressPage> createState() => _UpdateProgressPageState();
}

class _UpdateProgressPageState extends State<UpdateProgressPage> {
  final UpdateService _updateService = UpdateService();
  bool _isDownloading = false;
  double _progress = 0;
  String? _filePath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _error = null;
    });
    final path = await _updateService.downloadUpdate(
      widget.info,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (path != null) {
      setState(() {
        _filePath = path;
        _isDownloading = false;
        _progress = 1.0;
      });
    } else {
      setState(() {
        _error = '下载失败，请稍后重试或前往 GitHub 手动下载';
        _isDownloading = false;
      });
    }
  }

  Future<void> _install() async {
    if (_filePath == null) return;
    final success = await _updateService.installUpdate(_filePath!);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('更新文件已打开，请按照系统提示完成安装'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final dir = await _updateService.getDownloadDirectoryPath();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已下载到：$dir，请手动安装'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: BackButtonBar(title: '版本更新'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isDownloading
                    ? Icons.downloading
                    : _error != null
                        ? Icons.error_outline
                        : Icons.check_circle,
                size: 64,
                color: _isDownloading
                    ? theme.colorScheme.primary
                    : _error != null
                        ? theme.colorScheme.error
                        : Colors.green,
              ),
              const SizedBox(height: 16),
              Text(
                'v${widget.info.version} 更新',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isDownloading
                    ? _progress > 0
                        ? '下载中 ${(_progress * 100).toStringAsFixed(0)}%'
                        : '正在准备下载...'
                    : _error ?? '下载完成',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.outline,
                ),
              ),
              if (_isDownloading) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(
                  '请勿关闭此页面',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline.withValues(alpha: 0.6),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              if (_filePath != null && !_isDownloading)
                FilledButton.icon(
                  icon: const Icon(Icons.install_mobile, size: 20),
                  label: const Text('立即安装'),
                  onPressed: _install,
                ),
              if (_error != null)
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 20),
                  label: const Text('前往 GitHub 下载'),
                  onPressed: () => _updateService.openReleasePage(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
