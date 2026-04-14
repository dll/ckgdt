import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../services/file_opener_service.dart';

/// 应用内视频播放器（基于 media_kit，支持 Windows 桌面）
/// 支持播放/暂停、进度拖动、倍速、快进快退、全屏
class InAppVideoPlayerPage extends StatefulWidget {
  final String filePath;
  final String title;

  const InAppVideoPlayerPage({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<InAppVideoPlayerPage> createState() => _InAppVideoPlayerPageState();
}

class _InAppVideoPlayerPageState extends State<InAppVideoPlayerPage> {
  late final Player _player;
  late final VideoController _videoController;
  String? _error;
  bool _showControls = true;
  double _playbackSpeed = 1.0;

  // 播放状态
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _initPlayer();
  }

  void _initPlayer() {
    // 监听各种状态
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _player.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
          _initialized = true;
        });
      }
    });
    _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });
    _player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        setState(() => _error = error);
      }
    });

    // 打开文件
    _player.open(Media(widget.filePath)).catchError((e) {
      if (mounted) {
        setState(() => _error = '视频加载失败: $e');
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showControls
          ? AppBar(
              title: Text(widget.title, style: const TextStyle(fontSize: 15)),
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  tooltip: '使用系统播放器打开',
                  onPressed: () {
                    FileOpenerService.openExternalFile(context, widget.filePath);
                  },
                ),
              ],
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('使用系统播放器打开'),
                onPressed: () {
                  FileOpenerService.openExternalFile(context, widget.filePath);
                },
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 视频画面
          Center(
            child: Video(
              controller: _videoController,
              controls: NoVideoControls,
            ),
          ),

          // 缓冲指示器
          if (_isBuffering)
            const CircularProgressIndicator(color: Colors.white),

          // 中央播放/暂停按钮
          if (_showControls && !_isBuffering)
            GestureDetector(
              onTap: () => _player.playOrPause(),
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),

          // 底部控制栏
          if (_showControls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildControlBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Colors.grey[700],
              thumbColor: Colors.white,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (v) {
                _player.seek(Duration(
                  milliseconds: (v * _duration.inMilliseconds).round(),
                ));
              },
            ),
          ),

          // 时间 + 按钮
          Row(
            children: [
              Text(
                '${_fmt(_position)} / ${_fmt(_duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),

              // 快退 10s
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  final target = _position - const Duration(seconds: 10);
                  _player.seek(target < Duration.zero ? Duration.zero : target);
                },
              ),

              // 播放/暂停
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 30,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => _player.playOrPause(),
              ),

              // 快进 10s
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  final target = _position + const Duration(seconds: 10);
                  _player.seek(target > _duration ? _duration : target);
                },
              ),

              const Spacer(),

              // 倍速选择
              PopupMenuButton<double>(
                icon: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                onSelected: (speed) {
                  setState(() => _playbackSpeed = speed);
                  _player.setRate(speed);
                },
                itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                    .map((s) => PopupMenuItem(
                          value: s,
                          child: Text(
                            '${s}x',
                            style: TextStyle(
                              fontWeight: s == _playbackSpeed
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
