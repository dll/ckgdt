/// Shared SQL fragments for screens that should only use current students.
///
/// A student is visible when they are active and either not assigned to a class
/// yet, or assigned to at least one non-archived class. Students that only
/// belong to archived classes are excluded from current teaching statistics.
class ActiveStudentScope {
  const ActiveStudentScope._();

  static String where({
    String alias = 'u',
    bool includeRole = true,
    bool includeActive = true,
  }) {
    final prefix = alias.trim().isEmpty ? '' : '${alias.trim()}.';
    final userId = '${prefix}user_id';
    final parts = <String>[
      if (includeRole) "${prefix}role = 'student'",
      if (includeActive) 'COALESCE(${prefix}is_active, 1) = 1',
      '''
      (
        NOT EXISTS (
          SELECT 1
          FROM class_members cm_scope_any
          WHERE cm_scope_any.user_id = $userId
        )
        OR EXISTS (
          SELECT 1
          FROM class_members cm_scope_active
          JOIN classes c_scope_active
            ON c_scope_active.id = cm_scope_active.class_id
          WHERE cm_scope_active.user_id = $userId
            AND COALESCE(c_scope_active.is_archived, 0) = 0
        )
      )
      ''',
    ];
    return parts.join(' AND ');
  }
}
