import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/models/edge_model.dart';
import 'package:knowledge_graph_app/data/models/graph_model.dart';
import 'package:knowledge_graph_app/data/models/node_model.dart';
import 'package:knowledge_graph_app/data/models/question_model.dart';
import 'package:knowledge_graph_app/data/models/quiz_result_model.dart';
import 'package:knowledge_graph_app/data/models/user_model.dart';

void main() {
  group('GraphModel', () {
    test('fromMap should parse values correctly', () {
      final model = GraphModel.fromMap({
        'id': 'graph_01',
        'title': '移动应用开发知识图谱',
        'graph_type': 'knowledge_system',
        'layout': 'spring',
      });

      expect(model.id, 'graph_01');
      expect(model.title, '移动应用开发知识图谱');
      expect(model.graphType, 'knowledge_system');
      expect(model.layout, 'spring');
    });

    test('toMap should serialize values correctly', () {
      final model = GraphModel(
        id: 'graph_02',
        title: '课程图谱',
        graphType: 'learning_path',
        layout: 'tree',
      );

      expect(model.toMap(), {
        'id': 'graph_02',
        'title': '课程图谱',
        'graph_type': 'learning_path',
        'layout': 'tree',
      });
    });

    test('fromMap should provide safe defaults', () {
      final model = GraphModel.fromMap({});

      expect(model.id, '');
      expect(model.title, '');
      expect(model.graphType, isNull);
      expect(model.layout, isNull);
    });
  });

  group('NodeModel', () {
    test('fromMap should parse node fields correctly', () {
      final model = NodeModel.fromMap({
        'id': 'node_01',
        'graph_id': 'graph_01',
        'title': 'Flutter',
        'content': '跨平台开发框架',
        'node_type': 'knowledge',
        'level': 2,
        'x': 120.5,
        'y': 260.25,
        'color': '#4C6EF5',
        'parent_id': 'root',
        'visible': 1,
      });

      expect(model.id, 'node_01');
      expect(model.graphId, 'graph_01');
      expect(model.title, 'Flutter');
      expect(model.content, '跨平台开发框架');
      expect(model.nodeType, 'knowledge');
      expect(model.level, 2);
      expect(model.x, 120.5);
      expect(model.y, 260.25);
      expect(model.color, '#4C6EF5');
      expect(model.parentId, 'root');
      expect(model.visible, isTrue);
    });

    test('toMap should serialize node fields correctly', () {
      final model = NodeModel(
        id: 'node_02',
        graphId: 'graph_01',
        title: 'Dart',
        content: '编程语言',
        nodeType: 'language',
        level: 1,
        x: 10,
        y: 20,
        color: '#00FF00',
        parentId: 'parent_01',
        visible: false,
      );

      expect(model.toMap(), {
        'id': 'node_02',
        'graph_id': 'graph_01',
        'title': 'Dart',
        'content': '编程语言',
        'node_type': 'language',
        'level': 1,
        'x': 10.0,
        'y': 20.0,
        'color': '#00FF00',
        'parent_id': 'parent_01',
        'visible': 0,
        'metadata_json': null,
      });
    });

    test('fromMap should use defaults when fields are missing', () {
      final model = NodeModel.fromMap({
        'id': 'node_03',
        'graph_id': 'graph_02',
      });

      expect(model.title, '');
      expect(model.level, 0);
      expect(model.x, 0);
      expect(model.y, 0);
      expect(model.visible, isFalse);
    });
  });

  group('EdgeModel', () {
    test('fromMap should parse edge fields correctly', () {
      final model = EdgeModel.fromMap({
        'id': 'edge_01',
        'graph_id': 'graph_01',
        'source_id': 'node_a',
        'target_id': 'node_b',
        'edge_type': 'contains',
        'label': '包含',
        'weight': 2.5,
        'color': '#999999',
        'width': 1.8,
        'style': 'solid',
        'visible': 1,
      });

      expect(model.id, 'edge_01');
      expect(model.graphId, 'graph_01');
      expect(model.sourceId, 'node_a');
      expect(model.targetId, 'node_b');
      expect(model.edgeType, 'contains');
      expect(model.label, '包含');
      expect(model.weight, 2.5);
      expect(model.color, '#999999');
      expect(model.width, 1.8);
      expect(model.style, 'solid');
      expect(model.visible, isTrue);
    });

    test('toMap should serialize edge fields correctly', () {
      final model = EdgeModel(
        id: 'edge_02',
        graphId: 'graph_02',
        sourceId: 'node_1',
        targetId: 'node_2',
        edgeType: 'relation',
        label: '关联',
        weight: 1.2,
        color: '#333333',
        width: 2.0,
        style: 'dashed',
        visible: false,
      );

      expect(model.toMap(), {
        'id': 'edge_02',
        'graph_id': 'graph_02',
        'source_id': 'node_1',
        'target_id': 'node_2',
        'edge_type': 'relation',
        'label': '关联',
        'weight': 1.2,
        'color': '#333333',
        'width': 2.0,
        'style': 'dashed',
        'visible': 0,
      });
    });

    test('fromMap should use numeric defaults', () {
      final model = EdgeModel.fromMap({
        'id': 'edge_03',
        'graph_id': 'graph_03',
        'source_id': 'n1',
        'target_id': 'n2',
      });

      expect(model.weight, 1.0);
      expect(model.width, 1.0);
      expect(model.visible, isFalse);
    });
  });

  group('QuestionModel', () {
    test('fromMap should parse question correctly', () {
      final model = QuestionModel.fromMap({
        'id': 1,
        'source': '第一章',
        'question': 'Flutter 使用的主要语言是什么？',
        'option_a': 'Java',
        'option_b': 'Dart',
        'option_c': 'Kotlin',
        'option_d': 'Swift',
        'answer_index': 1,
      });

      expect(model.id, 1);
      expect(model.source, '第一章');
      expect(model.question, 'Flutter 使用的主要语言是什么？');
      expect(model.optionA, 'Java');
      expect(model.optionB, 'Dart');
      expect(model.optionC, 'Kotlin');
      expect(model.optionD, 'Swift');
      expect(model.answerIndex, 1);
      expect(model.options, ['Java', 'Dart', 'Kotlin', 'Swift']);
      expect(model.correctAnswer, 'Dart');
    });

    test('toMap should serialize question correctly', () {
      final model = QuestionModel(
        source: '第二章',
        question: 'SQLite 属于哪类数据库？',
        optionA: '关系型数据库',
        optionB: '图数据库',
        optionC: '列式数据库',
        optionD: '文档数据库',
        answerIndex: 0,
      );

      expect(model.toMap(), {
        'source': '第二章',
        'question': 'SQLite 属于哪类数据库？',
        'option_a': '关系型数据库',
        'option_b': '图数据库',
        'option_c': '列式数据库',
        'option_d': '文档数据库',
        'answer_index': 0,
      });
    });

    test('correctAnswer should return empty string for invalid answerIndex', () {
      final model = QuestionModel(
        question: '测试题',
        optionA: 'A',
        optionB: 'B',
        optionC: 'C',
        optionD: 'D',
        answerIndex: 9,
      );

      expect(model.correctAnswer, '');
    });
  });

  group('QuizResultModel', () {
    test('fromMap should parse quiz result correctly', () {
      final model = QuizResultModel.fromMap({
        'id': 2,
        'user_id': '2023211985',
        'quiz_timestamp': '2025-03-29T10:00:00',
        'score': 80,
        'num_correct': 8,
        'num_total': 10,
        'chapter': '第三章',
        'quiz_type': 'chapter',
        'completed_at': '2025-03-29T10:10:00',
      });

      expect(model.id, 2);
      expect(model.userId, '2023211985');
      expect(model.quizTimestamp, '2025-03-29T10:00:00');
      expect(model.score, 80);
      expect(model.numCorrect, 8);
      expect(model.numTotal, 10);
      expect(model.chapter, '第三章');
      expect(model.quizType, 'chapter');
      expect(model.completedAt, '2025-03-29T10:10:00');
      expect(model.accuracy, 80);
    });

    test('toMap should serialize quiz result correctly', () {
      final model = QuizResultModel(
        userId: '419116',
        quizTimestamp: '2025-03-29T12:00:00',
        score: 95,
        numCorrect: 19,
        numTotal: 20,
        chapter: '综合测试',
        quizType: 'final',
        completedAt: '2025-03-29T12:15:00',
      );

      expect(model.toMap(), {
        'user_id': '419116',
        'quiz_timestamp': '2025-03-29T12:00:00',
        'score': 95,
        'num_correct': 19,
        'num_total': 20,
        'chapter': '综合测试',
        'quiz_type': 'final',
        'completed_at': '2025-03-29T12:15:00',
      });
    });

    test('accuracy should return 0 when numTotal is 0', () {
      final model = QuizResultModel(
        userId: 'u1',
        score: 0,
        numCorrect: 0,
        numTotal: 0,
      );

      expect(model.accuracy, 0);
    });
  });

  group('UserModel', () {
    test('fromMap should parse user correctly', () {
      final model = UserModel.fromMap({
        'user_id': '419116',
        'real_name': '管理员',
        'machine_code': 'MACHINE-001',
        'role': 'admin',
        'created_at': '2025-03-29T08:00:00',
        'last_login': '2025-03-29T09:00:00',
        'is_active': 1,
      });

      expect(model.userId, '419116');
      expect(model.realName, '管理员');
      expect(model.machineCode, 'MACHINE-001');
      expect(model.role, 'admin');
      expect(model.createdAt, '2025-03-29T08:00:00');
      expect(model.lastLogin, '2025-03-29T09:00:00');
      expect(model.isActive, isTrue);
      expect(model.isAdmin, isTrue);
      expect(model.isTeacher, isFalse);
      expect(model.isStudent, isFalse);
      expect(model.password, '419116');
    });

    test('toMap should serialize user correctly', () {
      final model = UserModel(
        userId: '206004',
        realName: '教师',
        machineCode: 'DEV-02',
        role: 'teacher',
        createdAt: '2025-03-29T07:00:00',
        lastLogin: '2025-03-29T07:30:00',
        isActive: false,
      );

      expect(model.toMap(), {
        'user_id': '206004',
        'real_name': '教师',
        'machine_code': 'DEV-02',
        'role': 'teacher',
        'created_at': '2025-03-29T07:00:00',
        'last_login': '2025-03-29T07:30:00',
        'is_active': 0,
      });
    });

    test('password should return last 6 digits for long userId', () {
      final model = UserModel(userId: '2023211985');

      expect(model.password, '211985');
      expect(model.isStudent, isTrue);
      expect(model.isAdmin, isFalse);
      expect(model.isTeacher, isFalse);
    });

    test('password should return empty string when userId is shorter than 6', () {
      final model = UserModel(userId: '12345');

      expect(model.password, '');
    });
  });
}
