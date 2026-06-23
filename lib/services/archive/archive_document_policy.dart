import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/archive_document_model.dart';

/// Shared policy for archive source handling.
///
/// Some archive materials are best preserved as original files (PDF/PPT/official
/// Office forms). Others are imported from source files but immediately parsed
/// into structured Markdown; those should preview, print and archive from the
/// parsed content instead of copying the source spreadsheet.
class ArchiveDocumentPolicy {
  ArchiveDocumentPolicy._();

  static const Set<String> contentFirstDocumentTypes = {
    'teaching_task',
    'course_schedule',
    'survey',
    'syllabus_evaluation',
    'syllabus_review',
    'teaching_schedule',
    'teacher_guide',
    'student_guide',
    'midterm_progress_check',
    'midterm_homework_review',
    'midterm_exam',
    'midterm_check',
    'midterm_analysis',
    'final_archive_catalog',
    'final_syllabus',
    'final_syllabus_evaluation',
    'final_teaching_schedule',
    'final_lesson_plan',
    'final_syllabus_review',
    'final_assessment_review',
    'final_assessment_description',
  };

  static const Set<String> preservedOriginalExtensions = {
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
  };

  static const Set<String> pdfConvertibleOriginalExtensions = {
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
  };

  static const Set<String> textLikeExtensions = {
    '.mhtml',
    '.mht',
    '.html',
    '.htm',
    '.md',
    '.txt',
  };

  static bool shouldKeepOriginalTemplate({
    required String documentType,
    required String extension,
  }) {
    if (contentFirstDocumentTypes.contains(documentType)) return false;
    if (textLikeExtensions.contains(extension)) return false;
    return preservedOriginalExtensions.contains(extension);
  }

  static bool shouldUseOriginalSource(
    String documentType, {
    String? content,
  }) {
    if (contentFirstDocumentTypes.contains(documentType) &&
        !isOriginalReferenceContent(content)) {
      return false;
    }
    return true;
  }

  static bool isOriginalReferenceContent(String? content) {
    final text = content ?? '';
    return text.contains('此资料以原始文件为准') || text.contains('文件类型**：');
  }

  static bool hasArchiveOriginal(String? sourcePath) {
    final file = originalFile(sourcePath);
    return file != null && file.existsSync();
  }

  static bool canPreviewOriginalAsPdf(String? sourcePath) {
    if (sourcePath == null || sourcePath.trim().isEmpty) return false;
    final ext = p.extension(sourcePath).toLowerCase();
    if (!pdfConvertibleOriginalExtensions.contains(ext)) return false;
    return File(sourcePath).existsSync();
  }

  static File? sourceOriginalFile(ArchiveDocument doc) {
    if (!shouldUseOriginalSource(doc.documentType, content: doc.content)) {
      return null;
    }
    return originalFile(doc.filePath);
  }

  static File? originalFile(String? sourcePath) {
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;
    final ext = p.extension(sourcePath).toLowerCase();
    if (!preservedOriginalExtensions.contains(ext)) return null;
    final file = File(sourcePath);
    return file.existsSync() ? file : null;
  }
}
