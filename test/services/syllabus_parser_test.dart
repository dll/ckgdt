// ignore_for_file: prefer_const_declarations

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/syllabus_parser.dart';

void main() {
  group('SyllabusParser - DOCX解析', () {
    late SyllabusParser parser;
    final docxPath = 'data/教学大纲-c203140750-软件工程-2023.docx';

    setUp(() {
      parser = SyllabusParser();
    });

    test('解析软件工程教学大纲 DOCX', () async {
      final file = File(docxPath);
      expect(await file.exists(), isTrue, reason: 'DOCX 文件必须存在');

      final bytes = await file.readAsBytes();
      final data = parser.parseBytes(bytes);

      // === 课程基本信息 ===
      expect(data.courseName, contains('软件工程'));
      expect(data.courseCode, isNotEmpty);
      expect(data.lectureHours, greaterThan(0));
      expect(data.labHours, greaterThan(0));
      expect(data.credits, greaterThan(0));

      // === 课程目标 ===
      expect(data.objectives, isNotEmpty);
      for (final obj in data.objectives) {
        expect(obj.id, isNotEmpty);
        expect(obj.description, isNotEmpty);
      }

      // === 考核结构 ===
      expect(data.assessment.dailyWeight, greaterThan(0));
      expect(data.assessment.labWeight, greaterThan(0));
      expect(data.assessment.examWeight, greaterThan(0));
      final total = data.assessment.dailyWeight +
          data.assessment.labWeight +
          data.assessment.examWeight;
      expect(total, closeTo(1.0, 0.01));

      // === 教材 ===
      expect(data.textbooks, isNotEmpty);
      for (final tb in data.textbooks) {
        expect(tb.trim(), isNotEmpty);
      }

      // === 章节（≥9 章） ===
      expect(data.chapters.length, greaterThanOrEqualTo(9));
      for (var i = 0; i < data.chapters.length; i++) {
        final ch = data.chapters[i];
        expect(ch.index, greaterThan(0));
        expect(ch.title, isNotEmpty);
        // 每章应有教学重点
        expect(ch.keyPoints, isNotEmpty,
            reason: '第${ch.index}章「${ch.title}」缺少教学重点');
        // 每章应有教学目标
        expect(ch.teachingObjectives, isNotEmpty,
            reason: '第${ch.index}章「${ch.title}」缺少教学目标');
      }

      // === 实验（≥6 个） ===
      expect(data.labs.length, greaterThanOrEqualTo(6));
      for (final lab in data.labs) {
        expect(lab.title, isNotEmpty);
        expect(lab.content, isNotEmpty,
            reason: '实验「${lab.title}」缺少内容');
      }
    });

    test('章节内容完整性验证', () async {
      final bytes = await File(docxPath).readAsBytes();
      final data = parser.parseBytes(bytes);

      // 验证第一章详细内容
      final ch1 = data.chapters.firstWhere((c) => c.index == 1);
      expect(ch1.title, isNotEmpty);
      // 教学内容应包含关键术语
      expect(ch1.content, isNotEmpty);
      // 教学重点不应为空
      expect(ch1.keyPoints, isNotEmpty);
      // 教学目标不应为空
      expect(ch1.teachingObjectives, isNotEmpty);
      // 教学难点可能为空，但最好有内容
      // (部分章节可能没有单独列出难点，所以不强制断言)
    });

    test('实验内容完整性验证', () async {
      final bytes = await File(docxPath).readAsBytes();
      final data = parser.parseBytes(bytes);

      // 验证每个实验都有主要字段
      for (final lab in data.labs) {
        // 实验室设备要求
        expect(lab.equipment, isNotEmpty,
            reason: '实验「${lab.title}」缺少设备要求');
        // 实验目的
        expect(lab.objectives, isNotEmpty,
            reason: '实验「${lab.title}」缺少实验目的');
      }
    });

    test('章节顺序正确', () async {
      final bytes = await File(docxPath).readAsBytes();
      final data = parser.parseBytes(bytes);

      // 章节 index 应连续且递增
      for (var i = 0; i < data.chapters.length; i++) {
        expect(data.chapters[i].index, i + 1,
            reason: '章节索引不连续：位置 $i 应为 ${i + 1}');
      }
    });

    test('invalid bytes throws', () {
      expect(
        () => parser.parseBytes([0, 1, 2, 3]),
        throwsA(isA<Exception>()),
      );
    });

    test('空 PDF 投掷', () {
      expect(
        () => parser.parseBytes([]),
        throwsA(isA<Exception>()),
      );
    });
  });
}
