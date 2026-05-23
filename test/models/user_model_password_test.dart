import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/data/models/user_model.dart';

/// 默认密码规则是 CLAUDE.md 明确声明的不可变契约：
/// `userId.substring(userId.length - 6)`。
///
/// 已有 88 个学生数据依赖此规则，破坏会导致全班无法登录。
void main() {
  group('UserModel.defaultPassword', () {
    UserModel mk(String userId) => UserModel(
          userId: userId,
          realName: 'test',
          role: 'student',
          isActive: true,
        );

    test('正常 10 位学号取后 6 位', () {
      expect(mk('2023210586').defaultPassword, '210586');
    });

    test('管理员 6 位 userId 取自身（边界）', () {
      expect(mk('419116').defaultPassword, '419116');
    });

    test('短于 6 位的 userId 取自身（防 substring 越界）', () {
      expect(mk('abc').defaultPassword, 'abc');
      expect(mk('').defaultPassword, '');
    });

    test('恰好 6 位 userId 取全部', () {
      expect(mk('123456').defaultPassword, '123456');
    });
  });

  group('UserModel.hasCustomPassword', () {
    test('未设 passwordHash 时为 false', () {
      final u = UserModel(
          userId: '2023210586', realName: 't', role: 'student', isActive: true);
      expect(u.hasCustomPassword, isFalse);
    });

    test('设了 passwordHash 时为 true', () {
      final u = UserModel(
          userId: '2023210586',
          realName: 't',
          role: 'student',
          isActive: true,
          passwordHash: 'hash123');
      expect(u.hasCustomPassword, isTrue);
    });
  });
}
