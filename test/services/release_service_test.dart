import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/core/build_info.dart';
import 'package:knowledge_graph_app/services/release_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ReleaseService', () {
    test('windowsReleaseExePath uses current product brand', () {
      final path = ReleaseService.windowsReleaseExePath(
        projectRoot: r'D:\app',
        version: '2.1.0',
      );

      expect(
        path,
        p.join(
          r'D:\app',
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          '${BuildInfo.appBrand}v2.1.0.exe',
        ),
      );
      expect(path, contains('课程图谱与数字孪生'));
      expect(path, isNot(contains('移动图谱与数字孪生')));
    });
  });
}
