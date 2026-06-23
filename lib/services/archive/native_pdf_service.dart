import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Pure Dart Markdown -> PDF renderer for archive generated documents.
///
/// This is the dependency-free fallback when pandoc or LibreOffice is not
/// available on the teacher machine. It intentionally supports the same
/// pragmatic Markdown subset as [NativeDocxService]: headings, paragraphs,
/// simple lists, and pipe tables.
class NativePdfService {
  NativePdfService._();
  static final instance = NativePdfService._();

  pw.Font? _regular;
  pw.Font? _bold;

  Future<Uint8List> markdownToPdf(String markdown) async {
    if (markdown.trim().isEmpty) {
      throw StateError('Markdown 内容为空，无法生成 PDF');
    }
    await _ensureFonts();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
    );
    final widgets = _buildWidgets(markdown);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 38, 42, 42),
        build: (_) => widgets,
      ),
    );
    return doc.save();
  }

  Future<Uint8List> imageFileToPdf(String imagePath) async {
    await _ensureFonts();
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw StateError('图片文件不存在，无法生成 PDF：$imagePath');
    }
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) {
      throw StateError('图片格式不支持或文件损坏：$imagePath');
    }
    final pngBytes = Uint8List.fromList(img.encodePng(decoded));
    final image = pw.MemoryImage(pngBytes);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 38, 42, 42),
        build: (_) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> _ensureFonts() async {
    if (_regular != null && _bold != null) return;
    final data = await rootBundle.load('assets/fonts/simhei.ttf');
    final font = pw.Font.ttf(data);
    _regular = font;
    _bold = font;
  }

  List<pw.Widget> _buildWidgets(String markdown) {
    final widgets = <pw.Widget>[];
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      if (trimmed.startsWith('|')) {
        final tableLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          tableLines.add(lines[i].trim());
          i++;
        }
        final table = _table(tableLines);
        if (table != null) widgets.add(table);
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        widgets.add(_heading(_stripInline(heading.group(2)!), level));
        i++;
        continue;
      }

      final ul = RegExp(r'^[-*]\s+(.*)$').firstMatch(trimmed);
      if (ul != null) {
        widgets.add(_paragraph('• ${_stripInline(ul.group(1)!)}'));
        i++;
        continue;
      }

      final ol = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (ol != null) {
        widgets.add(
          _paragraph('${ol.group(1)}. ${_stripInline(ol.group(2)!)}'),
        );
        i++;
        continue;
      }

      widgets.add(_paragraph(_stripInline(trimmed)));
      i++;
    }
    return widgets;
  }

  pw.Widget _heading(String text, int level) {
    final size = switch (level) {
      1 => 20.0,
      2 => 16.5,
      3 => 14.5,
      _ => 12.5,
    };
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: level == 1 ? 8 : 6, bottom: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _paragraph(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2),
      ),
    );
  }

  pw.Widget? _table(List<String> tableLines) {
    final rows = tableLines
        .where((line) => !RegExp(r'^\|[\s:|-]+\|?$').hasMatch(line))
        .map((line) {
          var cells = line.split('|');
          if (cells.isNotEmpty && cells.first.trim().isEmpty) {
            cells = cells.sublist(1);
          }
          if (cells.isNotEmpty && cells.last.trim().isEmpty) {
            cells = cells.sublist(0, cells.length - 1);
          }
          return cells.map((cell) => _stripInline(cell.trim())).toList();
        })
        .where((row) => row.any((cell) => cell.isNotEmpty))
        .toList();
    if (rows.isEmpty) return null;

    final columnCount = rows.map((row) => row.length).fold<int>(
          0,
          (max, length) => length > max ? length : max,
        );
    final normalized = [
      for (final row in rows)
        [
          ...row,
          for (var i = row.length; i < columnCount; i++) '',
        ],
    ];

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 8),
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.45),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          for (var r = 0; r < normalized.length; r++)
            pw.TableRow(
              decoration: r == 0
                  ? const pw.BoxDecoration(color: PdfColors.grey200)
                  : null,
              children: [
                for (final cell in normalized[r])
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      cell,
                      style: pw.TextStyle(
                        fontSize: columnCount >= 6 ? 7.5 : 9,
                        fontWeight:
                            r == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _stripInline(String value) =>
      value.replaceAll('**', '').replaceAll('`', '').replaceAllMapped(
            RegExp(r'\[([^\]]*)\]\([^)]*\)'),
            (match) => match.group(1) ?? '',
          );
}
