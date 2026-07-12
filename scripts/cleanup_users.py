import sqlite3, sys, time
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'

# Try with timeout and WAL mode
conn = sqlite3.connect(db, timeout=10)
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('PRAGMA busy_timeout=5000')
c = conn.cursor()

# Allowed IDs: students.json (5 students + admin + 3 teachers) + teacher_ prefix IDs
allowed = {
    '419116', '203014', '203045', '206004',
    '2023211981', '2023211982', '2023211983', '2023211984', '2023211985',
    'teacher_203014', 'teacher_203045', 'teacher_206004',
}

c.execute('SELECT COUNT(*) FROM users')
before_users = c.fetchone()[0]
c.execute('SELECT COUNT(*) FROM class_members')
before_cm = c.fetchone()[0]

# Delete class_members not in allowed
placeholders = ','.join(['?'] * len(allowed))
c.execute(f'DELETE FROM class_members WHERE user_id NOT IN ({placeholders})', list(allowed))
deleted_cm = c.rowcount

# Delete users not in allowed
c.execute(f'DELETE FROM users WHERE user_id NOT IN ({placeholders})', list(allowed))
deleted_users = c.rowcount

# Update class student count
c.execute('SELECT id FROM classes')
for (class_id,) in c.fetchall():
    c.execute('SELECT COUNT(*) FROM class_members WHERE class_id = ?', (class_id,))
    count = c.fetchone()[0]
    c.execute('UPDATE classes SET student_count = ? WHERE id = ?', (count, class_id))

conn.commit()

c.execute('SELECT COUNT(*) FROM users')
after_users = c.fetchone()[0]
c.execute('SELECT COUNT(*) FROM class_members')
after_cm = c.fetchone()[0]

print(f'Before: {before_users} users, {before_cm} class_members')
print(f'After: {after_users} users, {after_cm} class_members')
print(f'Deleted: {deleted_users} users, {deleted_cm} class_members')

# Show remaining students
c.execute("SELECT user_id, real_name, role FROM users WHERE role = 'student' ORDER BY user_id")
rows = c.fetchall()
print(f'\n=== Remaining students ({len(rows)}) ===')
for r in rows: print(f'  {r[0]} {r[1]}')

c.execute("SELECT user_id, real_name, role FROM users WHERE role = 'teacher' ORDER BY user_id")
rows = c.fetchall()
print(f'\n=== Remaining teachers ({len(rows)}) ===')
for r in rows: print(f'  {r[0]} {r[1]}')

c.execute("SELECT user_id, real_name, role FROM users WHERE role = 'admin' ORDER BY user_id")
rows = c.fetchall()
print(f'\n=== Remaining admins ({len(rows)}) ===')
for r in rows: print(f'  {r[0]} {r[1]}')

conn.close()
