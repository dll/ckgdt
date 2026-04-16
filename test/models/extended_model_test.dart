import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/models/material_model.dart';
import 'package:knowledge_graph_app/data/models/ai_config_model.dart';
import 'package:knowledge_graph_app/data/models/puml_file_model.dart';
import 'package:knowledge_graph_app/data/models/learning_path_model.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // MaterialModel
  // ═══════════════════════════════════════════════════════════════════════════

  group('MaterialModel', () {
    test('fromMap should parse all fields correctly', () {
      final model = MaterialModel.fromMap({
        'id': 1,
        'title': 'Flutter 入门课件',
        'type': 'pdf',
        'file_path': '/docs/flutter_intro.pdf',
        'content': '课件内容',
        'chapter': '第1章',
        'created_at': '2025-06-01T10:00:00',
        'size': 2048,
      });

      expect(model.id, 1);
      expect(model.title, 'Flutter 入门课件');
      expect(model.type, 'pdf');
      expect(model.filePath, '/docs/flutter_intro.pdf');
      expect(model.content, '课件内容');
      expect(model.chapter, '第1章');
      expect(model.createdAt, '2025-06-01T10:00:00');
      expect(model.size, 2048);
    });

    test('toMap should serialize fields correctly', () {
      final model = MaterialModel(
        id: 5,
        title: '测试素材',
        type: 'slide',
        filePath: '/slides/test.pdf',
        content: 'slide content',
        chapter: '第3章',
        createdAt: '2025-07-01T08:00:00',
        size: 1024,
      );

      final map = model.toMap();
      expect(map['id'], 5);
      expect(map['title'], '测试素材');
      expect(map['type'], 'slide');
      expect(map['file_path'], '/slides/test.pdf');
      expect(map['content'], 'slide content');
      expect(map['chapter'], '第3章');
      expect(map['size'], 1024);
    });

    test('toMap without id should omit id field', () {
      final model = MaterialModel(
        title: '无ID素材',
        type: 'script',
      );

      final map = model.toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map['title'], '无ID素材');
      expect(map['type'], 'script');
    });

    test('fromMap should provide safe defaults for missing fields', () {
      final model = MaterialModel.fromMap({});

      expect(model.id, isNull);
      expect(model.title, '');
      expect(model.type, 'script');
      expect(model.filePath, isNull);
      expect(model.content, isNull);
      expect(model.chapter, isNull);
      expect(model.createdAt, isNull);
      expect(model.size, 0);
    });

    test('typeLabel should return correct Chinese labels', () {
      expect(
        MaterialModel(title: '', type: 'pdf').typeLabel,
        'PDF课件',
      );
      expect(
        MaterialModel(title: '', type: 'slide').typeLabel,
        '幻灯片',
      );
      expect(
        MaterialModel(title: '', type: 'script').typeLabel,
        '视频脚本',
      );
      expect(
        MaterialModel(title: '', type: 'uml').typeLabel,
        'UML图',
      );
      expect(
        MaterialModel(title: '', type: 'video_script').typeLabel,
        '教学脚本',
      );
      expect(
        MaterialModel(title: '', type: 'unknown_type').typeLabel,
        '素材',
      );
    });

    test('size should default to 0', () {
      final model = MaterialModel(title: 'test', type: 'pdf');
      expect(model.size, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AiConfigModel
  // ═══════════════════════════════════════════════════════════════════════════

  group('AiConfigModel', () {
    test('fromMap should parse all fields correctly', () {
      final model = AiConfigModel.fromMap({
        'provider': 'zhipu',
        'api_key': 'sk-test-key-123',
        'model': 'glm-4',
        'base_url': 'https://custom.api.url',
        'updated_at': '2025-06-01T12:00:00',
      });

      expect(model.provider, 'zhipu');
      expect(model.apiKey, 'sk-test-key-123');
      expect(model.model, 'glm-4');
      expect(model.baseUrl, 'https://custom.api.url');
      expect(model.updatedAt, '2025-06-01T12:00:00');
    });

    test('toMap should serialize with fixed id=1', () {
      final model = AiConfigModel(
        provider: 'deepseek',
        apiKey: 'sk-abc',
        model: 'deepseek-chat',
        baseUrl: 'https://api.deepseek.com',
        updatedAt: '2025-06-01T12:00:00',
      );

      final map = model.toMap();
      expect(map['id'], 1);
      expect(map['provider'], 'deepseek');
      expect(map['api_key'], 'sk-abc');
      expect(map['model'], 'deepseek-chat');
      expect(map['base_url'], 'https://api.deepseek.com');
    });

    test('fromMap should provide safe defaults', () {
      final model = AiConfigModel.fromMap({});

      expect(model.provider, 'deepseek');
      expect(model.apiKey, isNull);
      expect(model.model, 'deepseek-chat');
      expect(model.baseUrl, isNull);
      expect(model.updatedAt, isNull);
    });

    test('default constructor should use deepseek defaults', () {
      const model = AiConfigModel();

      expect(model.provider, 'deepseek');
      expect(model.model, 'deepseek-chat');
      expect(model.apiKey, isNull);
      expect(model.baseUrl, isNull);
    });

    test('effectiveBaseUrl should return custom URL when set', () {
      final model = AiConfigModel(
        provider: 'deepseek',
        baseUrl: 'https://my-proxy.com',
      );

      expect(model.effectiveBaseUrl, 'https://my-proxy.com');
    });

    test('effectiveBaseUrl should return deepseek default when baseUrl is null', () {
      const model = AiConfigModel(provider: 'deepseek');

      expect(model.effectiveBaseUrl, AiConfigModel.deepseekDefaultUrl);
    });

    test('effectiveBaseUrl should return zhipu default for zhipu provider', () {
      const model = AiConfigModel(provider: 'zhipu');

      expect(model.effectiveBaseUrl, AiConfigModel.zhipuDefaultUrl);
    });

    test('effectiveBaseUrl should return default when baseUrl is empty string', () {
      const model = AiConfigModel(provider: 'zhipu', baseUrl: '');

      expect(model.effectiveBaseUrl, AiConfigModel.zhipuDefaultUrl);
    });

    test('providerLabel should return Chinese label', () {
      expect(
        const AiConfigModel(provider: 'deepseek').providerLabel,
        'DeepSeek',
      );
      expect(
        const AiConfigModel(provider: 'zhipu').providerLabel,
        '智谱清言 GLM',
      );
      expect(
        const AiConfigModel(provider: 'other').providerLabel,
        'other',
      );
    });

    test('copyWith should create modified copy', () {
      const original = AiConfigModel(
        provider: 'deepseek',
        apiKey: 'old-key',
        model: 'deepseek-chat',
      );

      final copied = original.copyWith(
        provider: 'zhipu',
        apiKey: 'new-key',
        model: 'glm-4',
      );

      expect(copied.provider, 'zhipu');
      expect(copied.apiKey, 'new-key');
      expect(copied.model, 'glm-4');
      // updatedAt should be auto-set
      expect(copied.updatedAt, isNotNull);
    });

    test('copyWith should preserve unchanged fields', () {
      const original = AiConfigModel(
        provider: 'deepseek',
        apiKey: 'keep-this',
        model: 'deepseek-chat',
      );

      final copied = original.copyWith(model: 'deepseek-coder');

      expect(copied.provider, 'deepseek');
      expect(copied.apiKey, 'keep-this');
      expect(copied.model, 'deepseek-coder');
    });

    test('default URLs should be valid', () {
      expect(
        AiConfigModel.deepseekDefaultUrl,
        startsWith('https://'),
      );
      expect(
        AiConfigModel.zhipuDefaultUrl,
        startsWith('https://'),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PumlFileModel
  // ═══════════════════════════════════════════════════════════════════════════

  group('PumlFileModel', () {
    test('fromMap should parse all fields correctly', () {
      final model = PumlFileModel.fromMap({
        'id': 3,
        'title': '系统架构图',
        'content': '@startuml\nclass A\n@enduml',
        'file_path': '/uml/arch.puml',
        'rendered_url': 'https://kroki.io/image123',
        'diagram_type': 'class',
        'chapter': '第2章',
        'created_at': '2025-05-01T09:00:00',
        'updated_at': '2025-05-02T10:00:00',
      });

      expect(model.id, 3);
      expect(model.title, '系统架构图');
      expect(model.content, '@startuml\nclass A\n@enduml');
      expect(model.filePath, '/uml/arch.puml');
      expect(model.renderedUrl, 'https://kroki.io/image123');
      expect(model.diagramType, 'class');
      expect(model.chapter, '第2章');
      expect(model.createdAt, '2025-05-01T09:00:00');
      expect(model.updatedAt, '2025-05-02T10:00:00');
    });

    test('toMap should serialize correctly with id', () {
      final model = PumlFileModel(
        id: 7,
        title: '顺序图',
        content: '@startuml\nA -> B\n@enduml',
        diagramType: 'sequence',
        createdAt: '2025-06-01T08:00:00',
        updatedAt: '2025-06-01T09:00:00',
      );

      final map = model.toMap();
      expect(map['id'], 7);
      expect(map['title'], '顺序图');
      expect(map['content'], '@startuml\nA -> B\n@enduml');
      expect(map['diagram_type'], 'sequence');
    });

    test('toMap without id should omit id field', () {
      final model = PumlFileModel(
        title: '无ID图',
        content: '@startuml\n@enduml',
      );

      final map = model.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('fromMap should provide safe defaults', () {
      final model = PumlFileModel.fromMap({});

      expect(model.id, isNull);
      expect(model.title, '');
      expect(model.content, '');
      expect(model.filePath, isNull);
      expect(model.renderedUrl, isNull);
      expect(model.diagramType, 'class');
      expect(model.chapter, isNull);
    });

    test('typeLabel should return correct Chinese labels', () {
      expect(
        PumlFileModel(title: '', content: '', diagramType: 'class').typeLabel,
        '类图',
      );
      expect(
        PumlFileModel(title: '', content: '', diagramType: 'sequence').typeLabel,
        '顺序图',
      );
      expect(
        PumlFileModel(title: '', content: '', diagramType: 'activity').typeLabel,
        '活动图',
      );
      expect(
        PumlFileModel(title: '', content: '', diagramType: 'component').typeLabel,
        '组件图',
      );
      expect(
        PumlFileModel(title: '', content: '', diagramType: 'usecase').typeLabel,
        '用例图',
      );
      expect(
        PumlFileModel(title: '', content: '', diagramType: 'flowchart').typeLabel,
        '流程图',
      );
      expect(
        PumlFileModel(title: '', content: '', diagramType: 'custom').typeLabel,
        'custom',
      );
    });

    test('copyWith should create modified copy', () {
      final original = PumlFileModel(
        id: 1,
        title: '原始标题',
        content: '原始内容',
        diagramType: 'class',
        chapter: '第1章',
        createdAt: '2025-01-01T00:00:00',
      );

      final copied = original.copyWith(
        title: '新标题',
        content: '新内容',
        diagramType: 'sequence',
      );

      expect(copied.id, 1); // preserved
      expect(copied.title, '新标题');
      expect(copied.content, '新内容');
      expect(copied.diagramType, 'sequence');
      expect(copied.chapter, '第1章'); // preserved
      expect(copied.createdAt, '2025-01-01T00:00:00'); // preserved
      expect(copied.updatedAt, isNotNull); // auto-set
    });

    test('copyWith should preserve fields not specified', () {
      final original = PumlFileModel(
        id: 2,
        title: '保持不变',
        content: '保持不变内容',
        renderedUrl: 'https://example.com/img.png',
        diagramType: 'activity',
      );

      final copied = original.copyWith(chapter: '第5章');

      expect(copied.title, '保持不变');
      expect(copied.content, '保持不变内容');
      expect(copied.renderedUrl, 'https://example.com/img.png');
      expect(copied.diagramType, 'activity');
      expect(copied.chapter, '第5章');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LearningPathModel
  // ═══════════════════════════════════════════════════════════════════════════

  group('LearningPathModel', () {
    test('fromMap should parse all fields correctly', () {
      final model = LearningPathModel.fromMap({
        'id': 1,
        'user_id': '2023211985',
        'title': 'Flutter 学习路径',
        'description': '从入门到进阶',
        'node_ids': ['node_1', 'node_2', 'node_3'],
        'progress': 0.6,
        'status': 'active',
        'created_at': '2025-05-01T08:00:00',
        'updated_at': '2025-05-15T10:00:00',
      });

      expect(model.id, 1);
      expect(model.userId, '2023211985');
      expect(model.title, 'Flutter 学习路径');
      expect(model.description, '从入门到进阶');
      expect(model.nodeIds, ['node_1', 'node_2', 'node_3']);
      expect(model.progress, 0.6);
      expect(model.status, 'active');
      expect(model.createdAt, isNotNull);
      expect(model.updatedAt, isNotNull);
    });

    test('toMap should serialize correctly', () {
      final model = LearningPathModel(
        id: 2,
        userId: '419116',
        title: '跨平台开发',
        description: '学习路径描述',
        nodeIds: ['a', 'b', 'c'],
        progress: 0.5,
        status: 'completed',
        createdAt: DateTime(2025, 6, 1),
        updatedAt: DateTime(2025, 6, 15),
      );

      final map = model.toMap();
      expect(map['id'], 2);
      expect(map['user_id'], '419116');
      expect(map['title'], '跨平台开发');
      expect(map['description'], '学习路径描述');
      expect(map['node_ids'], 'a,b,c'); // joined with comma
      expect(map['progress'], 0.5);
      expect(map['status'], 'completed');
    });

    test('toMap without id should omit id field', () {
      final model = LearningPathModel(
        userId: 'u1',
        title: 'test',
      );

      final map = model.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('fromMap should provide safe defaults', () {
      final model = LearningPathModel.fromMap({});

      expect(model.id, isNull);
      expect(model.userId, '');
      expect(model.title, '');
      expect(model.description, isNull);
      expect(model.nodeIds, isEmpty);
      expect(model.progress, 0.0);
      expect(model.status, 'active');
      expect(model.createdAt, isNull);
      expect(model.updatedAt, isNull);
    });

    test('nodeIds should serialize as comma-separated string in toMap', () {
      final model = LearningPathModel(
        userId: 'u1',
        title: 'test',
        nodeIds: ['node_a', 'node_b'],
      );

      expect(model.toMap()['node_ids'], 'node_a,node_b');
    });

    test('empty nodeIds should serialize as empty string', () {
      final model = LearningPathModel(
        userId: 'u1',
        title: 'test',
        nodeIds: [],
      );

      expect(model.toMap()['node_ids'], '');
    });

    test('copyWith should create modified copy', () {
      final original = LearningPathModel(
        id: 1,
        userId: 'u1',
        title: '原始路径',
        progress: 0.3,
        status: 'active',
      );

      final copied = original.copyWith(
        title: '新路径',
        progress: 0.8,
        status: 'completed',
      );

      expect(copied.id, 1); // preserved
      expect(copied.userId, 'u1'); // preserved
      expect(copied.title, '新路径');
      expect(copied.progress, 0.8);
      expect(copied.status, 'completed');
    });

    test('copyWith should preserve unchanged fields', () {
      final original = LearningPathModel(
        id: 5,
        userId: 'u2',
        title: '保持',
        description: '不变描述',
        nodeIds: ['x', 'y'],
        progress: 0.5,
      );

      final copied = original.copyWith(progress: 0.9);

      expect(copied.userId, 'u2');
      expect(copied.title, '保持');
      expect(copied.description, '不变描述');
      expect(copied.nodeIds, ['x', 'y']);
      expect(copied.progress, 0.9);
    });

    test('progress should handle integer input from map', () {
      final model = LearningPathModel.fromMap({
        'user_id': 'u1',
        'title': 'test',
        'progress': 1, // integer instead of double
      });

      expect(model.progress, 1.0);
      expect(model.progress, isA<double>());
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PathNodeModel
  // ═══════════════════════════════════════════════════════════════════════════

  group('PathNodeModel', () {
    test('fromMap should parse all fields correctly', () {
      final model = PathNodeModel.fromMap({
        'id': 10,
        'path_id': 1,
        'node_id': 'node_flutter',
        'node_title': 'Flutter 基础',
        'sequence': 3,
        'is_completed': 1,
        'completed_at': '2025-06-10T14:00:00',
      });

      expect(model.id, 10);
      expect(model.pathId, 1);
      expect(model.nodeId, 'node_flutter');
      expect(model.nodeTitle, 'Flutter 基础');
      expect(model.sequence, 3);
      expect(model.isCompleted, isTrue);
      expect(model.completedAt, isNotNull);
    });

    test('toMap should serialize correctly', () {
      final model = PathNodeModel(
        id: 5,
        pathId: 2,
        nodeId: 'node_dart',
        nodeTitle: 'Dart 语言',
        sequence: 1,
        isCompleted: true,
        completedAt: DateTime(2025, 6, 1, 12, 0),
      );

      final map = model.toMap();
      expect(map['id'], 5);
      expect(map['path_id'], 2);
      expect(map['node_id'], 'node_dart');
      expect(map['node_title'], 'Dart 语言');
      expect(map['sequence'], 1);
      expect(map['is_completed'], 1);
      expect(map['completed_at'], isNotNull);
    });

    test('toMap without id should omit id field', () {
      final model = PathNodeModel(
        pathId: 1,
        nodeId: 'n1',
        sequence: 0,
      );

      final map = model.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('isCompleted should be false when is_completed is 0', () {
      final model = PathNodeModel.fromMap({
        'path_id': 1,
        'node_id': 'n1',
        'sequence': 0,
        'is_completed': 0,
      });

      expect(model.isCompleted, isFalse);
    });

    test('isCompleted should default to false', () {
      final model = PathNodeModel(
        pathId: 1,
        nodeId: 'n1',
        sequence: 0,
      );

      expect(model.isCompleted, isFalse);
    });

    test('completedAt should be null when not completed', () {
      final model = PathNodeModel.fromMap({
        'path_id': 1,
        'node_id': 'n1',
        'sequence': 0,
      });

      expect(model.completedAt, isNull);
    });

    test('toMap should serialize isCompleted as 0 for false', () {
      final model = PathNodeModel(
        pathId: 1,
        nodeId: 'n1',
        sequence: 0,
        isCompleted: false,
      );

      expect(model.toMap()['is_completed'], 0);
    });

    test('toMap should serialize isCompleted as 1 for true', () {
      final model = PathNodeModel(
        pathId: 1,
        nodeId: 'n1',
        sequence: 0,
        isCompleted: true,
      );

      expect(model.toMap()['is_completed'], 1);
    });

    test('sequence should default to 0', () {
      final model = PathNodeModel.fromMap({
        'path_id': 1,
        'node_id': 'n1',
      });

      expect(model.sequence, 0);
    });

    test('nodeId should default to empty string', () {
      final model = PathNodeModel.fromMap({
        'path_id': 1,
      });

      expect(model.nodeId, '');
    });
  });
}
