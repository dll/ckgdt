import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 原生 Markdown → docx 生成器（无外部依赖，纯 Dart + OOXML）。
///
/// 归档管线优先用 pandoc（可套学校模板样式）；pandoc 未安装时回退到本生成器，
/// 保证没有 pandoc/LibreOffice 的机器也能导出 docx（仅默认排版，无模板样式）。
///
/// 支持的 Markdown 子集：# 标题(1-3 级)、普通段落、- / * 无序列表、
/// 1. 有序列表、| 表格 |、**粗体**（行内简单处理）。
class NativeDocxService {
  NativeDocxService._();
  static final instance = NativeDocxService._();

  Uint8List markdownToDocx(String markdown) {
    final body = StringBuffer();
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // 表格：连续以 | 开头的行
      if (trimmed.startsWith('|')) {
        final tableLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          tableLines.add(lines[i].trim());
          i++;
        }
        _writeTable(body, tableLines);
        continue;
      }

      // 标题
      final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (h != null) {
        final level = h.group(1)!.length;
        _writePara(body, h.group(2)!, styleHeading: level);
        i++;
        continue;
      }

      // 列表
      final ul = RegExp(r'^[-*]\s+(.*)$').firstMatch(trimmed);
      if (ul != null) {
        _writePara(body, '• ${ul.group(1)!}');
        i++;
        continue;
      }
      final ol = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (ol != null) {
        _writePara(body, '${ol.group(1)}. ${ol.group(2)!}');
        i++;
        continue;
      }

      // 普通段落
      _writePara(body, trimmed);
      i++;
    }

    return _zipDocx(_documentXml(body.toString()));
  }

  void _writePara(StringBuffer b, String text, {int? styleHeading}) {
    final clean = _stripInline(text);
    final bold = styleHeading != null;
    final size = switch (styleHeading) { 1 => 36, 2 => 30, 3 => 26, _ => 21 };
    b.write('<w:p>');
    b.write('<w:pPr>');
    if (styleHeading != null) b.write('<w:spacing w:before="240" w:after="120"/>');
    b.write('</w:pPr>');
    b.write('<w:r><w:rPr>');
    if (bold) b.write('<w:b/>');
    b.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/>');
    b.write('</w:rPr><w:t xml:space="preserve">${_esc(clean)}</w:t></w:r>');
    b.write('</w:p>');
  }

  void _writeTable(StringBuffer b, List<String> tableLines) {
    // 过滤分隔行 |---|---|
    final rows = tableLines
        .where((l) => !RegExp(r'^\|[\s:|-]+\|?$').hasMatch(l))
        .map((l) {
      var cells = l.split('|');
      if (cells.isNotEmpty && cells.first.trim().isEmpty) cells = cells.sublist(1);
      if (cells.isNotEmpty && cells.last.trim().isEmpty) cells = cells.sublist(0, cells.length - 1);
      return cells.map((c) => _stripInline(c.trim())).toList();
    }).toList();
    if (rows.isEmpty) return;

    b.write('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="0" w:type="auto"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '</w:tblBorders></w:tblPr>');
    for (int r = 0; r < rows.length; r++) {
      b.write('<w:tr>');
      for (final cell in rows[r]) {
        b.write('<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr><w:p><w:r><w:rPr>');
        if (r == 0) b.write('<w:b/>');
        b.write('<w:sz w:val="20"/></w:rPr><w:t xml:space="preserve">${_esc(cell)}</w:t></w:r></w:p></w:tc>');
      }
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
    b.write('<w:p/>'); // 表后空段，避免连续表粘连
  }

  /// 去掉行内 markdown 标记（**、*、`、[]() 简单处理）。
  String _stripInline(String s) => s
      .replaceAll('**', '')
      .replaceAll('`', '')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _documentXml(String body) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
      '</w:sectPr></w:body></w:document>';

  Uint8List _zipDocx(String documentXml) {
    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>');
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>');
    add('word/_rels/document.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>');
    add('word/document.xml', documentXml);

    final zipped = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(zipped);
  }
}
