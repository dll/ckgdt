import 'package:flutter/material.dart';
import '../../../data/local/course_dao.dart';
import '../../../data/models/course_model.dart';
import '../../../services/knowledge_seed_service.dart';
import '../../widgets/course_generator_sheet.dart';

import '../../widgets/back_button_bar.dart';

/// 课程管理页面 — 查看、切换、删除课程
class CourseManagePage extends StatefulWidget {
  const CourseManagePage({super.key});

  @override
  State<CourseManagePage> createState() => _CourseManagePageState();
}

class _CourseManagePageState extends State<CourseManagePage> {
  final CourseDao _courseDao = CourseDao();
  List<CourseModel> _courses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _loading = true);
    try {
      final courses = await _courseDao.getAllCourses();
      setState(() {
        _courses = courses;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载课程失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: BackButtonBar(
        title: '课程管理',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '一键生课',
            onPressed: _showGenerator,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _courses.isEmpty
              ? _buildEmpty(theme)
              : _buildCourseList(theme),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('暂无课程', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '点击右上角 + 按钮一键生成课程',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('一键生课'),
            onPressed: _showGenerator,
          ),
        ],
      ),
    );
  }

  Widget _buildCourseList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _courses.length,
      itemBuilder: (context, index) {
        final course = _courses[index];
        return _buildCourseCard(theme, course);
      },
    );
  }

  Widget _buildCourseCard(ThemeData theme, CourseModel course) {
    final isActive = course.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isActive
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showCourseDetail(course),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Icon(
                    Icons.school,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      course.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isActive ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '当前课程',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (action) => _handleAction(action, course),
                    itemBuilder: (_) => [
                      if (!isActive)
                        const PopupMenuItem(
                          value: 'activate',
                          child: ListTile(
                            leading: Icon(Icons.check_circle_outline),
                            title: Text('切换到此课程'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (!isActive)
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading:
                                Icon(Icons.delete_outline, color: Colors.red),
                            title:
                                Text('删除', style: TextStyle(color: Colors.red)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // 描述
              if (course.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  course.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // 章节信息
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildInfoChip(
                    theme,
                    Icons.format_list_numbered,
                    '${course.chapterCount} 章',
                  ),
                  _buildInfoChip(
                    theme,
                    Icons.calendar_today,
                    course.createdAt.length >= 10
                        ? course.createdAt.substring(0, 10)
                        : course.createdAt,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _showCourseDetail(CourseModel course) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              controller: scrollController,
              children: [
                // 标题
                Text(
                  course.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (course.description.isNotEmpty)
                  Text(
                    course.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                const SizedBox(height: 20),

                // 章节列表
                Text(
                  '章节目录（${course.chapterCount} 章）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...course.chapters.asMap().entries.map((entry) {
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        '${entry.key + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(entry.value, style: theme.textTheme.bodyMedium),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  );
                }),

                const SizedBox(height: 20),

                // 操作按钮
                if (!course.isActive)
                  FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('切换到此课程'),
                    onPressed: () {
                      Navigator.pop(context);
                      _handleAction('activate', course);
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleAction(String action, CourseModel course) async {
    switch (action) {
      case 'activate':
        await _courseDao.setActiveCourse(course.id);
        await KnowledgeSeedService().seedIfEmpty();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已切换到《${course.name}》'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadCourses();
        break;

      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确定要删除课程《${course.name}》吗？此操作不可恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          final ok = await _courseDao.deleteCourse(course.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok ? '已删除《${course.name}》' : '无法删除当前激活的课程'),
                backgroundColor: ok ? Colors.green : Colors.orange,
              ),
            );
          }
          if (ok) _loadCourses();
        }
        break;
    }
  }

  Future<void> _showGenerator() async {
    final result = await showModalBottomSheet<CourseModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CourseGeneratorSheet(),
    );
    if (result != null) {
      _loadCourses();
    }
  }
}
