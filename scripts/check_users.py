import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db)
c = conn.cursor()

# Check classes schema
c.execute('PRAGMA table_info(classes)')
print('=== classes columns ===')
for r in c.fetchall(): print(f'  {r[1]} ({r[2]})')

c.execute('SELECT * FROM classes LIMIT 5')
cols = [d[0] for d in c.description]
print(f'\n=== classes data: {cols}')
for r in c.fetchall(): print(f'  {r}')

# Students
c.execute("SELECT user_id, real_name FROM users WHERE user_id LIKE '202321%' ORDER BY user_id")
print('\n=== All 202321 students ===')
for r in c.fetchall(): print(f'  {r[0]} {r[1]}')

# student_ prefix
c.execute("SELECT user_id, real_name FROM users WHERE user_id LIKE 'student_%' LIMIT 5")
print('\n=== Student_ prefix ===')
for r in c.fetchall(): print(f'  {r[0]} {r[1]}')

# Other users that are neither CKGDT nor teacher
c.execute("SELECT user_id, real_name, role FROM users WHERE user_id NOT LIKE '2023211%' AND user_id NOT LIKE '20202%' AND user_id NOT LIKE 'teacher_%' AND user_id NOT LIKE 'student_%' AND user_id != '419116'")
print('\n=== Other users ===')
for r in c.fetchall(): print(f'  {r[0]} {r[1]} {r[2]}')

# Total
c.execute('SELECT COUNT(*) FROM users')
print(f'\nTotal users: {c.fetchone()[0]}')
c.execute("SELECT COUNT(*) FROM users WHERE user_id LIKE '2023211%'")
print(f'CKGDT students (2023211xxx): {c.fetchone()[0]}')
c.execute("SELECT COUNT(*) FROM users WHERE user_id LIKE '202321%' AND user_id NOT LIKE '2023211%'")
print(f'Other 202321xxx students: {c.fetchone()[0]}')
c.execute("SELECT COUNT(*) FROM users WHERE user_id LIKE '20202%'")
print(f'20202xxx students: {c.fetchone()[0]}')

conn.close()
