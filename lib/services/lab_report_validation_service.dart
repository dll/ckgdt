import 'dart:math';

class LabReportValidationService {
  static const bodyMarker = '--- 报告正文（自动提取）---';
  static const minBodyLength = 80;

  static String? validateFileName({
    required String fileName,
    required String studentId,
    required String realName,
    required String taskTitle,
  }) {
    final trimmedName = fileName.trim();
    final trimmedStudentId = studentId.trim();
    final trimmedRealName = realName.trim();
    final trimmedTaskTitle = taskTitle.trim();

    if (trimmedStudentId.isEmpty || trimmedRealName.isEmpty) {
      return '提交失败：无法获取当前学生学号或姓名，请重新登录';
    }
    if (trimmedTaskTitle.isEmpty) {
      return '提交失败：实验任务名称为空，无法校验报告文件名';
    }
    if (!trimmedName.toLowerCase().endsWith('.pdf')) {
      return '提交失败：实验报告必须为 PDF 文件';
    }

    final baseName = trimmedName.substring(0, trimmedName.length - 4);
    final copyPattern = RegExp(
      r'([\(\（]\d+[\)\）]$)|(new|copy|副本|复制|备份)',
      caseSensitive: false,
    );
    if (copyPattern.hasMatch(baseName)) {
      return '提交失败：文件名不规范，不允许包含(1)、new、copy、副本等复制痕迹\n'
          '正确格式：$trimmedStudentId$trimmedRealName$trimmedTaskTitle.pdf';
    }

    final expected = '$trimmedStudentId$trimmedRealName$trimmedTaskTitle';
    if (baseName != expected) {
      return '提交失败：文件命名不规范\n'
          '当前文件：$trimmedName\n'
          '正确格式：$expected.pdf';
    }
    return null;
  }

  static String? validateExtractedBody({
    required String extractedText,
    required String taskTitle,
    String? requirements,
  }) {
    final body = extractedText.trim();
    if (body.length < minBodyLength) {
      return '提交失败：PDF 正文提取内容过少，无法证明报告内容与实验一致';
    }

    final keywords = _keywords('$taskTitle ${requirements ?? ''}');
    if (keywords.isEmpty) return null;
    final normalizedBody = _normalize(body);
    final hitCount = keywords
        .where((k) => normalizedBody.contains(_normalize(k)))
        .take(3)
        .length;
    final requiredHits = min(2, keywords.length);
    if (hitCount < requiredHits) {
      return '提交失败：PDF 正文与实验任务关键词匹配不足，请提交对应实验报告';
    }
    return null;
  }

  static String buildSubmissionContent({
    required String fileName,
    required String extractedText,
  }) {
    final buffer = StringBuffer()
      ..writeln('PDF实验报告：$fileName')
      ..writeln()
      ..writeln(bodyMarker)
      ..writeln(extractedText.trim());
    return buffer.toString();
  }

  static String? validateStoredSubmission(Map<String, dynamic> submission) {
    final fileNames = (submission['file_names'] as String? ?? '').trim();
    final fileName = fileNames.split(RegExp(r'[,;；，]')).first.trim();
    final userId = (submission['user_id'] as String? ?? '').trim();
    final realName = (submission['real_name'] as String? ?? '').trim();
    final taskTitle = (submission['task_title'] as String? ??
            submission['title'] as String? ??
            '')
        .trim();
    final content = (submission['content'] as String? ?? '').trim();

    if (fileName.isEmpty) return '缺少 PDF 实验报告附件';
    final nameError = validateFileName(
      fileName: fileName,
      studentId: userId,
      realName: realName,
      taskTitle: taskTitle,
    );
    if (nameError != null) return nameError;
    if (!content.contains(bodyMarker) || content.length < minBodyLength + 40) {
      return 'PDF 正文缺失或提取失败';
    }
    return null;
  }

  static List<String> _keywords(String source) {
    final ignored = {
      '实验',
      '报告',
      '任务',
      '要求',
      '完成',
      '提交',
      '设计',
      '实现',
      '软件',
      '工程',
      '移动',
      '应用',
      '开发',
    };
    final matches = RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]{2,}')
        .allMatches(source)
        .map((m) => m.group(0)!)
        .where((w) => !ignored.contains(w) && w.length >= 2)
        .toList();
    return matches.take(8).toList();
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
