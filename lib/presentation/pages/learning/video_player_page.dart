import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../services/file_opener_service.dart';

/// 应用内视频播放器
/// 使用 video_player 包实现，支持播放/暂停、进度拖动、倍速播放
/// AppBar 提供"使用系统播放器打开"按钮作为备选
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
  late VideoPlayerController _controller;
  bool _initialized = false;
  String? _error;
  bool _showControls = true;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
        }
      }).catchError((e) {
        if (mounted) {
          setState(() => _error = '视频加载失败: $e');
        }
      });
    _controller.addListener(_onPlayerUpdate);
  }

  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onPlayerUpdate);
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
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
      ),
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

    if (!_initialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('加载视频...', style: TextStyle(color: Colors.white70)),
          ],
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
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),

          // 播放/暂停叠加层（点击中央）
          if (_showControls)
            GestureDetector(
              onTap: () {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              },
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
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
    final pos = _controller.value.position;
    final dur = _controller.value.duration;
    final progress = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
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
                _controller.seekTo(Duration(
                  milliseconds: (v * dur.inMilliseconds).round(),
                ));
              },
            ),
          ),

          // 时间 + 按钮
          Row(
            children: [
              // 时间显示
              Text(
                '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),

              const Spacer(),

              // 快退 10s
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  _controller.seekTo(pos - const Duration(seconds: 10));
                },
              ),

              // 播放/暂停
              IconButton(
                icon: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 30,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                },
              ),

              // 快进 10s
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  _controller.seekTo(pos + const Duration(seconds: 10));
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
                  _controller.setPlaybackSpeed(speed);
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
