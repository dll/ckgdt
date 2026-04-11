import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../../../services/file_opener_service.dart';

/// 应用内 PPT/PPTX 查看器
/// 使用 archive 解压 PPTX（ZIP 格式），xml 解析幻灯片内容
/// 支持翻页浏览、缩放、全屏，AppBar 提供"使用系统工具打开"按钮
class InAppPptViewerPage extends StatefulWidget {
  final String filePath;
  final String title;

  const InAppPptViewerPage({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<InAppPptViewerPage> createState() => _InAppPptViewerPageState();
}

class _InAppPptViewerPageState extends State<InAppPptViewerPage> {
  List<_SlideData> _slides = [];
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _parsePptx();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _parsePptx() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _error = '文件不存在: ${widget.filePath}';
          _loading = false;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 收集所有 slide XML 文件
      final slideFiles = <int, ArchiveFile>{};
      for (final entry in archive) {
        final name = entry.name;
        // 匹配 ppt/slides/slide1.xml, ppt/slides/slide2.xml ...
        final match = RegExp(r'ppt/slides/slide(\d+)\.xml').firstMatch(name);
        if (match != null) {
          final slideNum = int.parse(match.group(1)!);
          slideFiles[slideNum] = entry;
        }
      }

      if (slideFiles.isEmpty) {
        setState(() {
          _error = '无法解析 PPTX 文件：未找到幻灯片内容';
          _loading = false;
        });
        return;
      }

      // 按编号排序
      final sortedKeys = slideFiles.keys.toList()..sort();
      final slides = <_SlideData>[];

      for (final key in sortedKeys) {
        final entry = slideFiles[key]!;
        final xmlContent = String.fromCharCodes(entry.content as List<int>);
        final slide = _parseSlideXml(xmlContent, key);
        slides.add(slide);
      }

      if (!mounted) return;
      setState(() {
        _slides = slides;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '解析 PPTX 失败: $e';
        _loading = false;
      });
    }
  }

  /// 解析单张幻灯片 XML，提取文本段落
  _SlideData _parseSlideXml(String xmlContent, int slideNumber) {
    try {
      final doc = XmlDocument.parse(xmlContent);
      final paragraphs = <_ParagraphData>[];
      String? title;

      // 查找所有 shape (sp) 元素
      final shapes = doc.findAllElements('p:sp').toList();

      for (final shape in shapes) {
        // 检查是否是标题形状
        final isTitle = _isShapeTitle(shape);

        // 提取文本框中的段落
        final txBody = shape.findAllElements('p:txBody');
        for (final body in txBody) {
          final pElements = body.findAllElements('a:p');
          for (final p in pElements) {
            final textParts = <String>[];
            bool isBold = false;
            double? fontSize;

            // 段落级属性
            final pPr = p.findAllElements('a:pPr').firstOrNull;
            int level = 0;
            if (pPr != null) {
              final lvl = pPr.getAttribute('lvl');
              if (lvl != null) level = int.tryParse(lvl) ?? 0;
            }

            // 收集文本运行
            final runs = p.findAllElements('a:r');
            for (final run in runs) {
              // 文本运行属性
              final rPr = run.findAllElements('a:rPr').firstOrNull;
              if (rPr != null) {
                final b = rPr.getAttribute('b');
                if (b == '1' || b == 'true') isBold = true;
                final sz = rPr.getAttribute('sz');
                if (sz != null) {
                  fontSize = (int.tryParse(sz) ?? 1800) / 100.0;
                }
              }

              final tElements = run.findAllElements('a:t');
              for (final t in tElements) {
                final text = t.innerText.trim();
                if (text.isNotEmpty) {
                  textParts.add(text);
                }
              }
            }

            // 也检查 <a:fld> 中的文本（日期、页码等字段）
            final fields = p.findAllElements('a:fld');
            for (final field in fields) {
              final tElements = field.findAllElements('a:t');
              for (final t in tElements) {
                final text = t.innerText.trim();
                if (text.isNotEmpty) {
                  textParts.add(text);
                }
              }
            }

            if (textParts.isNotEmpty) {
              final fullText = textParts.join('');
              if (isTitle && title == null) {
                title = fullText;
              }
              paragraphs.add(_ParagraphData(
                text: fullText,
                isTitle: isTitle && title == fullText,
                isBold: isBold,
                fontSize: fontSize,
                level: level,
              ));
            }
          }
        }
      }

      return _SlideData(
        slideNumber: slideNumber,
        title: title ?? '幻灯片 $slideNumber',
        paragraphs: paragraphs,
      );
    } catch (e) {
      return _SlideData(
        slideNumber: slideNumber,
        title: '幻灯片 $slideNumber',
        paragraphs: [_ParagraphData(text: '(内容解析失败)', isTitle: false)],
      );
    }
  }

  /// 判断形状是否为标题类型
  bool _isShapeTitle(XmlElement shape) {
    // 检查 nvSpPr → nvPr → ph 的 type 属性
    final nvSpPr = shape.findAllElements('p:nvSpPr');
    for (final nv in nvSpPr) {
      final nvPr = nv.findAllElements('p:nvPr');
      for (final pr in nvPr) {
        final ph = pr.findAllElements('p:ph');
        for (final placeholder in ph) {
          final type = placeholder.getAttribute('type');
          if (type == 'title' || type == 'ctrTitle') return true;
          // idx=0 通常也是标题
          final idx = placeholder.getAttribute('idx');
          if (idx == '0' && type == null) return true;
        }
      }
    }
    return false;
  }

  void _goToSlide(int index) {
    if (index < 0 || index >= _slides.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 15)),
        actions: [
          if (_slides.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_currentIndex + 1} / ${_slides.length}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '使用系统工具打开',
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
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在解析 PPT...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return _buildError(_error!);
    }

    if (_slides.isEmpty) {
      return _buildError('未找到幻灯片内容');
    }

    return Column(
      children: [
        // 幻灯片内容区域
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              return _buildSlideCard(_slides[index]);
            },
          ),
        ),

        // 底部导航栏
        _buildNavigationBar(),
      ],
    );
  }

  Widget _buildSlideCard(_SlideData slide) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 幻灯片标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${slide.slideNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      slide.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // 幻灯片内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildParagraphWidgets(slide),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildParagraphWidgets(_SlideData slide) {
    final widgets = <Widget>[];

    for (final para in slide.paragraphs) {
      if (para.isTitle) continue; // 标题已在顶部显示

      final indent = para.level * 20.0;
      final fontSize = para.fontSize ?? (para.isBold ? 16.0 : 14.0);

      // 根据层级决定前缀符号
      String prefix;
      Color bulletColor;
      if (para.level == 0) {
        prefix = para.isBold ? '' : '\u2022 '; // 无缩进的正文用圆点
        bulletColor = Theme.of(context).colorScheme.primary;
      } else if (para.level == 1) {
        prefix = '  \u25E6 '; // 空心圆点
        bulletColor = Colors.grey[600]!;
      } else {
        prefix = '    \u2013 '; // 短破折号
        bulletColor = Colors.grey[500]!;
      }

      widgets.add(
        Padding(
          padding: EdgeInsets.only(left: indent, bottom: 8),
          child: RichText(
            text: TextSpan(
              children: [
                if (!para.isBold && prefix.isNotEmpty)
                  TextSpan(
                    text: prefix,
                    style: TextStyle(
                      color: bulletColor,
                      fontSize: fontSize,
                      height: 1.6,
                    ),
                  ),
                TextSpan(
                  text: para.text,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: fontSize,
                    fontWeight: para.isBold ? FontWeight.w600 : FontWeight.normal,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      widgets.add(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(Icons.text_snippet_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  '此页无文本内容',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '可能包含图片或图表，请使用系统工具查看完整内容',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildNavigationBar() {
    final total = _slides.length;
    final isFirst = _currentIndex == 0;
    final isLast = _currentIndex == total - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 首页
            _NavButton(
              icon: Icons.first_page,
              label: '首页',
              enabled: !isFirst,
              onPressed: () => _goToSlide(0),
            ),

            const SizedBox(width: 8),

            // 上一页
            _NavButton(
              icon: Icons.chevron_left,
              label: '上一页',
              enabled: !isFirst,
              onPressed: () => _goToSlide(_currentIndex - 1),
            ),

            const Spacer(),

            // 页码指示器
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentIndex + 1} / $total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),

            const Spacer(),

            // 下一页
            _NavButton(
              icon: Icons.chevron_right,
              label: '下一页',
              enabled: !isLast,
              onPressed: () => _goToSlide(_currentIndex + 1),
            ),

            const SizedBox(width: 8),

            // 末页
            _NavButton(
              icon: Icons.last_page,
              label: '末页',
              enabled: !isLast,
              onPressed: () => _goToSlide(total - 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.slideshow, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('使用系统工具打开'),
              onPressed: () {
                FileOpenerService.openExternalFile(context, widget.filePath);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── 导航按钮组件 ───────────────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: enabled
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: enabled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400],
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[400],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 数据模型 ───────────────────────────────────────────────────────────────

class _SlideData {
  final int slideNumber;
  final String title;
  final List<_ParagraphData> paragraphs;

  _SlideData({
    required this.slideNumber,
    required this.title,
    required this.paragraphs,
  });
}

class _ParagraphData {
  final String text;
  final bool isTitle;
  final bool isBold;
  final double? fontSize;
  final int level;

  _ParagraphData({
    required this.text,
    required this.isTitle,
    this.isBold = false,
    this.fontSize,
    this.level = 0,
  });
}
