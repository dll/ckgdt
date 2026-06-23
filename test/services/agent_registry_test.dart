import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/agent/agent_registry.dart';

void main() {
  test('AgentRegistry registers the current 18 runtime agents', () {
    final registry = AgentRegistry.instance..initialize();
    final ids = registry.allConfigs.map((config) => config.id).toList();

    expect(ids, hasLength(18));
    expect(
      ids,
      equals([
        'voice',
        'graph',
        'quiz',
        'repo',
        'assessment',
        'lab',
        'works',
        'achievement',
        'courseware',
        'tutor',
        'doc_converter',
        'mobile_expert',
        'ethics',
        'safety',
        'archive',
        'grading',
        'digital_twin',
        'assistant',
      ]),
    );
  });
}
