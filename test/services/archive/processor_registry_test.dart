import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/document_processor.dart';
import 'package:knowledge_graph_app/services/archive/processor_registry.dart';
import 'package:knowledge_graph_app/data/models/archive_document_model.dart';

class _FakeAiDraft extends DocumentProcessor {
  @override
  String get docType => 'syllabus';
  @override
  String get docLabel => '教学大纲';
  @override
  ProcessorKind get kind => ProcessorKind.aiDraft;
  @override
  Future<String> generate({
    required String period,
    required String courseType,
    Map<String, dynamic>? extra,
  }) async => '# 大纲\n模拟 AI 起草';
  @override
  Future<String> review(ArchiveDocument doc) async => '审核结果';
  @override
  Future<Uint8List> toDocx(ArchiveDocument doc) async => Uint8List(0);
  @override
  Future<Uint8List> toPdf(ArchiveDocument doc) async => Uint8List(0);
}

class _FakeAudit extends DocumentProcessor {
  @override
  String get docType => 'syllabus_review';
  @override
  String get docLabel => '大纲合理性审核表';
  @override
  ProcessorKind get kind => ProcessorKind.aiAudit;
  @override
  bool get supportsGenerate => false;
  @override
  bool get supportsReview => false;
  @override
  Future<String> generate({
    required String period,
    required String courseType,
    Map<String, dynamic>? extra,
  }) async => throw UnsupportedError('audit 不生成新文档');
  @override
  Future<String> review(ArchiveDocument doc) async =>
      throw UnsupportedError('audit 自身不需要再审');
  @override
  Future<Uint8List> toDocx(ArchiveDocument doc) async => Uint8List(0);
  @override
  Future<Uint8List> toPdf(ArchiveDocument doc) async => Uint8List(0);
}

void main() {
  group('ProcessorRegistry', () {
    setUp(() => ProcessorRegistry.instance.resetForTest());

    test('register and find', () {
      final r = ProcessorRegistry.instance;
      r.register(_FakeAiDraft());
      expect(r.find('syllabus'), isA<_FakeAiDraft>());
      expect(r.find('not_registered'), isNull);
    });

    test('register override warns and replaces', () {
      final r = ProcessorRegistry.instance;
      r.register(_FakeAiDraft());
      final draft = r.find('syllabus');
      r.register(_FakeAiDraft());
      // 覆盖后仍能 find
      expect(r.find('syllabus'), isNot(same(draft)));
      expect(r.find('syllabus'), isA<_FakeAiDraft>());
    });

    test('registeredDocTypes sorted', () {
      final r = ProcessorRegistry.instance;
      r.register(_FakeAiDraft()); // syllabus
      r.register(_FakeAudit()); // syllabus_review
      expect(r.registeredDocTypes, equals(['syllabus', 'syllabus_review']));
    });

    test('kindStats counts by kind', () {
      final r = ProcessorRegistry.instance;
      r.register(_FakeAiDraft());
      r.register(_FakeAudit());
      expect(r.kindStats[ProcessorKind.aiDraft], equals(1));
      expect(r.kindStats[ProcessorKind.aiAudit], equals(1));
      expect(r.kindStats[ProcessorKind.systemImport], isNull);
    });

    test('aiAudit processor reports correct supports flags', () {
      final audit = _FakeAudit();
      expect(audit.supportsGenerate, isFalse);
      expect(audit.supportsReview, isFalse);
      expect(audit.supportsPrint, isTrue);
      expect(audit.supportsArchive, isTrue);
    });

    test('aiDraft processor reports correct supports flags', () {
      final draft = _FakeAiDraft();
      expect(draft.supportsGenerate, isTrue);
      expect(draft.supportsReview, isTrue);
      expect(draft.supportsPrint, isTrue);
      expect(draft.supportsArchive, isTrue);
    });

    test('ProcessorKind labels are CN', () {
      expect(ProcessorKind.systemImport.label, equals('教务导入'));
      expect(ProcessorKind.aiDraft.label, equals('AI 起草'));
      expect(ProcessorKind.aiAudit.label, equals('AI 审核'));
    });
  });
}
