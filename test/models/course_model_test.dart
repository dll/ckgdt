import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/models/course_model.dart';

void main() {
  group('CourseModel', () {
    test('chapters use real JSON encoding for cross-course titles', () {
      final model = CourseModel(
        id: 'software_engineering',
        name: '软件工程',
        chapters: const [
          '第1章 软件过程、模型与方法',
          '第2章 需求分析："用户故事"与用例',
          '第3章 UML, 设计模式与架构',
        ],
        createdAt: '2026-06-14T00:00:00',
      );

      final map = model.toMap();
      final restored = CourseModel.fromMap(map);

      expect(restored.name, '软件工程');
      expect(restored.chapters, model.chapters);
    });
  });
}
