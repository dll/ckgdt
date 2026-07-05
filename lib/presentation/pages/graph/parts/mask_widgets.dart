part of '../knowledge_graph_page.dart';

class _MaskDropdownButton extends StatelessWidget {
  final MaskShape selectedShape;
  final List<MaskShape> allShapes;
  final ValueChanged<MaskShape> onSelected;

  const _MaskDropdownButton({
    required this.selectedShape,
    required this.allShapes,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showMaskGrid(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.deepPurple,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withOpacity(0.30),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TechLogoWidget(
              shape: selectedShape,
              size: 20,
              selected: true,
            ),
            const SizedBox(width: 6),
            Text(
              selectedShape.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  void _showMaskGrid(BuildContext context) {
    showDialog<MaskShape>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(ctx).padding.top + 120,
              left: 16,
              right: 16,
            ),
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(ctx).size.width * 0.92,
                  maxHeight: 460,
                ),
                child: _MaskGridPanel(
                  allShapes: allShapes,
                  selectedShape: selectedShape,
                  onSelected: (shape) {
                    Navigator.of(ctx).pop(shape);
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).then((selected) {
      if (selected != null) {
        onSelected(selected);
      }
    });
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _MaskGridPanel — 弹窗内的蒙版网格面板（课程感知分类）
// ══════════════════════════════════════════════════════════════════════════════

class _MaskGridPanel extends StatefulWidget {
  final List<MaskShape> allShapes;
  final MaskShape selectedShape;
  final ValueChanged<MaskShape> onSelected;

  const _MaskGridPanel({
    required this.allShapes,
    required this.selectedShape,
    required this.onSelected,
  });

  @override
  State<_MaskGridPanel> createState() => _MaskGridPanelState();
}

class _MaskGridPanelState extends State<_MaskGridPanel> {
  List<ChapterDef> _chapterDefs = [];
  bool _loading = true;

  /// 从章节定义中提取课程相关的蒙版形状（仅显示课程匹配的类型）
  Map<String, List<MaskShape>> _buildGroups() {
    if (_chapterDefs.isEmpty) {
      return {'课程蒙版': [MaskShape.book, MaskShape.lightbulb, MaskShape.compass, MaskShape.brain]};
    }
    final groups = <String, List<MaskShape>>{};
    final chunkSize = _chapterDefs.length <= 4 ? 1 : (_chapterDefs.length <= 8 ? 2 : 3);
    for (var i = 0; i < _chapterDefs.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, _chapterDefs.length);
      final chapterRange = _chapterDefs.sublist(i, end);
      final label = _shortLabel(chapterRange.first.title);
      final icons = <MaskShape>[];
      for (final ch in chapterRange) {
        icons.add(_iconFromChapterDef(ch));
      }
      groups[label] = icons;
    }
    return groups;
  }

  /// 从章节定义的 icon 字段映射到 MaskShape
  MaskShape _iconFromChapterDef(ChapterDef ch) {
    // chapters.json icon: "account_tree", "storage", "laptop", etc.
    // 映射到 MaskShape 枚举
    final iconName = ch.icon.toLowerCase();
    for (final shape in MaskShape.values) {
      if (shape.name.toLowerCase() == iconName) return shape;
    }
    // 回退：按章节序号从池中取
    final pool = [MaskShape.book, MaskShape.lightbulb, MaskShape.compass,
      MaskShape.microscope, MaskShape.globe, MaskShape.pencil,
      MaskShape.monitor, MaskShape.chart, MaskShape.puzzle,
      MaskShape.graduationCap, MaskShape.brain, MaskShape.avatar];
    return pool[ch.number % pool.length];
  }

  /// 章节名缩短为标签
  String _shortLabel(String title) {
    // "第1章 课程知识图谱基础" → "知识图谱基础"
    var s = title.replaceFirst(RegExp(r'第\d+章\s*'), '').trim();
    if (s.length > 8) s = s.substring(0, 8);
    return s;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final ctx = CourseContextService();
    final id = await ctx.activeCourseId();
    // 从 CourseDataService 加载章节定义（含颜色/图标）
    final pkg = await CourseDataService.instance.getPackage(id);
    if (mounted) {
      setState(() {
        _chapterDefs = pkg.chapters;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 200, height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final groups = _buildGroups();

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.84,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: Colors.deepPurple),
                const SizedBox(width: 6),
                const Text(
                  '选择蒙版形状',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const Spacer(),
                Text(
                  '共 ${widget.allShapes.length} 个',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...groups.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, top: 4),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: entry.value.map((shape) {
                      final isSelected = shape == widget.selectedShape;
                      return GestureDetector(
                        onTap: () => widget.onSelected(shape),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 76,
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.deepPurple
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.deepPurple
                                  : Colors.grey.shade200,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.deepPurple
                                          .withOpacity(0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TechLogoWidget(
                                shape: shape,
                                size: 28,
                                selected: isSelected,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                shape.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                ],
              );
            }),
            // ── 创建蒙版按钮 ──────────────────────────────────
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('自定义蒙版功能即将上线，敬请期待')),
                );
              },
              child: Container(
                width: 76,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400, width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline, size: 28, color: Colors.grey.shade500),
                    const SizedBox(height: 4),
                    Text(
                      '创建蒙版',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
