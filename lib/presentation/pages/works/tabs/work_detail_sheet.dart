part of '../works_page.dart';

class _WorkDetailSheet extends StatefulWidget {
  final Map<String, dynamic> work;
  final Map<String, dynamic>? studentInfo;
  final AuthService authService;
  final WorksDao worksDao;
  final VoidCallback? onChanged;

  const _WorkDetailSheet({
    required this.work,
    this.studentInfo,
    required this.authService,
    required this.worksDao,
    this.onChanged,
  });

  @override
  State<_WorkDetailSheet> createState() => _WorkDetailSheetState();
}

class _WorkDetailSheetState extends State<_WorkDetailSheet> {
  late Map<String, dynamic> _work;
  List<Map<String, dynamic>> _comments = [];
  bool _isLiked = false;
  final _commentCtrl = TextEditingController();
  bool _loadingComments = true;
  bool _isUploading = false;

  bool get _isOwnerOrTeacher {
    final auth = widget.authService;
    if (auth.isTeacher || auth.isAdmin) return true;
    final userId = auth.getCurrentUserId();
    return userId != null && _work['user_id'] == userId;
  }

  @override
  void initState() {
    super.initState();
    _work = Map.from(widget.work);
    _loadInteractionData();
  }

  Future<void> _loadInteractionData() async {
    final userId = widget.authService.getCurrentUserId() ?? '';
    final workId = _work['id'] as int;
    try {
      final liked = await widget.worksDao.isLiked(workId, userId);
      final comments = await widget.worksDao.getComments(workId);
      final refreshed = await widget.worksDao.getWork(workId);
      if (mounted) {
        setState(() {
          _isLiked = liked;
          _comments = comments;
          if (refreshed != null) _work = refreshed;
          _loadingComments = false;
        });
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'WorkDetailSheet.loadInteractionData', stack: st);
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  /// 上传演示视频（MP4）
  Future<void> _uploadVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'avi', 'mkv'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final filePath = file.path;
      if (filePath == null) return;

      final fileSize = file.size;
      // 限制 100MB
      if (fileSize > 100 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('视频文件不能超过 100MB'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      final workId = _work['id'] as int;
      final userId = _work['user_id'] as String? ?? '';
      final fileName = file.name;

      // 复制到应用文档目录（持久化）
      String savedPath = filePath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final videoDir = Directory('${appDir.path}/works_videos/$userId');
        if (!videoDir.existsSync()) videoDir.createSync(recursive: true);
        final destFile = File('${videoDir.path}/$fileName');
        if (destFile.path != filePath) {
          await File(filePath).copy(destFile.path);
          savedPath = destFile.path;
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'WorkDetailSheet.saveVideoLocal', stack: st);
      }

      // 同步上传到 Gitee 仓库（通过 SyncService 的文件上传）
      try {
        final gitee = GiteeService();
        final remotePath = '作品/$userId/$fileName';
        // Gitee 文件限制 1MB base64，大文件只存本地路径
        if (fileSize <= 1 * 1024 * 1024) {
          final bytes = await File(savedPath).readAsBytes();
          await gitee.createFile(
            owner: 'osgisOne',
            repo: 'mad-data',
            path: remotePath,
            content: base64Encode(bytes),
            message: '上传作品视频: $fileName',
            branch: 'master',
          );
        }
      } catch (e) {
        debugPrint('视频上传到 Gitee 失败（文件可能过大）: $e');
      }

      // 更新数据库
      final db = await widget.worksDao.getDatabase();
      await db.update(
        'student_works',
        {
          'video_url': savedPath,
          'file_path': savedPath,
          'file_size': '${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB',
        },
        where: 'id = ?',
        whereArgs: [workId],
      );

      final wasUnsubmitted = (_work['status'] as String? ?? '待提交') == '待提交';
      final isStudent =
          !widget.authService.isTeacher && !widget.authService.isAdmin;
      var successMessage = '视频上传成功';

      // 学生首次提交：AI 初评达到评价分数线后才切换为已提交并通知教师。
      if (wasUnsubmitted && isStudent) {
        final refreshedDraft = await widget.worksDao.getWork(workId);
        if (refreshedDraft != null && mounted) {
          final title = (refreshedDraft['title'] as String?) ??
              (refreshedDraft['project'] as String?) ??
              '作品';
          final description = (refreshedDraft['description'] as String?) ?? '';
          final techStack = refreshedDraft['tech_stack'] as String?;
          final groupName = refreshedDraft['group_name'] as String?;
          final studentName = (refreshedDraft['student_name'] as String?) ??
              widget.authService.currentUser?.realName ??
              userId;
          final passScore = await SettingsService.getEvaluationPassScore();
          final draft = await AutoGradingService.instance.gradeWork(
            workId: workId,
            studentId: userId,
            studentName: studentName,
            workTitle: title,
            description: description,
            techStack: techStack,
            groupName: groupName,
            returnDraft: true,
            notifyStudent: false,
          );
          if (draft == null || !draft.isUsable || draft.score < passScore) {
            await GradingResultDao().deletePendingForTarget('works', workId);
            final refreshed = await widget.worksDao.getWork(workId);
            if (mounted) {
              setState(() {
                if (refreshed != null) _work = refreshed;
                _isUploading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(draft == null
                      ? '提交失败：AI 审核未完成，请稍后重试'
                      : '提交失败：AI 初评 ${draft.score} 分，未达到 $passScore 分达标线，请修改后重新提交'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                ),
              );
              widget.onChanged?.call();
            }
            return;
          }
          await widget.worksDao.submitWork(workId);
          successMessage = '作品提交成功！AI 初评 ${draft.score} 分，等待教师复核。';
        }
      } else if (wasUnsubmitted) {
        await widget.worksDao.submitWork(workId);
      }

      // 刷新
      final refreshed = await widget.worksDao.getWork(workId);
      if (mounted) {
        setState(() {
          if (refreshed != null) _work = refreshed;
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
          ),
        );
        widget.onChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleLike() async {
    final userId = widget.authService.getCurrentUserId() ?? '';
    final workId = _work['id'] as int;
    try {
      final liked = await widget.worksDao.toggleLike(workId, userId);
      final refreshed = await widget.worksDao.getWork(workId);
      if (mounted) {
        setState(() {
          _isLiked = liked;
          if (refreshed != null) _work = refreshed;
        });
      }
      widget.onChanged?.call();
    } catch (e, st) {
      swallowDebug(e, tag: 'WorkDetailSheet.toggleLike', stack: st);
    }
  }

  Future<void> _submitComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;
    final user = widget.authService.currentUser;
    final userId = user?.userId ?? '';
    final role = user?.role ?? 'student';
    final name = user?.realName ?? userId;
    try {
      await widget.worksDao.addComment(
        workId: _work['id'] as int,
        userId: userId,
        userName: name,
        userRole: role,
        content: content,
      );
      _commentCtrl.clear();
      await _loadInteractionData();
      widget.onChanged?.call();
    } catch (e, st) {
      swallowDebug(e, tag: 'WorkDetailSheet.submitComment', stack: st);
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final score = _work['score'] as int?;
    final tags = _work['tags'] != null
        ? (jsonDecode(_work['tags'] as String) as List)
        : [];
    final isTeacherOrAdmin =
        widget.authService.isTeacher || widget.authService.isAdmin;
    final workStatus = _work['status'] as String? ?? '待提交';
    final isSubmitted = workStatus == '已提交';
    final canInteract = isTeacherOrAdmin || isSubmitted;
    final viewCount = (_work['view_count'] as int?) ?? 0;
    final likeCount = (_work['like_count'] as int?) ?? 0;
    final commentCount = (_work['comment_count'] as int?) ?? 0;
    final si = widget.studentInfo; // 可能为 null

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(20),
        children: [
          // 拖拽手柄
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 视频区 ──────────────────────────────────────
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.12),
                  primary.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.videocam,
                    size: 64, color: primary.withValues(alpha: 0.2)),
                // 播放按钮
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 32),
                    onPressed: () {
                      final videoUrl = _work['video_url'] as String? ?? '';
                      if (videoUrl.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('该作品尚未上传演示视频'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      // 如果是本地文件路径，直接打开
                      if (File(videoUrl).existsSync()) {
                        FileOpenerService.openFile(
                          context,
                          videoUrl,
                          '${_work['title'] ?? '作品'}-演示视频',
                        );
                      } else {
                        // Gitee URL 或远程路径
                        FileOpenerService.openFile(
                          context,
                          videoUrl,
                          '${_work['title'] ?? '作品'}-演示视频',
                        );
                      }
                    },
                  ),
                ),
                // 上传按钮（仅作品所有者或教师可见）
                if (_isOwnerOrTeacher)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _isUploading ? null : _uploadVideo,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isUploading)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              else
                                const Icon(Icons.upload,
                                    size: 16, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                _isUploading ? '上传中...' : '上传视频',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_work['video_duration'] != null)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_work['video_duration'] as String,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 学生信息 + 交互按钮 ─────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头像
              CircleAvatar(
                radius: 22,
                backgroundColor: primary.withValues(alpha: 0.15),
                child: Text(
                  _avatarChar(_work, isTeacherOrAdmin),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _studentDisplayName(_work, isTeacherOrAdmin),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (_work['student_role'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _work['student_role'] as String,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.orange[700]),
                            ),
                          ),
                        if (_work['repo'] != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _work['repo'] as String,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.blue[700]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 交互按钮行
          Row(
            children: [
              _statChip(
                  Icons.visibility, '$viewCount', '播放', Colors.grey[600]!),
              const SizedBox(width: 8),
              InkWell(
                onTap: canInteract ? _toggleLike : null,
                borderRadius: BorderRadius.circular(8),
                child: _statChip(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  '$likeCount',
                  '点赞',
                  _isLiked ? Colors.red : Colors.grey[600]!,
                ),
              ),
              const SizedBox(width: 8),
              _statChip(Icons.comment, '$commentCount', '评论', Colors.blue),
              const Spacer(),
              if (isTeacherOrAdmin)
                ElevatedButton.icon(
                  onPressed: () => _showScoreDialog(context),
                  icon: const Icon(Icons.rate_review, size: 16),
                  label: Text(score != null ? '重新评分' : '评分'),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              if (!isTeacherOrAdmin &&
                  (isSubmitted || workStatus == '已评分') &&
                  _work['user_id'] != widget.authService.getCurrentUserId())
                ElevatedButton.icon(
                  onPressed: () => _showScoreDialog(context, isPeer: true),
                  icon: const Icon(Icons.people, size: 16),
                  label: const Text('同学互评'),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          const Divider(height: 28),

          // ── 项目信息 ────────────────────────────────────
          _sectionHeader('项目信息', icon: Icons.info_outline),
          _infoRow(Icons.science, '项目', _work['title'] as String? ?? '未命名'),
          _infoRow(Icons.code, '技术栈', _work['tech_stack'] as String? ?? '未指定'),
          if (_work['class_group'] != null)
            _infoRow(Icons.class_, '班组', _work['class_group'] as String),

          // 来自 JSON 的丰富信息
          if (si != null) ...[
            if (si['coreDuty'] != null && (si['coreDuty'] as String).isNotEmpty)
              _infoRow(Icons.work, '核心职责', si['coreDuty'] as String),
            if (si['features'] != null && (si['features'] as String).isNotEmpty)
              _infoRow(Icons.auto_awesome, '特色功能', si['features'] as String),
            if (si['remark'] != null && (si['remark'] as String).isNotEmpty)
              _infoRow(Icons.note, '备注', si['remark'] as String),
          ],

          // 功能详情（长文本）
          if (_work['description'] != null &&
              (_work['description'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            _sectionHeader('功能详情', icon: Icons.description),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Text(_work['description'] as String,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[700], height: 1.6)),
            ),
          ],

          // 标签
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(t.toString(),
                            style: TextStyle(fontSize: 11, color: primary)),
                      ))
                  .toList(),
            ),
          ],

          // ── 评分详情 ────────────────────────────────────
          if (score != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _sectionHeader('教师评分', icon: Icons.star)),
                // 仅教师/管理员能查审计 — 学生无操作权限不暴露入口
                if (widget.authService.isTeacher || widget.authService.isAdmin)
                  TextButton.icon(
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('修改历史', style: TextStyle(fontSize: 12)),
                    onPressed: () => ScoreHistoryDialog.show(
                      context,
                      tableName: 'work_scores',
                      rowId: _work['id'] as int,
                      title: '作品评分修改历史',
                    ),
                  ),
              ],
            ),
            _buildScoreDetail(),
          ],

          // ── 同学互评 ────────────────────────────────────
          if ((_work['peer_avg'] as num?) != null &&
              (_work['peer_count'] as int?) != null &&
              (_work['peer_count'] as int) > 0) ...[
            const SizedBox(height: 16),
            _sectionHeader('同学互评 (${_work['peer_count']}人)',
                icon: Icons.people),
            _buildPeerScoreDetail(),
          ],

          // ── 评论区 ──────────────────────────────────────
          const SizedBox(height: 16),
          _sectionHeader('评论区 ($commentCount)', icon: Icons.forum),
          // 发表评论（仅已提交的作品允许评论）
          if (canInteract)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    decoration: InputDecoration(
                      hintText: '发表评论...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _submitComment,
                  icon: Icon(Icons.send, color: primary),
                  style: IconButton.styleFrom(
                    backgroundColor: primary.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (_loadingComments)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else if (_comments.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Text('暂无评论，快来抢沙发吧~',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            )
          else
            ..._comments.map((c) => _buildCommentItem(c)),
        ],
      ),
    );
  }

  Widget _buildScoreDetail() {
    final score = _work['score'] as int? ?? 0;
    final scoreColor = score >= 90
        ? Colors.green
        : score >= 80
            ? Colors.blue
            : Colors.orange;
    final dims = [
      {'name': '功能完整性', 'key': 'score_functionality', 'max': 25},
      {'name': '技术深度', 'key': 'score_tech_depth', 'max': 20},
      {'name': '跨框架整合', 'key': 'score_integration', 'max': 25},
      {'name': '性能质量', 'key': 'score_quality', 'max': 15},
      {'name': '文档协作', 'key': 'score_documentation', 'max': 15},
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scoreColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: scoreColor, width: 3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('$score',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: scoreColor)),
              Text(' / 100',
                  style: TextStyle(fontSize: 16, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 10),
          ...dims.map((d) {
            final val = (_work[d['key'] as String] as int?) ?? 0;
            final maxVal = d['max'] as int;
            final ratio = val / maxVal;
            final barColor = ratio >= 0.9
                ? Colors.green
                : ratio >= 0.7
                    ? Colors.blue
                    : Colors.orange;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(d['name'] as String,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation(barColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$val/$maxVal',
                      style: TextStyle(
                          fontSize: 11,
                          color: barColor,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
          if (_work['score_comment'] != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('教师评语',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(_work['score_comment'] as String,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeerScoreDetail() {
    final peerAvg = (_work['peer_avg'] as num?)?.toDouble() ?? 0;
    final peerCount = (_work['peer_count'] as int?) ?? 0;
    final scoreColor = peerAvg >= 90
        ? Colors.green
        : peerAvg >= 80
            ? Colors.blue
            : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Colors.orange, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.people, color: Colors.orange[700], size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${peerAvg.toStringAsFixed(1)}',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: scoreColor)),
                  Text(' / 100',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                ],
              ),
              Text('$peerCount 位同学参与互评',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final role = comment['user_role'] as String? ?? 'student';
    final isTeacher = role == 'teacher' || role == 'admin';
    final roleColor = isTeacher ? Colors.blue : Colors.green;
    final roleLabel = isTeacher ? '教师' : '同学';
    final viewerIsAdmin =
        widget.authService.isTeacher || widget.authService.isAdmin;
    final commentName = viewerIsAdmin
        ? (comment['user_name'] as String? ?? '未知')
        : (isTeacher ? (comment['user_name'] as String? ?? '教师') : '匿名同学');
    final commentAvatar =
        commentName.isNotEmpty ? commentName.characters.first : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isTeacher ? Colors.blue.withValues(alpha: 0.03) : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: roleColor.withValues(alpha: 0.4), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Text(
                  commentAvatar,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: roleColor),
                ),
              ),
              const SizedBox(width: 8),
              Text(commentName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(roleLabel,
                    style: TextStyle(
                        fontSize: 9,
                        color: roleColor,
                        fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text(_timeAgo(comment['created_at'] as String?),
                  style: TextStyle(fontSize: 10, color: Colors.grey[400])),
            ],
          ),
          const SizedBox(height: 8),
          Text(comment['content'] as String? ?? '',
              style: TextStyle(
                  fontSize: 13, color: Colors.grey[800], height: 1.4)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey[500]),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── 评分对话框 ──────────────────────────────────────────

  void _showScoreDialog(BuildContext context, {bool isPeer = false}) {
    double functionality =
        (_work['score_functionality'] as int?)?.toDouble() ?? 15;
    double techDepth = (_work['score_tech_depth'] as int?)?.toDouble() ?? 12;
    double integration = (_work['score_integration'] as int?)?.toDouble() ?? 15;
    double quality = (_work['score_quality'] as int?)?.toDouble() ?? 9;
    double documentation =
        (_work['score_documentation'] as int?)?.toDouble() ?? 9;
    final commentCtrl =
        TextEditingController(text: _work['score_comment'] as String? ?? '');
    bool isAiGrading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final total = functionality.round() +
              techDepth.round() +
              integration.round() +
              quality.round() +
              documentation.round();
          final totalColor = total >= 90
              ? Colors.green
              : total >= 80
                  ? Colors.blue
                  : total >= 60
                      ? Colors.orange
                      : Colors.red;
          return AlertDialog(
            title: Text(
                '${isPeer ? "同学互评" : "评分"}: ${_studentDisplayName(_work, widget.authService.isTeacher || widget.authService.isAdmin)}',
                style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _scoreSlider('功能完整性', functionality, 25,
                        (v) => setDialogState(() => functionality = v)),
                    _scoreSlider('技术实现深度', techDepth, 20,
                        (v) => setDialogState(() => techDepth = v)),
                    _scoreSlider('跨框架整合', integration, 25,
                        (v) => setDialogState(() => integration = v)),
                    _scoreSlider('性能与质量', quality, 15,
                        (v) => setDialogState(() => quality = v)),
                    _scoreSlider('文档与协作', documentation, 15,
                        (v) => setDialogState(() => documentation = v)),
                    const SizedBox(height: 8),
                    Text('总分: $total / 100',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: totalColor)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: commentCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isPeer ? '互评评语' : '教师评语',
                        hintText: '请输入评语...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // AI 批阅按钮（仅教师可用）
              if (!isPeer)
                OutlinedButton.icon(
                  onPressed: isAiGrading
                      ? null
                      : () async {
                          setDialogState(() => isAiGrading = true);
                          try {
                            final agent = GradingAgent();
                            final result = await agent.gradeWork(
                              title: _work['title'] as String? ?? '',
                              description: _work['description'] as String?,
                              techStack: _work['tech_stack'] as String?,
                              studentName: _work['student_name'] as String? ??
                                  _work['leader_name'] as String?,
                              groupName: _work['group_name'] as String?,
                            );
                            final parsed = _tryParseGradingJson(result);
                            if (parsed != null) {
                              final scores =
                                  parsed['scores'] as Map<String, dynamic>?;
                              setDialogState(() {
                                if (scores != null) {
                                  functionality = ((scores['functionality']
                                              as Map?)?['score'] as num?)
                                          ?.toDouble() ??
                                      functionality;
                                  techDepth = ((scores['tech_depth']
                                              as Map?)?['score'] as num?)
                                          ?.toDouble() ??
                                      techDepth;
                                  integration = ((scores['integration']
                                              as Map?)?['score'] as num?)
                                          ?.toDouble() ??
                                      integration;
                                  quality = ((scores['quality']
                                              as Map?)?['score'] as num?)
                                          ?.toDouble() ??
                                      quality;
                                  documentation = ((scores['documentation']
                                              as Map?)?['score'] as num?)
                                          ?.toDouble() ??
                                      documentation;
                                }
                                commentCtrl.text =
                                    parsed['feedback'] as String? ?? '';
                              });
                            } else {
                              setDialogState(() {
                                commentCtrl.text = result;
                              });
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('AI批阅失败: $e')),
                              );
                            }
                          } finally {
                            if (ctx.mounted) {
                              setDialogState(() => isAiGrading = false);
                            }
                          }
                        },
                  icon: isAiGrading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(isAiGrading ? 'AI批阅中...' : 'AI批阅'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final user = widget.authService.currentUser;
                    final workId = _work['id'] as int;
                    await widget.worksDao.scoreWork(
                      workId: workId,
                      scorerId: widget.authService.getCurrentUserId(),
                      scorerName: user?.realName ?? (isPeer ? '同学' : '教师'),
                      functionality: functionality.round(),
                      techDepth: techDepth.round(),
                      integration: integration.round(),
                      quality: quality.round(),
                      documentation: documentation.round(),
                      comment: commentCtrl.text.trim().isNotEmpty
                          ? commentCtrl.text.trim()
                          : null,
                    );
                    // 审计：评分录入操作（失败不阻塞）
                    try {
                      await ScoreAuditDao.instance.logChange(
                        tableName: 'work_scores',
                        rowId: workId,
                        field: 'total',
                        newValue: (functionality +
                                techDepth +
                                integration +
                                quality +
                                documentation)
                            .round()
                            .toString(),
                        scorerId: widget.authService.getCurrentUserId() ?? '',
                        scorerName: user?.realName,
                        op: 'create',
                      );
                    } catch (e) {
                      // 审计日志失败不阻塞评分主流程
                      swallow(e, tag: 'WorkDetailSheet.scoreAudit');
                    }
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isPeer ? '互评提交成功！' : '评分成功！'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      await _loadInteractionData();
                      widget.onChanged?.call();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('评分失败: $e')),
                      );
                    }
                  }
                },
                child: const Text('提交评分'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 尝试从 AI 批阅结果中解析 JSON
  Map<String, dynamic>? _tryParseGradingJson(String text) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch == null) return null;
      final jsonStr = jsonMatch.group(0)!;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map.containsKey('scores') ||
          map.containsKey('feedback') ||
          map.containsKey('total_score')) {
        return map;
      }
      return null;
    } catch (e) {
      // AI 输出非 JSON 属预期，解析失败回退 null
      swallow(e, tag: 'WorkDetailSheet.parseAiJson');
      return null;
    }
  }

  Widget _scoreSlider(
      String name, double value, int max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
              Text('${value.round()} / $max',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: max.toDouble(),
            divisions: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 1: 作品记录 (Records) — 多维度排序展示                                 ║
// ╚══════════════════════════════════════════════════════════════════════════════╝
