import 'dart:convert';
import 'dart:io';
import 'package:charset/charset.dart' show gbk;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../data/local/exam_analysis_dao.dart';
import '../../../../core/error_handler.dart';

class ExamAnalysisTab extends StatefulWidget {
  const ExamAnalysisTab({super.key});
  @override
  State<ExamAnalysisTab> createState() => _ExamAnalysisTabState();
}

class _ExamAnalysisTabState extends State<ExamAnalysisTab> {
  final _dao = ExamAnalysisDao();
  final _nameCtrl = TextEditingController();
  final _classCtrl = TextEditingController();
  final _specCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _analysisCtrl = TextEditingController();
  String _examStyle = '闭卷';
  int _itemCount = 10;
  int _studentCount = 0;
  List<List<double>> _grades = [];
  Map<String, dynamic> _stats = {};
  int? _currentId;
  int _tab = 0;

  // Electronic signature image paths (PNG)
  String? _teacherSignPath;
  String? _directorSignPath;
  String? _deanSignPath;

  bool get _hasData => _grades.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _timeCtrl.text = DateTime.now().toIso8601String().substring(0, 10);
    _loadLatest();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _classCtrl.dispose();
    _specCtrl.dispose();
    _sourceCtrl.dispose();
    _timeCtrl.dispose();
    _analysisCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLatest() async {
    try {
      final all = await _dao.getAll();
      if (all.isNotEmpty && mounted) _populateFromRow(all.first);
    } catch (e, st) {
      swallowDebug(e, tag: 'ExamAnalysisTab.loadLatest', stack: st);
    }
  }

  void _populateFromRow(Map<String, dynamic> row) {
    _currentId = row['id'] as int?;
    _nameCtrl.text = (row['course_name'] ?? '').toString();
    _classCtrl.text = (row['class_name'] ?? '').toString();
    _specCtrl.text = (row['speciality'] ?? '').toString();
    _sourceCtrl.text = (row['source'] ?? '').toString();
    _timeCtrl.text = (row['exam_time'] ?? '').toString();
    _examStyle = (row['exam_style'] ?? '闭卷').toString();
    _itemCount = (row['item_count'] as num?)?.toInt() ?? 10;
    _studentCount = (row['student_count'] as num?)?.toInt() ?? 0;
    _analysisCtrl.text = (row['analysis_text'] ?? '').toString();
    _grades = _dao.parseGrades(row['grades_json'] as String?);
    if (_grades.isEmpty && _studentCount > 0) _initGrades();
    _computeStats();
    setState(() {});
  }

  void _initGrades() {
    _grades = List.generate(_studentCount, (_) => List.filled(_itemCount, 0.0));
  }

  Map<String, dynamic> _buildRow() => {
    if (_currentId != null) 'id': _currentId,
    'course_name': _nameCtrl.text,
    'class_name': _classCtrl.text,
    'speciality': _specCtrl.text,
    'source': _sourceCtrl.text,
    'exam_time': _timeCtrl.text,
    'exam_style': _examStyle,
    'item_count': _itemCount,
    'student_count': _studentCount,
    'grades_json': ExamAnalysisDao.encodeGrades(_grades),
    'analysis_text': _analysisCtrl.text,
  };

  Future<void> _save() async {
    try {
      _currentId = await _dao.save(_buildRow());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功')));
    } catch (e, st) {
      swallowDebug(e, tag: 'ExamAnalysisTab.save', stack: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  void _computeStats() {
    _stats = ExamAnalysisDao.computeStatistics(_grades);
    setState(() {});
  }

  Future<void> _importIni() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['ini', 'txt']);
      if (result == null || result.files.isEmpty) return;
      final bytes = await File(result.files.first.path!).readAsBytes();
      String content;
      try { content = utf8.decode(bytes); } catch (_) {
        try { content = gbk.decode(bytes); } catch (_) { content = latin1.decode(bytes); }
      }
      _parseIni(content);
      _computeStats();
      setState(() {});
    } catch (e, st) {
      swallowDebug(e, tag: 'ExamAnalysisTab.importIni', stack: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  void _parseIni(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    String section = '';
    final grades = <List<double>>[];
    String? analysisText;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) { section = line.substring(1, line.length - 1).toLowerCase(); continue; }
      if (section == 'brief') {
        final eq = line.indexOf('=');
        if (eq < 0) continue;
        final key = line.substring(0, eq).trim().toLowerCase();
        final value = line.substring(eq + 1).trim();
        switch (key) {
          case 'speciality': _specCtrl.text = value; break;
          case 'class': _classCtrl.text = value; break;
          case 'course': _nameCtrl.text = value; break;
          case 'source': _sourceCtrl.text = value; break;
          case 'time': _timeCtrl.text = value; break;
          case 'style': _examStyle = value; break;
          case 'itemnumber': _itemCount = int.tryParse(value) ?? 10; break;
          case 'studentnumber': _studentCount = int.tryParse(value) ?? 0; break;
        }
      } else if (section == 'grade') {
        final parts = line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
        final row = <double>[];
        for (final p in parts) { final v = double.tryParse(p); if (v != null) row.add(v); }
        if (row.isNotEmpty) grades.add(row);
      } else if (section == 'analysis') {
        analysisText = (analysisText ?? '') + line;
      }
    }
    if (grades.isNotEmpty) {
      _grades = grades;
      _studentCount = grades.length;
      if (_itemCount <= 0 && grades.isNotEmpty) _itemCount = grades[0].length;
    } else if (_studentCount > 0) { _initGrades(); }
    if (analysisText != null && analysisText.isNotEmpty) _analysisCtrl.text = analysisText;
  }

  Future<void> _exportIni() async {
    try {
      final buf = StringBuffer()
        ..writeln('[brief]')
        ..writeln('Speciality=${_specCtrl.text}')
        ..writeln('Class=${_classCtrl.text}')
        ..writeln('Course=${_nameCtrl.text}')
        ..writeln('Source=${_sourceCtrl.text}')
        ..writeln('Time=${_timeCtrl.text}')
        ..writeln('Style=$_examStyle')
        ..writeln('ItemNumber=$_itemCount')
        ..writeln('StudentNumber=$_studentCount')
        ..writeln('')
        ..writeln('[grade]');
      for (final row in _grades) { buf.writeln(row.map((v) => v.toStringAsFixed(0)).join('\t')); }
      buf.writeln('');
      buf.writeln('[analysis]');
      if (_analysisCtrl.text.isNotEmpty) buf.writeln(_analysisCtrl.text);
      buf.writeln('');
      final result = await FilePicker.platform.saveFile(type: FileType.custom, allowedExtensions: ['ini'], fileName: '${_nameCtrl.text}试卷分析.ini');
      if (result == null) return;
      await File(result).writeAsString(buf.toString(), encoding: utf8);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出成功: $result')));
    } catch (e, st) {
      swallowDebug(e, tag: 'ExamAnalysisTab.exportIni', stack: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  void _resetAll() {
    setState(() {
      _currentId = null;
      _nameCtrl.clear(); _classCtrl.clear(); _specCtrl.clear(); _sourceCtrl.clear();
      _timeCtrl.text = DateTime.now().toIso8601String().substring(0, 10);
      _examStyle = '闭卷'; _itemCount = 10; _studentCount = 0;
      _grades = []; _analysisCtrl.clear(); _stats = {};
    });
  }

  void _syncGradeDimensions() {
    if (_studentCount <= 0 || _itemCount <= 0) { _grades = []; setState(() {}); return; }
    final old = _grades;
    final newGrades = <List<double>>[];
    for (var r = 0; r < _studentCount; r++) {
      final row = <double>[];
      for (var c = 0; c < _itemCount; c++) {
        row.add((r < old.length && c < old[r].length) ? old[r][c] : 0.0);
      }
      newGrades.add(row);
    }
    _grades = newGrades;
    _computeStats();
  }

  Future<void> _pickSignature(String label, ValueChanged<String?> onPicked) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path!;
      // Copy to app documents dir for persistence
      final ext = path.split('.').last.toLowerCase();
      final destDir = await _dao.getSignatureDir();
      final destPath = '$destDir/${label}_sign.$ext';
      await File(path).copy(destPath);
      onPicked(destPath);
      setState(() {});
    } catch (e, st) {
      swallowDebug(e, tag: 'ExamAnalysisTab.pickSignature', stack: st);
    }
  }

  void _removeSignature(String label, ValueChanged<String?> onClear) {
    onClear(null);
    setState(() {});
  }

  Widget _signUploadRow(ColorScheme cs, String label, String? path, ValueChanged<String?> onPicked, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          if (path != null && File(path).existsSync())
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Image.file(File(path), height: 32, fit: BoxFit.contain),
            )
          else
            Container(
              height: 36,
              width: 120,
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(child: Text('未上传', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4)))),
            ),
          const SizedBox(width: 8),
          _btn(Icons.upload_outlined, '上传', () => _pickSignature(label, onPicked), color: cs.primary),
          if (path != null) ...[
            const SizedBox(width: 4),
            _btn(Icons.close, '清除', onRemove, color: Colors.red.shade400),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(children: [
        _toolbar(cs),
        Expanded(child: Column(children: [
          _tabs(cs),
          const Divider(height: 1),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: _content(cs))),
        ])),
      ]),
    );
  }

  Widget _toolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.primary.withValues(alpha: 0.06),
      child: Row(children: [
        _btn(Icons.file_open_outlined, '导入', _importIni),
        const SizedBox(width: 8),
        _btn(Icons.file_download_outlined, '导出', _exportIni),
        const Spacer(),
        _btn(Icons.picture_as_pdf_outlined, 'PDF', _previewPdf),
        const SizedBox(width: 8),
        _btn(Icons.print_outlined, '打印', _printPdf),
        const SizedBox(width: 8),
        _btn(Icons.save_outlined, '保存', _save),
        const SizedBox(width: 8),
        _btn(Icons.refresh, '重置', _resetAll, color: Colors.red.shade400),
      ]),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return Material(color: Colors.transparent, child: InkWell(
      borderRadius: BorderRadius.circular(8), onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ));
  }

  Widget _tabs(ColorScheme cs) {
    final labels = ['基本信息', '成绩矩阵', '统计分析'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: cs.surfaceContainerLow,
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Padding(padding: const EdgeInsets.only(right: 4), child: ChoiceChip(
            label: Text(labels[i], style: const TextStyle(fontSize: 13)),
            selected: _tab == i,
            onSelected: (_) => setState(() => _tab = i),
            selectedColor: cs.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(color: _tab == i ? cs.primary : null, fontWeight: FontWeight.w600),
          )),
      ]),
    );
  }

  Widget _content(ColorScheme cs) {
    switch (_tab) {
      case 0: return _basicInfo(cs);
      case 1: return _scoreMatrix(cs);
      case 2: return _statistics(cs);
      default: return const SizedBox.shrink();
    }
  }
  Widget _basicInfo(ColorScheme cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field('课程名称', _nameCtrl, hint: '如：软件工程基础'),
      _field('班级', _classCtrl, hint: '如：计科212'),
      _field('专业', _specCtrl, hint: '如：计科'),
      _field('数据来源', _sourceCtrl, hint: '如：任课教师命题'),
      _field('考试时间', _timeCtrl, hint: '如：2024/1/3'),
      const SizedBox(height: 12),
      Row(children: [
        const Text('考试方式：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        for (final s in ['闭卷', '开卷'])
          Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
            label: Text(s), selected: _examStyle == s,
            onSelected: (_) => setState(() => _examStyle = s),
            selectedColor: cs.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(fontSize: 13, color: _examStyle == s ? cs.primary : null, fontWeight: FontWeight.w600),
          )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _numField('题数', _itemCount, (v) { _itemCount = v; _syncGradeDimensions(); })),
        const SizedBox(width: 16),
        Expanded(child: _numField('考试人数', _studentCount, (v) { _studentCount = v; _syncGradeDimensions(); })),
      ]),
      const SizedBox(height: 16),
      Text('成绩矩阵：${_grades.length}名学生 x ${_grades.isNotEmpty ? _grades[0].length : 0}题',
          style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6))),
      const SizedBox(height: 20),
      Text('电子签名（可选，用于PDF报告）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 8),
      _signUploadRow(cs, '任课教师', _teacherSignPath, (p) => _teacherSignPath = p, () => _removeSignature('teacher', (p) => _teacherSignPath = p)),
      _signUploadRow(cs, '系主任', _directorSignPath, (p) => _directorSignPath = p, () => _removeSignature('director', (p) => _directorSignPath = p)),
      _signUploadRow(cs, '院长', _deanSignPath, (p) => _deanSignPath = p, () => _removeSignature('dean', (p) => _deanSignPath = p)),
    ]);
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, hintText: hint, isDense: true,
        border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      style: const TextStyle(fontSize: 14),
    ));
  }

  Widget _numField(String label, int value, ValueChanged<int> onChange) {
    return TextField(
      decoration: InputDecoration(labelText: label, isDense: true,
        border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      keyboardType: TextInputType.number,
      controller: TextEditingController(text: value.toString()),
      style: const TextStyle(fontSize: 14),
      onSubmitted: (v) { final p = int.tryParse(v); if (p != null && p > 0) onChange(p); },
    );
  }
  Future<void> _batchImportGrades() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
      if (result == null || result.files.isEmpty) return;
      final bytes = await File(result.files.first.path!).readAsBytes();
      String content;
      try { content = utf8.decode(bytes); } catch (_) {
        try { content = gbk.decode(bytes); } catch (_) { content = latin1.decode(bytes); }
      }
      final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) return;
      final newGrades = <List<double>>[];
      for (final line in lines) {
        final parts = line.split(RegExp(r'[\t,;|]+')).where((s) => s.trim().isNotEmpty);
        final row = <double>[];
        for (final p in parts) {
          final v = double.tryParse(p.trim());
          if (v != null) row.add(v);
        }
        if (row.isNotEmpty) newGrades.add(row);
      }
      if (newGrades.isEmpty) return;
      setState(() {
        _grades = newGrades;
        _studentCount = _grades.length;
        if (_grades.isNotEmpty) _itemCount = _grades[0].length;
        _computeStats();
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $_studentCount 名学生成绩')),
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'ExamAnalysisTab.batchImport', stack: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    }
  }

  Widget _scoreMatrix(ColorScheme cs) {
    if (_grades.isEmpty || _grades[0].isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.table_chart_outlined, size: 64, color: cs.onSurface.withValues(alpha: 0.2)),
        const SizedBox(height: 16),
        Text('请先在「基本信息」中设置学生数和题数', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
        const SizedBox(height: 12),
        _btn(Icons.upload_file_outlined, '批量导入成绩', _batchImportGrades),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('成绩录入表', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
        const Spacer(),
        _btn(Icons.upload_file_outlined, '批量导入', _batchImportGrades),
        const SizedBox(width: 8),
        _btn(Icons.add, '添加学生', () { setState(() { _grades.add(List.filled(_itemCount, 0.0)); _studentCount = _grades.length; }); }),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outline.withValues(alpha: 0.3))),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_matrixHeader(cs), ...List.generate(_grades.length, (i) => _matrixRow(cs, i))],
        )),
      ),
    ]);
  }

  Widget _matrixHeader(ColorScheme cs) {
    final cells = <Widget>[Container(width: 60, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), border: Border(right: BorderSide(color: cs.outline.withValues(alpha: 0.2)))),
      child: const Text('学生', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11), textAlign: TextAlign.center))];
    for (var c = 0; c < _itemCount; c++) {
      cells.add(Container(width: 48, padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), border: Border(right: BorderSide(color: cs.outline.withValues(alpha: 0.2)))),
        child: Text('题${c+1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11), textAlign: TextAlign.center)));
    }
    cells.add(Container(width: 56, padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08)),
      child: const Text('总分', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11), textAlign: TextAlign.center)));
    return Row(mainAxisSize: MainAxisSize.min, children: cells);
  }

  Widget _matrixRow(ColorScheme cs, int ri) {
    final total = _grades[ri].fold<double>(0, (a, b) => a + b);
    final bg = ri % 2 == 0 ? Colors.transparent : cs.surfaceContainerLow;
    final cells = <Widget>[Container(width: 60, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, border: Border(right: BorderSide(color: cs.outline.withValues(alpha: 0.15)))),
      child: Text('${ri+1}', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center))];
    for (var c = 0; c < _itemCount; c++) {
      cells.add(_scoreCell(cs, ri, c, bg));
    }
    cells.add(Container(width: 56, padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: bg),
      child: Text(total.toStringAsFixed(1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.center)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ...cells,
      SizedBox(width: 28, child: IconButton(icon: Icon(Icons.remove_circle_outline, size: 13, color: Colors.red.shade300),
        onPressed: () { setState(() { _grades.removeAt(ri); _studentCount = _grades.length; _computeStats(); }); },
        padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24))),
    ]);
  }

  Widget _scoreCell(ColorScheme cs, int ri, int ci, Color bg) {
    return _ScoreCell(initialValue: _grades[ri][ci], bgColor: bg, borderColor: cs.outline.withValues(alpha: 0.15),
      onSubmitted: (v) { setState(() { _grades[ri][ci] = v; _computeStats(); }); });
  }
  Widget _statistics(ColorScheme cs) {
    if (!_hasData) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.analytics_outlined, size: 64, color: cs.onSurface.withValues(alpha: 0.2)),
      const SizedBox(height: 16),
      Text('暂无成绩数据', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
    ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _overviewStats(cs),
      const SizedBox(height: 12),
      _distTable(cs),
      const SizedBox(height: 12),
      _itemTable(cs),
      const SizedBox(height: 12),
      _analysisEditor(cs),
    ]);
  }

  // ── Overview Stats (single row, 9 indicators) ──
  Widget _overviewStats(ColorScheme cs) {
    final s = _stats;
    return Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('考试结果', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          final cellW = w / 9;
          return Wrap(children: [
            _statItem(cs, '考试人数', '${s['studentCount'] ?? 0}', cellW),
            _statItem(cs, '最高分', '${s['max'] ?? 0}', cellW),
            _statItem(cs, '最低分', '${s['min'] ?? 0}', cellW),
            _statItem(cs, '平均分', '${s['avg'] ?? 0}', cellW),
            _statItem(cs, '标准差', '${s['stdDev'] ?? 0}', cellW),
            _statItem(cs, '难度', '${s['difficulty'] ?? 0}', cellW),
            _statItem(cs, '区分度', '${s['examValidity'] ?? 0}', cellW),
            _statItem(cs, '效度', '${s['examValidity'] ?? 0}', cellW),
            _statItem(cs, '信度', '${s['examReliability'] ?? 0}', cellW),
          ]);
        }),
      ],
    )));
  }

  Widget _statItem(ColorScheme cs, String label, String value, double width) {
    return SizedBox(width: width, child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.5))),
        const SizedBox(height: 1),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.primary)),
      ]),
    ));
  }

  // ── Distribution Table (7 ranges, proportional bars growing upward) ──
  Widget _distTable(ColorScheme cs) {
    final dist = (_stats['distribution'] as List<dynamic>?) ?? [0,0,0,0,0,0,0];
    final pct = (_stats['distributionPct'] as List<dynamic>?) ?? [0.0,0.0,0.0,0.0,0.0,0.0,0.0];
    final labels = ['0-40分','40-50分','50-60分','60-70分','70-80分','80-90分','90-100分'];
    final colors = [Colors.red.shade700, Colors.red.shade400, Colors.orange.shade400,
      Colors.amber.shade600, Colors.lightGreen.shade600, Colors.green.shade500, Colors.green.shade700];
    final maxCount = dist.cast<num>().reduce((a, b) => a > b ? a : b).toDouble();
    final maxBarHeight = 80.0;
    final total = dist.fold<int>(0, (a, b) => a + (b as int));
    return Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('考试成绩分布直方图', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 8),
        // Data table
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.2),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08)),
              children: [
                _th(cs, '分数段'),
                _th(cs, '人数'),
                _th(cs, '比例'),
              ],
            ),
            for (var i = 0; i < 7; i++)
              TableRow(
                decoration: BoxDecoration(
                  color: i.isEven ? cs.surfaceContainerHighest.withValues(alpha: 0.3) : null,
                ),
                children: [
                  _td(cs, labels[i]),
                  _td(cs, '${dist[i]}'),
                  _td(cs, '${(pct[i] as num).toStringAsFixed(1)}%'),
                ],
              ),
            TableRow(
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.05)),
              children: [
                _td(cs, '合计', bold: true),
                _td(cs, '$total', bold: true),
                _td(cs, '100.0%', bold: true),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Bar chart
        SizedBox(
          height: maxBarHeight + 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final count = (dist[i] as num).toDouble();
              final barH = maxCount > 0 ? (count / maxCount) * maxBarHeight : 0.0;
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${count.toInt()}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: colors[i])),
                    const SizedBox(height: 2),
                    Container(
                      height: barH.clamp(4.0, maxBarHeight),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: colors[i],
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                      ),
                      child: Center(
                        child: Text('${(pct[i] as num).toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(labels[i], style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.6))),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    )));
  }

  Widget _th(ColorScheme cs, String t) => Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)));
  Widget _td(ColorScheme cs, String t, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.w600 : FontWeight.normal, color: cs.onSurface)));
  Widget _itemTable(ColorScheme cs) {
    final items = (_stats['itemStats'] as List<dynamic>?) ?? [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('各题分析', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 8),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Table(
          columnWidths: const {
            0: FixedColumnWidth(42), 1: FixedColumnWidth(42), 2: FixedColumnWidth(42),
            3: FixedColumnWidth(42), 4: FixedColumnWidth(48), 5: FixedColumnWidth(48),
            6: FixedColumnWidth(52), 7: FixedColumnWidth(52),
          },
          children: [
            TableRow(children: [_th(cs,'题号'),_th(cs,'满分'),_th(cs,'最高'),_th(cs,'最低'),
              _th(cs,'平均'),_th(cs,'标准差'),_th(cs,'难度'),_th(cs,'区分度')]),
            for (final it in items)
              TableRow(children: [
                _td(cs,'${it['label']}', bold: true), _td(cs,'${it['fullMark']}'),
                _td(cs,'${it['max']}'), _td(cs,'${it['min']}'),
                _td(cs,'${it['avg']}'), _td(cs,'${it['stdDev']}'),
                _colorCell(cs, (it['difficulty'] as num).toDouble()),
                _colorCell(cs, (it['discrimination'] as num).toDouble()),
              ]),
          ],
        )),
      ],
    )));
  }

  Widget _colorCell(ColorScheme cs, double v) {
    final c = v >= 0.7 ? Colors.green : v >= 0.4 ? Colors.orange : Colors.red;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
        child: Text(v.toStringAsFixed(2), style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600))));
  }

  Widget _analysisEditor(ColorScheme cs) {
    return Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('试卷分析', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const Spacer(),
          Text('${_analysisCtrl.text.length}字', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _analysisCtrl, maxLines: 8,
          decoration: InputDecoration(hintText: '请输入试卷分析内容...',
            hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.35)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(10)),
          style: const TextStyle(fontSize: 12, height: 1.5)),
      ],
    )));
  }
  // ══════════════════════════════════════════════════
  // PDF Generation — compact 2-page report
  // ══════════════════════════════════════════════════
  pw.Font? _font;

  Future<pw.Font> _loadFont() async {
    if (_font != null) return _font!;
    try { _font = await PdfGoogleFonts.notoSansSCRegular(); } catch (_) {}
    return _font!;
  }

  Future<void> _previewPdf() async {
    final doc = await _genPdf();
    if (doc == null) return;
    await Printing.layoutPdf(onLayout: (f) async => doc.save(), name: '${_nameCtrl.text}试卷分析');
  }

  Future<void> _printPdf() async {
    final doc = await _genPdf();
    if (doc == null) return;
    await Printing.sharePdf(bytes: await doc.save(), filename: '${_nameCtrl.text}试卷分析.pdf');
  }

  Future<pw.Document?> _genPdf() async {
    try {
      final font = await _loadFont();
      final doc = pw.Document();
      final theme = pw.ThemeData.withFont(base: font);
      final cs = _stats;
      final dist = (cs['distribution'] as List<dynamic>?) ?? [0,0,0,0,0,0,0];
      final pct = (cs['distributionPct'] as List<dynamic>?) ?? [0.0,0.0,0.0,0.0,0.0,0.0,0.0];
      final items = (cs['itemStats'] as List<dynamic>?) ?? [];
      final labels = ['0-40分','40-50分','50-60分','60-70分','70-80分','80-90分','90-100分'];

      // ── Page 1: Title + Info + Stats + Chart + Distribution Table ──
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 24),
        theme: theme,
        build: (ctx) => [
          // Title
          pw.Center(child: pw.Text('${_specCtrl.text} ${_nameCtrl.text}考试质量分析表',
            style: pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 8),
          // Info table (compact)
          pw.TableHelper.fromTextArray(
            cellStyle: pw.TextStyle(font: font, fontSize: 9),
            cellHeight: 16,
            columnWidths: {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(2.5), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(2.5)},
            data: [
              ['专业', _specCtrl.text, '班级', _classCtrl.text],
              ['考试科目', _nameCtrl.text, '卷源', _sourceCtrl.text],
              ['考试日期', _timeCtrl.text, '考试方式', _examStyle],
              ['题数', '$_itemCount', '考试人数', '$_studentCount'],
            ],
          ),
          pw.SizedBox(height: 8),
          // 考试结果 section
          pw.Text('考试结果', style: pw.TextStyle(font: font, fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          // Stats row (matching app UI: label on top, value below in blue)
          pw.TableHelper.fromTextArray(
            cellStyle: pw.TextStyle(font: font, fontSize: 7),
            cellHeight: 14,
            columnWidths: {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1), 4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
              6: pw.FlexColumnWidth(1), 7: pw.FlexColumnWidth(1), 8: pw.FlexColumnWidth(1)},
            headerStyle: pw.TextStyle(font: font, fontSize: 6, color: PdfColor.fromInt(0xFF666666)),
            data: [
              ['考试人数', '最高分', '最低分', '平均分', '标准差', '难度', '区分度', '效度', '信度'],
              ['${cs['studentCount']??0}', '${cs['max']??0}', '${cs['min']??0}', '${cs['avg']??0}',
               '${cs['stdDev']??0}', '${cs['difficulty']??0}', '${cs['examValidity']??0}',
               '${cs['examValidity']??0}', '${cs['examReliability']??0}'],
            ],
          ),
          pw.SizedBox(height: 8),
          // Distribution bar chart drawn in PDF
          pw.Text('考试成绩分布直方图', style: pw.TextStyle(font: font, fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          // Data table
          pw.TableHelper.fromTextArray(
            cellStyle: pw.TextStyle(font: font, fontSize: 8),
            cellHeight: 12,
            columnWidths: {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1.2)},
            headerStyle: pw.TextStyle(font: font, fontSize: 7, fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8E8E8)),
            data: [
              ['分数段', '人数', '比例'],
              for (var i = 0; i < 7; i++)
                ['${labels[i]}', '${dist[i]}', '${(pct[i] as num).toStringAsFixed(1)}%'],
            ],
          ),
          pw.SizedBox(height: 6),
          // Bar chart
          _pdfDistChart(font, dist, pct),
          pw.SizedBox(height: 6),
        ],
      ));

      // ── Page 2: Item Analysis + Analysis Text + Signatures ──
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 24),
        theme: theme,
        build: (ctx) => [
          // Item analysis table
          pw.Text('各题分析', style: pw.TextStyle(font: font, fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              cellStyle: pw.TextStyle(font: font, fontSize: 8),
              cellHeight: 12,
              columnWidths: {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1),
                3: pw.FlexColumnWidth(1), 4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
                6: pw.FlexColumnWidth(1), 7: pw.FlexColumnWidth(1)},
              headerStyle: pw.TextStyle(font: font, fontSize: 7, fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8E8E8)),
              data: [
                ['题号','满分','最高','最低','平均','标准差','难度','区分度'],
                for (final it in items)
                  ['${it['label']}','${it['fullMark']}','${it['max']}','${it['min']}',
                   '${it['avg']}','${it['stdDev']}','${it['difficulty']}','${it['discrimination']}'],
              ],
            ),
          pw.SizedBox(height: 12),
          // Analysis text
          if (_analysisCtrl.text.isNotEmpty) ...[
            pw.Text('试卷分析', style: pw.TextStyle(font: font, fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(_analysisCtrl.text, style: pw.TextStyle(font: font, fontSize: 9)),
            pw.SizedBox(height: 12),
          ],
          // Signatures
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            _pdfSignatureCell(font, '任课教师', _teacherSignPath),
            _pdfSignatureCell(font, '系主任', _directorSignPath),
            _pdfSignatureCell(font, '院长', _deanSignPath),
          ]),
          pw.SizedBox(height: 10),
          pw.Divider(height: 1),
          pw.SizedBox(height: 4),
          pw.Text('说明：1、考试方式：闭卷、开卷；卷源：试题库、试卷库、任课教师命题、教研室命题。\n'
            '2、本表一式二份，一份随卷装订，一份交开课院（部）存档（复印有效）。',
            style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
        ],
      ));
      return doc;
    } catch (e, st) {
      swallowDebug(e, tag: 'ExamAnalysisTab.genPdf', stack: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF生成失败: $e')));
      return null;
    }
  }

  // ── PDF signature cell (embed image or text placeholder) ──
  pw.Widget _pdfSignatureCell(pw.Font font, String label, String? signPath) {
    // Try to load signature image
    pw.Image? signImg;
    if (signPath != null && signPath.isNotEmpty) {
      try {
        final file = File(signPath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          signImg = pw.Image(pw.MemoryImage(bytes), height: 28, fit: pw.BoxFit.contain);
        }
      } catch (_) {}
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$label签名：', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColor.fromInt(0xFF666666))),
        pw.SizedBox(height: 2),
        pw.Container(
          width: 120,
          height: 30,
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFCCCCCC), width: 0.5)),
          ),
          child: signImg ?? pw.Center(
            child: pw.Text('___________', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColor.fromInt(0xFFAAAAAA))),
          ),
        ),
      ],
    );
  }

  // ── PDF bar chart (proportional-height bars matching app UI) ──
  pw.Widget _pdfDistChart(pw.Font font, List dist, List pct) {
    final labels = ['0-40分','40-50分','50-60分','60-70分','70-80分','80-90分','90-100分'];
    final barColors = [
      PdfColor.fromInt(0xFFB71C1C), PdfColor.fromInt(0xFFE53935), PdfColor.fromInt(0xFFFF9800),
      PdfColor.fromInt(0xFFFFC107), PdfColor.fromInt(0xFF8BC34A), PdfColor.fromInt(0xFF43A047),
      PdfColor.fromInt(0xFF1B5E20),
    ];
    final maxCount = dist.cast<num>().reduce((a, b) => a > b ? a : b).toDouble();
    const maxBarHeight = 40.0;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final count = (dist[i] as num).toDouble();
        final barH = maxCount > 0 ? (count / maxCount * maxBarHeight).clamp(4.0, maxBarHeight) : 4.0;
        return pw.Expanded(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Center(child: pw.Text('${count.toInt()}',
                style: pw.TextStyle(font: font, fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF333333)))),
              pw.SizedBox(height: 1),
              pw.Container(
                height: barH,
                color: barColors[i],
                child: pw.Center(child: pw.Text('${(pct[i] as num).toStringAsFixed(1)}%',
                  style: pw.TextStyle(font: font, fontSize: 5, color: PdfColors.white, fontWeight: pw.FontWeight.bold))),
              ),
              pw.SizedBox(height: 1),
              pw.Center(child: pw.Text(labels[i],
                style: pw.TextStyle(font: font, fontSize: 5, color: PdfColor.fromInt(0xFF666666)))),
            ],
          ),
        );
      }),
    );
  }
}

class _ScoreCell extends StatefulWidget {
  final double initialValue;
  final Color bgColor;
  final Color borderColor;
  final ValueChanged<double> onSubmitted;
  const _ScoreCell({required this.initialValue, required this.bgColor, required this.borderColor, required this.onSubmitted});
  @override
  State<_ScoreCell> createState() => _ScoreCellState();
}

class _ScoreCellState extends State<_ScoreCell> {
  late TextEditingController _ctrl;
  @override
  void initState() { super.initState(); _ctrl = TextEditingController(text: widget.initialValue.toStringAsFixed(0)); }
  @override
  void didUpdateWidget(_ScoreCell old) { super.didUpdateWidget(old); if (old.initialValue != widget.initialValue) _ctrl.text = widget.initialValue.toStringAsFixed(0); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Container(width: 48, padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 1),
      decoration: BoxDecoration(color: widget.bgColor, border: Border(right: BorderSide(color: widget.borderColor))),
      child: TextField(controller: _ctrl, textAlign: TextAlign.center, keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 11),
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 3, horizontal: 1)),
        onSubmitted: (v) { final p = double.tryParse(v); if (p != null) widget.onSubmitted(p); }),
    );
  }
}
