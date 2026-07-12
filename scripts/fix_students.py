import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db, timeout=10)
conn.execute('PRAGMA busy_timeout=10000')
c = conn.cursor()

# Add missing CKGDT students from students.json
students = [
    ('2023211981', '张明远'),
    ('2023211982', '李思涵'),
    ('2023211983', '王浩宇'),
    ('2023211984', '赵雨萱'),
]

for uid, name in students:
    c.execute('SELECT user_id FROM users WHERE user_id = ?', (uid,))
    if c.fetchone() is None:
        c.execute('INSERT INTO users (user_id, real_name, role, is_active) VALUES (?, ?, ?, ?)',
                  (uid, name, 'student', 1))
        print(f'Added student: {uid} {name}')
    else:
        print(f'Student already exists: {uid}')

# Add class membership for all 5 CKGDT students
c.execute('SELECT id FROM classes WHERE name LIKE "%CKGDT%"')
cls = c.fetchone()
if cls:
    class_id = cls[0]
    for uid, name in students + [('2023211985', '测试学生')]:
        c.execute('SELECT user_id FROM class_members WHERE user_id = ? AND class_id = ?', (uid, class_id))
        if c.fetchone() is None:
            c.execute('INSERT OR IGNORE INTO class_members (class_id, user_id, role, joined_at) VALUES (?, ?, ?, ?)',
                      (class_id, uid, 'student', '2026-07-11T00:00:00'))
            print(f'Added {uid} to class {class_id}')
    
    # Update student count
    c.execute('SELECT COUNT(*) FROM class_members WHERE class_id = ? AND role = ?', (class_id, 'student'))
    count = c.fetchone()[0]
    c.execute('UPDATE classes SET student_count = ? WHERE id = ?', (count, class_id))
    print(f'Updated class student count: {count}')
else:
    print('ERROR: No CKGDT class found!')

conn.commit()

# Final verification
c.execute("SELECT user_id, real_name, role FROM users ORDER BY role, user_id")
print('\n=== ALL USERS ===')
for r in c.fetchall(): print(f'  {r[0]} {r[1]} [{r[2]}]')

c.execute("SELECT COUNT(*) FROM lab_tasks")
print(f'\nLab tasks: {c.fetchone()[0]}')

c.execute("SELECT COUNT(*) FROM class_members")
print(f'Class members: {c.fetchone()[0]}')

conn.close()
