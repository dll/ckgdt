import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/core/constants/role_guard.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // RoleGuard — 权限守卫纯逻辑测试
  // ═══════════════════════════════════════════════════════════════════════════

  group('RoleGuard - canManageQuestions', () {
    test('admin can manage questions', () {
      expect(RoleGuard.canManageQuestions('admin'), isTrue);
    });

    test('teacher can manage questions', () {
      expect(RoleGuard.canManageQuestions('teacher'), isTrue);
    });

    test('student cannot manage questions', () {
      expect(RoleGuard.canManageQuestions('student'), isFalse);
    });

    test('unknown role cannot manage questions', () {
      expect(RoleGuard.canManageQuestions('guest'), isFalse);
    });
  });

  group('RoleGuard - canManageStudents', () {
    test('admin can manage students', () {
      expect(RoleGuard.canManageStudents('admin'), isTrue);
    });

    test('teacher cannot manage students', () {
      expect(RoleGuard.canManageStudents('teacher'), isFalse);
    });

    test('student cannot manage students', () {
      expect(RoleGuard.canManageStudents('student'), isFalse);
    });
  });

  group('RoleGuard - canScoreWorks', () {
    test('admin can score works', () {
      expect(RoleGuard.canScoreWorks('admin'), isTrue);
    });

    test('teacher can score works', () {
      expect(RoleGuard.canScoreWorks('teacher'), isTrue);
    });

    test('student cannot score works', () {
      expect(RoleGuard.canScoreWorks('student'), isFalse);
    });
  });

  group('RoleGuard - canManageAssessment', () {
    test('admin can manage assessment', () {
      expect(RoleGuard.canManageAssessment('admin'), isTrue);
    });

    test('teacher can manage assessment', () {
      expect(RoleGuard.canManageAssessment('teacher'), isTrue);
    });

    test('student cannot manage assessment', () {
      expect(RoleGuard.canManageAssessment('student'), isFalse);
    });
  });

  group('RoleGuard - canImportData', () {
    test('admin can import data', () {
      expect(RoleGuard.canImportData('admin'), isTrue);
    });

    test('teacher can import data', () {
      expect(RoleGuard.canImportData('teacher'), isTrue);
    });

    test('student cannot import data', () {
      expect(RoleGuard.canImportData('student'), isFalse);
    });
  });

  group('RoleGuard - canConfigGitee', () {
    test('admin can config gitee', () {
      expect(RoleGuard.canConfigGitee('admin'), isTrue);
    });

    test('teacher can config gitee', () {
      expect(RoleGuard.canConfigGitee('teacher'), isTrue);
    });

    test('student cannot config gitee', () {
      expect(RoleGuard.canConfigGitee('student'), isFalse);
    });
  });

  group('RoleGuard - canViewAllRepos', () {
    test('admin can view all repos', () {
      expect(RoleGuard.canViewAllRepos('admin'), isTrue);
    });

    test('teacher can view all repos', () {
      expect(RoleGuard.canViewAllRepos('teacher'), isTrue);
    });

    test('student cannot view all repos', () {
      expect(RoleGuard.canViewAllRepos('student'), isFalse);
    });
  });

  group('RoleGuard - isTeacherOrAdmin', () {
    test('admin is teacher or admin', () {
      expect(RoleGuard.isTeacherOrAdmin('admin'), isTrue);
    });

    test('teacher is teacher or admin', () {
      expect(RoleGuard.isTeacherOrAdmin('teacher'), isTrue);
    });

    test('student is not teacher or admin', () {
      expect(RoleGuard.isTeacherOrAdmin('student'), isFalse);
    });

    test('empty string is not teacher or admin', () {
      expect(RoleGuard.isTeacherOrAdmin(''), isFalse);
    });
  });

  group('RoleGuard - canAccessSubPage', () {
    test('student cannot access teacher archive or workspace pages', () {
      expect(RoleGuard.canAccessSubPage('student', 'archive'), isFalse);
      expect(
        RoleGuard.canAccessSubPage('student', 'teacher_workspace'),
        isFalse,
      );
      expect(RoleGuard.canAccessSubPage('student', 'class_token'), isFalse);
      expect(RoleGuard.canAccessSubPage('student', 'agent_calls'), isFalse);
      expect(RoleGuard.canAccessSubPage('student', 'data_import'), isFalse);
      expect(RoleGuard.canAccessSubPage('student', 'grade_entry'), isFalse);
      expect(
        RoleGuard.canAccessSubPage('student', 'notification_manage'),
        isFalse,
      );
    });

    test('teacher can access teacher sub pages but not admin-only pages', () {
      expect(RoleGuard.canAccessSubPage('teacher', 'archive'), isTrue);
      expect(
        RoleGuard.canAccessSubPage('teacher', 'teacher_workspace'),
        isTrue,
      );
      expect(RoleGuard.canAccessSubPage('teacher', 'lab_manage'), isTrue);
      expect(RoleGuard.canAccessSubPage('teacher', 'grade_entry'), isTrue);
      expect(
        RoleGuard.canAccessSubPage('teacher', 'notification_manage'),
        isTrue,
      );
      expect(
        RoleGuard.canAccessSubPage('teacher', 'teacher_application_manage'),
        isFalse,
      );
      expect(RoleGuard.canAccessSubPage('teacher', 'repo_analytics'), isFalse);
      expect(RoleGuard.canAccessSubPage('teacher', 'release_center'), isFalse);
    });

    test('admin can access admin-only sub pages', () {
      expect(
        RoleGuard.canAccessSubPage('admin', 'teacher_application_manage'),
        isTrue,
      );
      expect(RoleGuard.canAccessSubPage('admin', 'student_manage'), isTrue);
      expect(RoleGuard.canAccessSubPage('admin', 'teacher_manage'), isTrue);
      expect(RoleGuard.canAccessSubPage('admin', 'class_manage'), isTrue);
      expect(RoleGuard.canAccessSubPage('admin', 'repo_analytics'), isTrue);
      expect(RoleGuard.canAccessSubPage('admin', 'release_center'), isTrue);
    });

    test('admin can access teaching management workflow sub pages', () {
      const routes = [
        'question_manage',
        'data_import',
        'data_export',
        'survey_manage',
        'teaching_manage',
        'lab_manage',
        'grade_entry',
        'notification_manage',
      ];
      for (final route in routes) {
        expect(
          RoleGuard.canAccessSubPage('admin', route),
          isTrue,
          reason: 'admin should access $route',
        );
      }
    });

    test('public learning sub pages remain available to students', () {
      expect(RoleGuard.canAccessSubPage('student', 'quiz'), isTrue);
      expect(RoleGuard.canAccessSubPage('student', 'video'), isTrue);
      expect(RoleGuard.canAccessSubPage('student', 'student_token'), isTrue);
    });
  });

  group('RoleGuard - canAccessInnerPage', () {
    test('student cannot request teacher-only inner pages', () {
      expect(RoleGuard.canAccessInnerPage('student', 'achievement'), isFalse);
      expect(RoleGuard.canAccessInnerPage('student', 'archive'), isFalse);
      expect(RoleGuard.canAccessInnerPage('student', 'evaluation'), isFalse);
    });

    test('student can request student workflow inner pages', () {
      expect(RoleGuard.canAccessInnerPage('student', 'learning'), isTrue);
      expect(RoleGuard.canAccessInnerPage('student', 'lab'), isTrue);
      expect(RoleGuard.canAccessInnerPage('student', 'assessment'), isTrue);
      expect(RoleGuard.canAccessInnerPage('student', 'works'), isTrue);
    });

    test('teacher can request teacher-only inner pages', () {
      expect(RoleGuard.canAccessInnerPage('teacher', 'achievement'), isTrue);
      expect(RoleGuard.canAccessInnerPage('teacher', 'archive'), isTrue);
      expect(RoleGuard.canAccessInnerPage('teacher', 'evaluation'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 权限矩阵交叉验证
  // ═══════════════════════════════════════════════════════════════════════════

  group('RoleGuard - Permission Matrix', () {
    test('admin should have all permissions', () {
      const role = 'admin';
      expect(RoleGuard.canManageQuestions(role), isTrue);
      expect(RoleGuard.canManageStudents(role), isTrue);
      expect(RoleGuard.canScoreWorks(role), isTrue);
      expect(RoleGuard.canManageAssessment(role), isTrue);
      expect(RoleGuard.canImportData(role), isTrue);
      expect(RoleGuard.canConfigGitee(role), isTrue);
      expect(RoleGuard.canViewAllRepos(role), isTrue);
      expect(RoleGuard.isTeacherOrAdmin(role), isTrue);
    });

    test('teacher should have teaching permissions but not admin-only', () {
      const role = 'teacher';
      expect(RoleGuard.canManageQuestions(role), isTrue);
      expect(RoleGuard.canManageStudents(role), isFalse); // admin only
      expect(RoleGuard.canScoreWorks(role), isTrue);
      expect(RoleGuard.canManageAssessment(role), isTrue);
      expect(RoleGuard.canImportData(role), isTrue);
      expect(RoleGuard.canConfigGitee(role), isTrue);
      expect(RoleGuard.canViewAllRepos(role), isTrue);
      expect(RoleGuard.isTeacherOrAdmin(role), isTrue);
    });

    test('student should have no management permissions', () {
      const role = 'student';
      expect(RoleGuard.canManageQuestions(role), isFalse);
      expect(RoleGuard.canManageStudents(role), isFalse);
      expect(RoleGuard.canScoreWorks(role), isFalse);
      expect(RoleGuard.canManageAssessment(role), isFalse);
      expect(RoleGuard.canImportData(role), isFalse);
      expect(RoleGuard.canConfigGitee(role), isFalse);
      expect(RoleGuard.canViewAllRepos(role), isFalse);
      expect(RoleGuard.isTeacherOrAdmin(role), isFalse);
    });
  });
}
