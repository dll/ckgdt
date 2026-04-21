import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../../../services/file_opener_service.dart';
import '../../../services/ppt_export_service.dart';
import '../../../services/tts_flutter_service.dart';
import '../../pages/quiz/quiz_page.dart';

/// 应用内 PPTX 放映器 — 接近 PowerPoint / WPS 演示效果
///
/// 功能：
/// • 解析 PPTX（ZIP + XML），提取文字、图片、背景、主题色
/// • 全屏沉浸式放映（默认），自动隐藏控件
/// • 键盘导航（方向键 / 空格 / ESC / F 全屏 / G 概览）
/// • 手势导航（滑动翻页、点击左右区域翻页、点击中央切换控件）
/// • 幻灯片概览网格视图
/// • 自动播放 + 可调间隔
/// • 进度条 / 页码指示 / 缩略图导航条
class InAppPptViewerPage extends StatefulWidget {
  final String filePath;
  final String title;
  final String? chapter;

  const InAppPptViewerPage({
    super.key,
    required this.filePath,
    required this.title,
    this.chapter,
  });

  @override
  State<InAppPptViewerPage> createState() => _InAppPptViewerPageState();
}

class _InAppPptViewerPageState extends State<InAppPptViewerPage> {
  // ── 核心状态 ──────────────────────────────────────────────────────────
  List<_SlideData> _slides = [];
  List<File> _slideImages = [];       // COM 导出的 PNG 图片（Windows）
  bool get _useImageMode => _slideImages.isNotEmpty;
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;
  String _loadingMsg = '正在解析 PPT...';
  bool _completionShown = false;

  // ── 放映模式 ──────────────────────────────────────────────────────────
  bool _isFullScreen = true;
  bool _showOverlay = true;
  bool _isOverview = false;
  bool _isAutoPlaying = false;
  bool _showThumbnails = false;
  int _autoPlaySec = 5;

  // ── 控制器 / 计时器 ───────────────────────────────────────────────────
  final PageController _pageController = PageController();
  final FocusNode _focusNode = FocusNode();
  Timer? _autoTimer;
  Timer? _hideTimer;

  // ── PPTX 解析缓存 ─────────────────────────────────────────────────────
  final Map<String, Uint8List> _archive = {};
  final Map<String, Color> _themeColors = {};
  double _slideWidthEmu = 12192000;
  double _slideHeightEmu = 6858000;
  double get _slideAspect => _slideWidthEmu / _slideHeightEmu;

  // ═══════════════════════════════════════════════════════════════════════
  //  生命周期
  // ═══════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _parsePptx();
    _scheduleHide();
  }

  void _showQuizPrompt() {
    TtsFlutterService.instance.speak('课件学习完成，是否立即进入章节测验检验学习效果？');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('课件学完'),
        content: const Text('PPT 已浏览完毕！\n建议立即测验，巩固所学知识。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const QuizPage(),
                ),
              );
            },
            icon: const Icon(Icons.quiz, size: 18),
            label: const Text('立即测验'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    _autoTimer?.cancel();
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  PPTX 解析
  // ═══════════════════════════════════════════════════════════════════════

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

      // ── Windows: 优先使用 PowerPoint/WPS COM 导出高清图片 ──
      if (Platform.isWindows) {
        setState(() => _loadingMsg = '正在通过 PowerPoint/WPS 导出幻灯片...');
        final images = await PptExportService.exportSlides(widget.filePath);
        if (images != null && images.isNotEmpty) {
          _slideImages = images;
          // 创建占位 _slides 以便导航逻辑正常运作
          _slides = List.generate(images.length, (i) => _SlideData(
            slideNumber: i + 1,
            title: '',
          ));
          if (!mounted) return;
          setState(() => _loading = false);
          if (_isFullScreen) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          }
          return;
        }
        // COM 导出失败，降级为 XML 解析
        if (mounted) {
          setState(() => _loadingMsg = '正在解析 PPT（内置解析器）...');
        }
      }

      // ── 降级：XML 解析 ──
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1. 读入全部文件
      for (final entry in archive) {
        if (!entry.isFile) continue;
        _archive[entry.name] =
            Uint8List.fromList(entry.content as List<int>);
      }

      // 2. 幻灯片尺寸
      _parseSlideDimensions();

      // 3. 主题颜色
      _parseTheme();

      // 4. 收集幻灯片
      final slideMap = <int, String>{};
      for (final name in _archive.keys) {
        final m = RegExp(r'ppt/slides/slide(\d+)\.xml').firstMatch(name);
        if (m != null) slideMap[int.parse(m.group(1)!)] = name;
      }
      if (slideMap.isEmpty) {
        setState(() {
          _error = '无法解析：未找到幻灯片内容';
          _loading = false;
        });
        return;
      }

      // 5. 按编号排序并解析
      final keys = slideMap.keys.toList()..sort();
      final slides = <_SlideData>[];
      for (final k in keys) {
        final xml = utf8.decode(_archive[slideMap[k]!]!);
        final rels = _slideRels(k);
        slides.add(_parseSlide(xml, k, rels));
      }

      if (!mounted) return;
      setState(() {
        _slides = slides;
        _loading = false;
      });
      // 进入全屏
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '解析 PPTX 失败: $e';
        _loading = false;
      });
    }
  }

  // ── 读取幻灯片尺寸 ────────────────────────────────────────────────────

  void _parseSlideDimensions() {
    try {
      final data = _archive['ppt/presentation.xml'];
      if (data == null) return;
      final doc = XmlDocument.parse(utf8.decode(data));
      final sz = doc.findAllElements('p:sldSz').firstOrNull;
      if (sz != null) {
        final cx = double.tryParse(sz.getAttribute('cx') ?? '');
        final cy = double.tryParse(sz.getAttribute('cy') ?? '');
        if (cx != null && cy != null && cy > 0) {
          _slideWidthEmu = cx;
          _slideHeightEmu = cy;
        }
      }
    } catch (_) {}
  }

  // ── 读取主题颜色 ──────────────────────────────────────────────────────

  void _parseTheme() {
    try {
      final themeKey = _archive.keys.firstWhere(
        (k) => RegExp(r'ppt/theme/theme\d+\.xml').hasMatch(k),
        orElse: () => '',
      );
      if (themeKey.isEmpty) return;
      final doc = XmlDocument.parse(utf8.decode(_archive[themeKey]!));
      for (final scheme in doc.findAllElements('a:clrScheme')) {
        for (final child in scheme.children.whereType<XmlElement>()) {
          final name = child.localName;
          final srgb = child.findAllElements('a:srgbClr').firstOrNull;
          if (srgb != null) {
            final v = srgb.getAttribute('val');
            if (v != null && v.length == 6) {
              _themeColors[name] = Color(int.parse('FF$v', radix: 16));
            }
          }
          if (!_themeColors.containsKey(name)) {
            final sys = child.findAllElements('a:sysClr').firstOrNull;
            final v = sys?.getAttribute('lastClr');
            if (v != null && v.length == 6) {
              _themeColors[name] = Color(int.parse('FF$v', radix: 16));
            }
          }
        }
      }
    } catch (_) {}
  }

  // ── 幻灯片关系文件 ────────────────────────────────────────────────────

  Map<String, String> _slideRels(int num) {
    final map = <String, String>{};
    try {
      final path = 'ppt/slides/_rels/slide$num.xml.rels';
      final data = _archive[path];
      if (data == null) return map;
      final doc = XmlDocument.parse(utf8.decode(data));
      for (final rel in doc.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id == null || target == null) continue;
        String resolved = target;
        if (target.startsWith('../')) {
          resolved = 'ppt/${target.substring(3)}';
        } else if (!target.startsWith('ppt/') && !target.startsWith('/')) {
          resolved = 'ppt/slides/$target';
        }
        map[id] = resolved;
      }
    } catch (_) {}
    return map;
  }

  // ── 解析单张幻灯片 ────────────────────────────────────────────────────

  _SlideData _parseSlide(
      String xmlStr, int slideNum, Map<String, String> rels) {
    try {
      final doc = XmlDocument.parse(xmlStr);
      String? title;
      String? subtitle;
      final body = <_ParagraphData>[];
      final images = <_SlideImage>[];
      Color bgColor = const Color(0xFF1e3a5f);
      List<Color>? bgGradient;
      _SlideImage? bgImage;

      // ── 背景 ──
      final bgEl = doc.findAllElements('p:bg').firstOrNull;
      if (bgEl != null) {
        // 纯色
        final sf = bgEl.findAllElements('a:solidFill').firstOrNull;
        if (sf != null) bgColor = _colorFromFill(sf) ?? bgColor;
        // 渐变
        final gf = bgEl.findAllElements('a:gradFill').firstOrNull;
        if (gf != null) {
          final gColors = _gradientColors(gf);
          if (gColors.isNotEmpty) bgGradient = gColors;
        }
        // 图片背景
        final bf = bgEl.findAllElements('a:blipFill').firstOrNull;
        if (bf != null) {
          final img = _imageFromBlipFill(bf, rels);
          if (img != null) bgImage = img;
        }
      }

      // ── 图片元素 (p:pic) ──
      for (final pic in doc.findAllElements('p:pic')) {
        final img = _parsePic(pic, rels);
        if (img != null) images.add(img);
      }

      // ── 文本形状 (p:sp) ──
      for (final shape in doc.findAllElements('p:sp')) {
        final ph = _phType(shape);
        if (ph == 'dt' || ph == 'ftr' || ph == 'sldNum') continue;
        final isTitle = ph == 'title' || ph == 'ctrTitle';
        final isSub = ph == 'subTitle';

        for (final txBody in shape.findAllElements('p:txBody')) {
          for (final p in txBody.findAllElements('a:p')) {
            final para = _parsePara(p);
            if (para == null) continue;
            if (isTitle) {
              title = title == null ? para.text : '$title ${para.text}';
            } else if (isSub) {
              subtitle =
                  subtitle == null ? para.text : '$subtitle\n${para.text}';
            } else {
              body.add(para);
            }
          }
        }
      }

      // ── 表格 (a:tbl) ──
      for (final gf in doc.findAllElements('p:graphicFrame')) {
        for (final tbl in gf.findAllElements('a:tbl')) {
          body.addAll(_parseTable(tbl));
        }
      }

      // ── 分组形状内的图片 ──
      for (final grp in doc.findAllElements('p:grpSp')) {
        for (final pic in grp.findAllElements('p:pic')) {
          final img = _parsePic(pic, rels);
          if (img != null) images.add(img);
        }
      }

      return _SlideData(
        slideNumber: slideNum,
        title: title ?? '',
        subtitle: subtitle,
        paragraphs: body,
        images: images,
        bgColor: bgColor,
        bgGradient: bgGradient,
        bgImage: bgImage,
      );
    } catch (e) {
      return _SlideData(
        slideNumber: slideNum,
        title: '',
        paragraphs: [_ParagraphData(text: '(解析失败)')],
      );
    }
  }

  // ── 解析段落 ──────────────────────────────────────────────────────────

  _ParagraphData? _parsePara(XmlElement p) {
    final parts = <String>[];
    bool bold = false, italic = false;
    double? fSize;
    Color? fColor;
    TextAlign align = TextAlign.left;
    int level = 0;

    final pPr = p.findAllElements('a:pPr').firstOrNull;
    if (pPr != null) {
      level = int.tryParse(pPr.getAttribute('lvl') ?? '') ?? 0;
      switch (pPr.getAttribute('algn')) {
        case 'ctr':
          align = TextAlign.center;
          break;
        case 'r':
          align = TextAlign.right;
          break;
        case 'just':
          align = TextAlign.justify;
          break;
      }
    }

    for (final run in p.findAllElements('a:r')) {
      final rPr = run.findAllElements('a:rPr').firstOrNull;
      if (rPr != null) {
        if (rPr.getAttribute('b') == '1') bold = true;
        if (rPr.getAttribute('i') == '1') italic = true;
        final sz = rPr.getAttribute('sz');
        if (sz != null) fSize = (int.tryParse(sz) ?? 1800) / 100.0;
        fColor ??= _colorFromFill(rPr);
      }
      for (final t in run.findAllElements('a:t')) {
        if (t.innerText.isNotEmpty) parts.add(t.innerText);
      }
    }

    if (parts.isEmpty) return null;
    final text = parts.join('');
    if (text.trim().isEmpty) return null;

    return _ParagraphData(
      text: text,
      isBold: bold,
      isItalic: italic,
      fontSize: fSize,
      level: level,
      color: fColor,
      textAlign: align,
    );
  }

  // ── 解析图片元素 ──────────────────────────────────────────────────────

  _SlideImage? _parsePic(XmlElement pic, Map<String, String> rels) {
    try {
      // 获取 r:embed 属性
      final blip = pic.findAllElements('a:blip').firstOrNull;
      if (blip == null) return null;
      final rId = _embedRId(blip);
      if (rId == null) return null;

      final mediaPath = rels[rId];
      if (mediaPath == null) return null;
      final bytes = _archive[mediaPath];
      if (bytes == null || bytes.isEmpty) return null;

      // 位置和大小 (EMU)
      double relX = 0, relY = 0, relW = 1, relH = 1;
      final xfrm = pic.findAllElements('a:xfrm').firstOrNull;
      if (xfrm != null) {
        final off = xfrm.findAllElements('a:off').firstOrNull;
        final ext = xfrm.findAllElements('a:ext').firstOrNull;
        if (off != null) {
          relX = (double.tryParse(off.getAttribute('x') ?? '') ?? 0) /
              _slideWidthEmu;
          relY = (double.tryParse(off.getAttribute('y') ?? '') ?? 0) /
              _slideHeightEmu;
        }
        if (ext != null) {
          relW = (double.tryParse(ext.getAttribute('cx') ?? '') ?? 0) /
              _slideWidthEmu;
          relH = (double.tryParse(ext.getAttribute('cy') ?? '') ?? 0) /
              _slideHeightEmu;
        }
      }

      return _SlideImage(
        bytes: bytes,
        relX: relX.clamp(0.0, 1.0),
        relY: relY.clamp(0.0, 1.0),
        relW: relW.clamp(0.0, 1.0),
        relH: relH.clamp(0.0, 1.0),
      );
    } catch (_) {
      return null;
    }
  }

  /// 从 blipFill 解析图片（背景用）
  _SlideImage? _imageFromBlipFill(
      XmlElement blipFill, Map<String, String> rels) {
    final blip = blipFill.findAllElements('a:blip').firstOrNull;
    if (blip == null) return null;
    final rId = _embedRId(blip);
    if (rId == null) return null;
    final path = rels[rId];
    if (path == null) return null;
    final bytes = _archive[path];
    if (bytes == null || bytes.isEmpty) return null;
    return _SlideImage(bytes: bytes);
  }

  // ── 解析表格 ──────────────────────────────────────────────────────────

  List<_ParagraphData> _parseTable(XmlElement tbl) {
    final result = <_ParagraphData>[];
    try {
      for (final tr in tbl.findAllElements('a:tr')) {
        final cells = <String>[];
        for (final tc in tr.findAllElements('a:tc')) {
          final sb = StringBuffer();
          for (final t in tc.findAllElements('a:t')) {
            sb.write(t.innerText);
          }
          cells.add(sb.toString().trim());
        }
        if (cells.isNotEmpty && cells.any((c) => c.isNotEmpty)) {
          result.add(_ParagraphData(
            text: cells.join('  |  '),
            isBold: result.isEmpty,
            fontSize: 13,
          ));
        }
      }
    } catch (_) {}
    return result;
  }

  // ── 颜色提取 ──────────────────────────────────────────────────────────

  Color? _colorFromFill(XmlElement el) {
    // 直接 srgbClr
    final srgb = el.findAllElements('a:srgbClr').firstOrNull;
    if (srgb != null) {
      final v = srgb.getAttribute('val');
      if (v != null && v.length == 6) {
        return Color(int.parse('FF$v', radix: 16));
      }
    }
    // 主题色引用
    final scheme = el.findAllElements('a:schemeClr').firstOrNull;
    if (scheme != null) {
      final name = scheme.getAttribute('val');
      if (name != null && _themeColors.containsKey(name)) {
        return _themeColors[name];
      }
    }
    return null;
  }

  List<Color> _gradientColors(XmlElement gradFill) {
    final colors = <Color>[];
    for (final gs in gradFill.findAllElements('a:gs')) {
      final c = _colorFromFill(gs);
      if (c != null) colors.add(c);
    }
    return colors;
  }

  // ── 占位符类型 ────────────────────────────────────────────────────────

  String? _phType(XmlElement shape) {
    for (final nv in shape.findAllElements('p:nvSpPr')) {
      for (final pr in nv.findAllElements('p:nvPr')) {
        for (final ph in pr.findAllElements('p:ph')) {
          final type = ph.getAttribute('type');
          if (type != null) return type;
          if (ph.getAttribute('idx') == '0') return 'title';
        }
      }
    }
    return null;
  }

  /// 提取 r:embed 属性（兼容不同命名空间写法）
  String? _embedRId(XmlElement blip) {
    var v = blip.getAttribute('r:embed');
    if (v != null) return v;
    for (final a in blip.attributes) {
      if (a.localName == 'embed') return a.value;
    }
    return null;
  }

  /// 根据背景亮度选择文字颜色
  Color _textColorFor(Color bg) {
    return bg.computeLuminance() > 0.45
        ? const Color(0xFF1a1a2e)
        : Colors.white;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  导航 / 控制
  // ═══════════════════════════════════════════════════════════════════════

  void _goTo(int index) {
    if (index < 0 || index >= _slides.length) return;
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  void _next() {
    if (_currentIndex < _slides.length - 1) _goTo(_currentIndex + 1);
  }

  void _prev() {
    if (_currentIndex > 0) _goTo(_currentIndex - 1);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter) {
      _next();
      _resetHide();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.backspace) {
      _prev();
      _resetHide();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _goTo(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _goTo(_slides.length - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_isOverview) {
        setState(() => _isOverview = false);
      } else if (_isFullScreen) {
        _toggleFullScreen();
      } else {
        Navigator.pop(context);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _toggleFullScreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      _toggleOverview();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      _toggleAutoPlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _toggleOverview() {
    setState(() {
      _isOverview = !_isOverview;
      if (_isOverview) _stopAutoPlay();
    });
  }

  void _toggleAutoPlay() {
    if (_isAutoPlaying) {
      _stopAutoPlay();
    } else {
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(Duration(seconds: _autoPlaySec), (_) {
      if (_currentIndex < _slides.length - 1) {
        _next();
      } else {
        _goTo(0); // 循环
      }
    });
    setState(() => _isAutoPlaying = true);
  }

  void _stopAutoPlay() {
    _autoTimer?.cancel();
    setState(() => _isAutoPlaying = false);
  }

  // ── 控件显示/隐藏 ─────────────────────────────────────────────────────

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
    if (_showOverlay) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showOverlay && !_isOverview) {
        setState(() => _showOverlay = false);
      }
    });
  }

  void _resetHide() {
    if (!_showOverlay) setState(() => _showOverlay = true);
    _scheduleHide();
  }

  // ── 点击区域处理 ──────────────────────────────────────────────────────

  void _onSlideTap(TapUpDetails details) {
    final w = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    if (x < w * 0.25) {
      _prev();
      _resetHide();
    } else if (x > w * 0.75) {
      _next();
      _resetHide();
    } else {
      _toggleOverlay();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  UI — 主框架
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen
          ? null
          : AppBar(
              title:
                  Text(widget.title, style: const TextStyle(fontSize: 15)),
              backgroundColor: const Color(0xFF16213e),
              foregroundColor: Colors.white,
              actions: [
                if (_slides.isNotEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${_currentIndex + 1} / ${_slides.length}',
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white70),
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(
                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
                  tooltip: '全屏',
                  onPressed: _toggleFullScreen,
                ),
                IconButton(
                  icon: const Icon(Icons.grid_view),
                  tooltip: '概览',
                  onPressed: _toggleOverview,
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  tooltip: '外部打开',
                  onPressed: () => FileOpenerService.openExternalFile(
                      context, widget.filePath),
                ),
              ],
            ),
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError(_error!);
    if (_slides.isEmpty) return _buildError('未找到幻灯片内容');
    if (_isOverview) return _buildOverview();
    return _buildSlideshow();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  UI — 放映视图
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSlideshow() {
    return Stack(
      children: [
        // ── 幻灯片 PageView ──
        PageView.builder(
          controller: _pageController,
          itemCount: _slides.length,
          onPageChanged: (i) {
            setState(() => _currentIndex = i);
            _resetHide();
            // 到达最后一页时提示测验
            if (i == _slides.length - 1 && !_completionShown) {
              _completionShown = true;
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _showQuizPrompt();
              });
            }
          },
          itemBuilder: (_, i) => GestureDetector(
            onTapUp: _onSlideTap,
            onDoubleTap: _toggleFullScreen,
            child: _buildSlide(_slides[i]),
          ),
        ),

        // ── 控件覆盖层 ──
        IgnorePointer(
          ignoring: !_showOverlay,
          child: AnimatedOpacity(
            opacity: _showOverlay ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: _buildOverlay(),
          ),
        ),

        // ── 底部进度条（始终可见） ──
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildProgressBar(),
        ),

        // ── 缩略图导航条 ──
        if (_showThumbnails && _showOverlay)
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            height: 72,
            child: _buildThumbnailStrip(),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  UI — 概览网格
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildOverview() {
    return Column(
      children: [
        // 顶栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF16213e),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => setState(() => _isOverview = false),
                ),
                const SizedBox(width: 8),
                Text('幻灯片概览 (${_slides.length})',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_currentIndex + 1} / ${_slides.length}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
        ),
        // 网格
        Expanded(
          child: LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 900
                ? 4
                : box.maxWidth > 600
                    ? 3
                    : 2;
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: _slideAspect,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: _slides.length,
              itemBuilder: (_, i) => _buildOverviewTile(i),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildOverviewTile(int index) {
    final sel = index == _currentIndex;

    // ── 图片模式：直接显示导出的 PNG 缩略图 ──
    if (_useImageMode && index < _slideImages.length) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _currentIndex = index;
            _isOverview = false;
          });
          _pageController.jumpToPage(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: sel
                ? Border.all(color: const Color(0xFF667eea), width: 3)
                : Border.all(color: Colors.white24, width: 1),
            boxShadow: sel
                ? [
                    BoxShadow(
                        color: const Color(0xFF667eea).withValues(alpha: 0.4),
                        blurRadius: 12)
                  ]
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(_slideImages[index],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${index + 1}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── XML 解析模式 ──
    final slide = _slides[index];
    final tc = _textColorFor(slide.bgColor);
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
          _isOverview = false;
        });
        _pageController.jumpToPage(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: slide.bgColor,
          gradient: slide.bgGradient != null
              ? LinearGradient(
                  colors: slide.bgGradient!,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)
              : null,
          borderRadius: BorderRadius.circular(8),
          border: sel
              ? Border.all(color: const Color(0xFF667eea), width: 3)
              : Border.all(color: Colors.white24, width: 1),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: const Color(0xFF667eea).withValues(alpha: 0.4),
                      blurRadius: 12)
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景图
              if (slide.bgImage != null)
                Image.memory(slide.bgImage!.bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              // 第一张图片作为预览
              if (slide.bgImage == null && slide.images.isNotEmpty)
                Opacity(
                  opacity: 0.3,
                  child: Image.memory(slide.images.first.bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              // 标题
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(slide.title,
                          style: TextStyle(
                            color: tc,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 4)
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                      if (slide.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(slide.subtitle!,
                            style: TextStyle(
                                color: tc.withValues(alpha: 0.7),
                                fontSize: 9),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
              ),
              // 页码角标
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${index + 1}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  UI — 单张幻灯片渲染
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSlide(_SlideData slide) {
    // ── 图片模式：直接显示 PowerPoint/WPS 导出的 PNG ──
    if (_useImageMode) {
      final idx = slide.slideNumber - 1;
      if (idx >= 0 && idx < _slideImages.length) {
        return Container(
          color: Colors.black,
          child: Center(
            child: Image.file(
              _slideImages[idx],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Center(
                child: Text('幻灯片 ${slide.slideNumber} 加载失败',
                    style: const TextStyle(color: Colors.white54)),
              ),
            ),
          ),
        );
      }
    }

    // ── XML 解析模式 ──
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _slideAspect,
          child: Container(
            decoration: BoxDecoration(
              color: slide.bgColor,
              gradient: slide.bgGradient != null && slide.bgGradient!.length >= 2
                  ? LinearGradient(
                      colors: slide.bgGradient!,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)
                  : null,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景图片
                  if (slide.bgImage != null)
                    Image.memory(slide.bgImage!.bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),

                  // 定位图片层（按 PPTX 坐标放置）
                  ..._buildPositionedImages(slide),

                  // 文字内容层
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 28, 36, 24),
                    child: _buildSlideContent(slide),
                  ),

                  // 右下角页码
                  Positioned(
                    right: 16,
                    bottom: 10,
                    child: Text(
                      '${slide.slideNumber}',
                      style: TextStyle(
                        color: _textColorFor(slide.bgColor)
                            .withValues(alpha: 0.25),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 按 PPTX 坐标放置图片
  List<Widget> _buildPositionedImages(_SlideData slide) {
    // 排除面积极大的图片（已作为背景处理或单独显示）
    // 以及面积极小的图片（可能是装饰/图标）
    final positioned = <Widget>[];
    for (final img in slide.images) {
      final area = img.relW * img.relH;
      // 大面积图片（>60% 幻灯片面积）作为底层全屏显示
      if (area > 0.6) {
        positioned.insert(
          0,
          Positioned.fill(
            child: Opacity(
              opacity: slide.paragraphs.isNotEmpty ? 0.35 : 1.0,
              child: Image.memory(img.bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ),
        );
        continue;
      }
      // 极小图片（<3%）跳过（通常是装饰元素或小图标）
      if (area < 0.03) continue;

      // 正常大小图片 → 按坐标定位
      positioned.add(
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          child: LayoutBuilder(builder: (ctx, box) {
            return Stack(
              children: [
                Positioned(
                  left: img.relX * box.maxWidth,
                  top: img.relY * box.maxHeight,
                  width: img.relW * box.maxWidth,
                  height: img.relH * box.maxHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(img.bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink()),
                  ),
                ),
              ],
            );
          }),
        ),
      );
    }
    return positioned;
  }

  // ── 幻灯片内容 ────────────────────────────────────────────────────────

  Widget _buildSlideContent(_SlideData slide) {
    final tc = _textColorFor(slide.bgColor);
    final hasBody = slide.paragraphs.isNotEmpty;
    final hasInlineImages = slide.images
        .where((im) =>
            im.relW * im.relH >= 0.03 && im.relW * im.relH <= 0.6)
        .isEmpty;
    final isTitleSlide = !hasBody && hasInlineImages;

    // ── 纯标题页 ──
    if (isTitleSlide) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(slide.title,
              style: TextStyle(
                color: tc,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                height: 1.4,
                shadows: [
                  Shadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 6)
                ],
              ),
              textAlign: TextAlign.center),
          if (slide.subtitle != null) ...[
            const SizedBox(height: 16),
            Text(slide.subtitle!,
                style: TextStyle(
                  color: tc.withValues(alpha: 0.7),
                  fontSize: 18,
                  height: 1.5,
                ),
                textAlign: TextAlign.center),
          ],
        ],
      );
    }

    // ── 内容页 ──
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(slide.title,
            style: TextStyle(
              color: tc,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
              shadows: [
                Shadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4)
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        // 标题下划线
        Container(
          width: 60,
          height: 3,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF667eea), Color(0xFF764ba2)]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        if (slide.subtitle != null) ...[
          const SizedBox(height: 8),
          Text(slide.subtitle!,
              style: TextStyle(
                color: tc.withValues(alpha: 0.65),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              )),
        ],
        const SizedBox(height: 14),
        // 正文
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: slide.paragraphs
                  .map((p) => _buildParagraph(p, tc))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ── 段落渲染 ──────────────────────────────────────────────────────────

  Widget _buildParagraph(_ParagraphData para, Color defaultColor) {
    final indent = para.level * 24.0;
    final fs = para.fontSize?.clamp(10.0, 28.0) ??
        (para.isBold ? 17.0 : 15.0);
    final color = para.color ?? defaultColor.withValues(alpha: para.isBold ? 1.0 : 0.9);

    // 项目符号
    final String bullet;
    final Color bulletColor;
    switch (para.level) {
      case 0:
        bullet = para.isBold ? '' : '\u25CF  ';
        bulletColor = const Color(0xFF667eea);
        break;
      case 1:
        bullet = '\u25CB  ';
        bulletColor = const Color(0xFF8e9cc0);
        break;
      default:
        bullet = '\u2013  ';
        bulletColor = const Color(0xFF6b7a99);
        break;
    }

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 7),
      child: RichText(
        textAlign: para.textAlign,
        text: TextSpan(
          children: [
            if (bullet.isNotEmpty)
              TextSpan(
                text: bullet,
                style: TextStyle(
                    color: bulletColor, fontSize: fs, height: 1.7),
              ),
            TextSpan(
              text: para.text,
              style: TextStyle(
                color: color,
                fontSize: fs,
                fontWeight:
                    para.isBold ? FontWeight.w600 : FontWeight.normal,
                fontStyle:
                    para.isItalic ? FontStyle.italic : FontStyle.normal,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  UI — 控件覆盖层
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildOverlay() {
    return Column(
      children: [
        _buildTopBar(),
        const Spacer(),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: 8,
        right: 8,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_isFullScreen) {
                _toggleFullScreen();
              }
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 缩略图切换
          IconButton(
            icon: Icon(
              _showThumbnails
                  ? Icons.view_carousel
                  : Icons.view_carousel_outlined,
              color: _showThumbnails ? const Color(0xFF667eea) : Colors.white70,
              size: 22,
            ),
            tooltip: '缩略图',
            onPressed: () => setState(() => _showThumbnails = !_showThumbnails),
          ),
          // 概览
          IconButton(
            icon: const Icon(Icons.grid_view, color: Colors.white70, size: 22),
            tooltip: '概览 (G)',
            onPressed: _toggleOverview,
          ),
          // 全屏切换
          IconButton(
            icon: Icon(
              _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white70,
              size: 22,
            ),
            tooltip: '全屏 (F)',
            onPressed: _toggleFullScreen,
          ),
          // 外部打开
          IconButton(
            icon:
                const Icon(Icons.open_in_new, color: Colors.white70, size: 20),
            tooltip: '外部打开',
            onPressed: () =>
                FileOpenerService.openExternalFile(context, widget.filePath),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final total = _slides.length;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        left: 12,
        right: 12,
        top: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          // 首页
          _overlayBtn(Icons.first_page, '首页', () => _goTo(0),
              enabled: _currentIndex > 0),
          // 上一页
          _overlayBtn(Icons.chevron_left, '上一页', _prev,
              enabled: _currentIndex > 0),
          const SizedBox(width: 8),
          // 自动播放
          _overlayBtn(
            _isAutoPlaying ? Icons.pause_circle : Icons.play_circle,
            _isAutoPlaying ? '暂停 (P)' : '自动播放 (P)',
            _toggleAutoPlay,
            highlight: _isAutoPlaying,
          ),
          // 自动播放速度
          if (_isAutoPlaying)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _autoPlaySec = _autoPlaySec >= 10 ? 3 : _autoPlaySec + 1;
                  });
                  if (_isAutoPlaying) _startAutoPlay(); // 重启计时器
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667eea).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${_autoPlaySec}s',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11)),
                ),
              ),
            ),
          const Spacer(),
          // 页码
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_currentIndex + 1} / $total',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          // 下一页
          _overlayBtn(Icons.chevron_right, '下一页', _next,
              enabled: _currentIndex < total - 1),
          // 末页
          _overlayBtn(Icons.last_page, '末页', () => _goTo(total - 1),
              enabled: _currentIndex < total - 1),
        ],
      ),
    );
  }

  Widget _overlayBtn(IconData icon, String tip, VoidCallback onTap,
      {bool enabled = true, bool highlight = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: highlight
              ? BoxDecoration(
                  color: const Color(0xFF667eea).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Icon(icon,
              size: 24,
              color: enabled
                  ? (highlight ? const Color(0xFF667eea) : Colors.white)
                  : Colors.white24),
        ),
      ),
    );
  }

  // ── 缩略图导航条 ──────────────────────────────────────────────────────

  Widget _buildThumbnailStrip() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: _slides.length,
        itemBuilder: (_, i) {
          final sel = i == _currentIndex;

          // ── 图片模式缩略图 ──
          if (_useImageMode && i < _slideImages.length) {
            return GestureDetector(
              onTap: () => _goTo(i),
              child: Container(
                width: 100,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                  border: sel
                      ? Border.all(color: const Color(0xFF667eea), width: 2)
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Image.file(_slideImages[i],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 13)),
                          )),
                ),
              ),
            );
          }

          // ── XML 解析模式缩略图 ──
          final slide = _slides[i];
          return GestureDetector(
            onTap: () => _goTo(i),
            child: Container(
              width: 100,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: slide.bgColor,
                gradient: slide.bgGradient != null
                    ? LinearGradient(colors: slide.bgGradient!)
                    : null,
                borderRadius: BorderRadius.circular(4),
                border: sel
                    ? Border.all(color: const Color(0xFF667eea), width: 2)
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (slide.bgImage != null)
                      Image.memory(slide.bgImage!.bytes,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink()),
                    Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: _textColorFor(slide.bgColor)
                              .withValues(alpha: sel ? 1.0 : 0.5),
                          fontSize: sel ? 16 : 13,
                          fontWeight:
                              sel ? FontWeight.bold : FontWeight.normal,
                          shadows: [
                            Shadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 4)
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 进度条 ────────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    return LinearProgressIndicator(
      value: _slides.isEmpty ? 0 : (_currentIndex + 1) / _slides.length,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      valueColor:
          const AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
      minHeight: 3,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  UI — 加载 / 错误
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF667eea)),
          const SizedBox(height: 16),
          Text(_loadingMsg,
              style: const TextStyle(color: Colors.white70)),
        ],
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
            Icon(Icons.slideshow, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(color: Colors.white60, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('使用系统工具打开'),
              onPressed: () => FileOpenerService.openExternalFile(
                  context, widget.filePath),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  数据模型
// ═══════════════════════════════════════════════════════════════════════════

class _SlideData {
  final int slideNumber;
  final String title;
  final String? subtitle;
  final List<_ParagraphData> paragraphs;
  final List<_SlideImage> images;
  final Color bgColor;
  final List<Color>? bgGradient;
  final _SlideImage? bgImage;

  _SlideData({
    required this.slideNumber,
    required this.title,
    this.subtitle,
    List<_ParagraphData>? paragraphs,
    List<_SlideImage>? images,
    this.bgColor = const Color(0xFF1e3a5f),
    this.bgGradient,
    this.bgImage,
  })  : paragraphs = paragraphs ?? [],
        images = images ?? [];
}

class _ParagraphData {
  final String text;
  final bool isBold;
  final bool isItalic;
  final double? fontSize;
  final int level;
  final Color? color;
  final TextAlign textAlign;

  _ParagraphData({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.fontSize,
    this.level = 0,
    this.color,
    this.textAlign = TextAlign.left,
  });
}

class _SlideImage {
  final Uint8List bytes;
  final double relX;
  final double relY;
  final double relW;
  final double relH;

  _SlideImage({
    required this.bytes,
    this.relX = 0,
    this.relY = 0,
    this.relW = 1,
    this.relH = 1,
  });
}
