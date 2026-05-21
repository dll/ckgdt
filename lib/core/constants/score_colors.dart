import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

/// 评分阈值（4 档）
const int kScoreExcellent = 90;
const int kScoreGood = 80;
const int kScorePass = 60;

/// Material 评分配色（4 档：优/良/及格/不及格）
Color scoreColorMaterial(int? s) {
  if (s == null) return Colors.grey;
  if (s >= kScoreExcellent) return Colors.green;
  if (s >= kScoreGood) return Colors.blue;
  if (s >= kScorePass) return Colors.orange;
  return Colors.red;
}

/// PDF 评分配色（4 档：优/良/及格/不及格）
PdfColor scoreColorPdf(int? s) {
  if (s == null) return PdfColors.grey400;
  if (s >= kScoreExcellent) return PdfColors.green700;
  if (s >= kScoreGood) return PdfColors.blue700;
  if (s >= kScorePass) return PdfColors.orange700;
  return PdfColors.red700;
}
