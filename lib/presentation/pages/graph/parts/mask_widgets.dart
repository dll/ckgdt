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
// _MaskGridPanel — 弹窗内的蒙版网格面板
// ══════════════════════════════════════════════════════════════════════════════

class _MaskGridPanel extends StatelessWidget {
  final List<MaskShape> allShapes;
  final MaskShape selectedShape;
  final ValueChanged<MaskShape> onSelected;

  const _MaskGridPanel({
    required this.allShapes,
    required this.selectedShape,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // 按类别分组
    final groups = <String, List<MaskShape>>{
      '移动平台': [
        MaskShape.android, MaskShape.apple, MaskShape.harmonyOS,
      ],
      '跨平台框架': [
        MaskShape.flutter, MaskShape.reactNative, MaskShape.uniapp,
        MaskShape.maui, MaskShape.cordova,
      ],
      '编程语言': [
        MaskShape.dart, MaskShape.kotlin, MaskShape.swift,
        MaskShape.java, MaskShape.python, MaskShape.typeScript,
        MaskShape.golang,
      ],
      '工具与平台': [
        MaskShape.wechat, MaskShape.docker, MaskShape.gitHub,
        MaskShape.vsCode, MaskShape.linux,
      ],
      '个性化': [
        MaskShape.avatar, MaskShape.brain,
      ],
    };

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.84,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
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
                  '共 ${allShapes.length} 个',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 按分类显示
            ...groups.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 分类标签
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
                  // 网格
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: entry.value.map((shape) {
                      final isSelected = shape == selectedShape;
                      return GestureDetector(
                        onTap: () => onSelected(shape),
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
          ],
        ),
      ),
    );
  }
}
