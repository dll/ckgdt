import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db, timeout=5)
conn.execute('PRAGMA busy_timeout=5000')
c = conn.cursor()

# Lab tasks
c.execute('SELECT id, title, chapter, course_id, difficulty, max_score FROM lab_tasks ORDER BY id')
print('=== LAB TASKS ===')
for r in c.fetchall(): print(f'  id={r[0]} title={r[1]} ch={r[2]} course={r[3]} diff={r[4]} score={r[5]}')

c.execute('SELECT COUNT(*) FROM lab_tasks')
print(f'\nTotal lab tasks: {c.fetchone()[0]}')

# Lab submissions
c.execute('SELECT COUNT(*) FROM lab_submissions')
print(f'Total lab submissions: {c.fetchone()[0]}')

# Users
c.execute('SELECT COUNT(*) FROM users')
print(f'Total users: {c.fetchone()[0]}')

c.execute("SELECT user_id, real_name, role FROM users WHERE role='student' ORDER BY user_id")
rows = c.fetchall()
print(f'Students ({len(rows)}):')
for r in rows: print(f'  {r[0]} {r[1]}')

# Class members
c.execute('SELECT COUNT(*) FROM class_members')
print(f'\nClass members: {c.fetchone()[0]}')

conn.close()
