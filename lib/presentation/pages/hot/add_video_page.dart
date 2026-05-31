import 'package:flutter/material.dart';
import '../../../data/local/hot_video_dao.dart';
import '../../../data/models/hot_video_model.dart';

class AddVideoPage extends StatefulWidget {
  final String userId;
  final HotVideoModel? editingVideo;

  const AddVideoPage({super.key, required this.userId, this.editingVideo});

  @override
  State<AddVideoPage> createState() => _AddVideoPageState();
}

class _AddVideoPageState extends State<AddVideoPage> {
  final _formKey = GlobalKey<FormState>();
  final _dao = HotVideoDao();

  late String _platform;
  late final TextEditingController _urlController;
  late final TextEditingController _titleController;
  late final TextEditingController _thumbnailController;
  late final TextEditingController _sourceController;
  late final TextEditingController _durationController;
  late final TextEditingController _viewCountController;
  late final TextEditingController _publishDateController;
  late final TextEditingController _descController;

  bool _saving = false;

  bool get _isEditing => widget.editingVideo != null;

  static const _platforms = [
    {'key': 'bilibili', 'label': 'B站 (Bilibili)', 'icon': Icons.play_circle},
    {'key': 'youtube', 'label': 'YouTube', 'icon': Icons.ondemand_video},
    {'key': 'douyin', 'label': '抖音 (Douyin)', 'icon': Icons.music_note},
    {'key': 'twitter', 'label': '推特 (Twitter/X)', 'icon': Icons.chat_bubble},
    {'key': 'other', 'label': '其他平台', 'icon': Icons.video_library},
  ];

  @override
  void initState() {
    super.initState();
    final video = widget.editingVideo;
    _platform = video?.platform ?? 'bilibili';
    _urlController = TextEditingController(text: video?.videoUrl ?? '');
    _titleController = TextEditingController(text: video?.title ?? '');
    _thumbnailController = TextEditingController(text: video?.thumbnailUrl ?? '');
    _sourceController = TextEditingController(text: video?.source ?? '');
    _durationController = TextEditingController(text: video?.duration ?? '');
    _viewCountController = TextEditingController(text: video?.viewCount ?? '');
    _publishDateController = TextEditingController(text: video?.publishDate ?? '');
    _descController = TextEditingController(text: video?.description ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _thumbnailController.dispose();
    _sourceController.dispose();
    _durationController.dispose();
    _viewCountController.dispose();
    _publishDateController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await _dao.updateVideo(
          id: widget.editingVideo!.id!,
          userId: widget.userId,
          platform: _platform,
          videoUrl: _urlController.text.trim(),
          title: _titleController.text.trim(),
          thumbnailUrl: _thumbnailController.text.trim().isEmpty
              ? null
              : _thumbnailController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          viewCount: _viewCountController.text.trim().isEmpty
              ? null
              : _viewCountController.text.trim(),
          duration: _durationController.text.trim().isEmpty
              ? null
              : _durationController.text.trim(),
          source: _sourceController.text.trim().isEmpty
              ? null
              : _sourceController.text.trim(),
          publishDate: _publishDateController.text.trim().isEmpty
              ? null
              : _publishDateController.text.trim(),
        );
      } else {
        await _dao.addVideo(
          userId: widget.userId,
          platform: _platform,
          videoUrl: _urlController.text.trim(),
          title: _titleController.text.trim(),
          thumbnailUrl: _thumbnailController.text.trim().isEmpty
              ? null
              : _thumbnailController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          viewCount: _viewCountController.text.trim().isEmpty
              ? null
              : _viewCountController.text.trim(),
          duration: _durationController.text.trim().isEmpty
              ? null
              : _durationController.text.trim(),
          source: _sourceController.text.trim().isEmpty
              ? null
              : _sourceController.text.trim(),
          publishDate: _publishDateController.text.trim().isEmpty
              ? null
              : _publishDateController.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请重试'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑视频' : '添加推荐视频'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('选择平台', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: _platform,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language),
              ),
              items: _platforms.map((p) => DropdownMenuItem(
                value: p['key'] as String,
                child: Text(p['label'] as String),
              )).toList(),
              onChanged: (v) => setState(() => _platform = v!),
            ),
            const SizedBox(height: 16),

            _buildField(
              controller: _urlController,
              label: '视频链接',
              hint: 'https://...',
              icon: Icons.link,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '请输入视频链接';
                if (!v.trim().startsWith('http')) return '请输入有效的URL';
                return null;
              },
            ),
            _buildField(
              controller: _titleController,
              label: '视频标题',
              hint: '输入视频标题',
              icon: Icons.title,
              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入视频标题' : null,
            ),
            _buildField(
              controller: _sourceController,
              label: '来源 / UP主',
              hint: '如: 李永乐老师',
              icon: Icons.person,
            ),
            _buildField(
              controller: _thumbnailController,
              label: '缩略图链接（可选）',
              hint: 'https://...',
              icon: Icons.image,
            ),

            Row(children: [
              Expanded(
                child: _buildField(
                  controller: _durationController,
                  label: '时长（可选）',
                  hint: '如: 15:32',
                  icon: Icons.timer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(
                  controller: _viewCountController,
                  label: '播放量（可选）',
                  hint: '如: 1.2万',
                  icon: Icons.visibility,
                ),
              ),
            ]),

            _buildField(
              controller: _publishDateController,
              label: '发布日期（可选）',
              hint: '如: 2026-05-15',
              icon: Icons.calendar_today,
            ),
            _buildField(
              controller: _descController,
              label: '描述（可选）',
              hint: '简单描述视频内容...',
              icon: Icons.description,
              maxLines: 3,
            ),

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_isEditing ? Icons.save : Icons.add),
              label: Text(_isEditing ? '保存修改' : '添加视频'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 20),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }
}
