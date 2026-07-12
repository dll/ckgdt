import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db, timeout=10)
conn.execute('PRAGMA busy_timeout=10000')
c = conn.cursor()

# 1. Delete OLD MAD lab tasks (course=mad)
c.execute("DELETE FROM lab_tasks WHERE course_id = 'mad'")
print(f'Deleted MAD lab tasks: {c.rowcount}')

# 2. Delete first set of CKGDT generic tasks (id 23-28) — keep better set (id 37-44)
c.execute("DELETE FROM lab_tasks WHERE id BETWEEN 23 AND 28")
print(f'Deleted generic CKGDT tasks: {c.rowcount}')

# 3. Delete orphaned submissions for deleted tasks
c.execute("DELETE FROM lab_submissions WHERE task_id NOT IN (SELECT id FROM lab_tasks)")
print(f'Deleted orphaned submissions: {c.rowcount}')

# 4. Clean up legacy users — only keep CKGDT allowed IDs
allowed = {
    '419116', '203014', '203045', '206004', '910910',
    '2023211981', '2023211982', '2023211983', '2023211984', '2023211985',
    'teacher_203014', 'teacher_203045', 'teacher_206004',
}
placeholders = ','.join(['?'] * len(allowed))

c.execute(f'DELETE FROM class_members WHERE user_id NOT IN ({placeholders})', list(allowed))
print(f'Deleted legacy class_members: {c.rowcount}')

c.execute(f'DELETE FROM users WHERE user_id NOT IN ({placeholders})', list(allowed))
print(f'Deleted legacy users: {c.rowcount}')

# 5. Update class student count
c.execute('SELECT id FROM classes')
for (class_id,) in c.fetchall():
    c.execute('SELECT COUNT(*) FROM class_members WHERE class_id = ?', (class_id,))
    count = c.fetchone()[0]
    c.execute('UPDATE classes SET student_count = ? WHERE id = ?', (count, class_id))

conn.commit()

# Verify
c.execute("SELECT id, title, course_id FROM lab_tasks ORDER BY id")
print(f'\n=== REMAINING LAB TASKS ({c.rowcount}) ===')
for r in c.fetchall(): print(f'  id={r[0]} {r[1]} [{r[2]}]')

c.execute("SELECT COUNT(*) FROM users")
print(f'\nTotal users: {c.fetchone()[0]}')
c.execute("SELECT user_id, real_name, role FROM users ORDER BY role, user_id")
print('=== ALL REMAINING USERS ===')
for r in c.fetchall(): print(f'  {r[0]} {r[1]} [{r[2]}]')

c.execute("SELECT COUNT(*) FROM class_members")
print(f'\nClass members: {c.fetchone()[0]}')

c.execute("SELECT COUNT(*) FROM lab_submissions")
print(f'Lab submissions: {c.fetchone()[0]}')

conn.close()
