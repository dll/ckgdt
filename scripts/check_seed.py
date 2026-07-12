import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
conn = sqlite3.connect(r'assets/learning_data.db')
c = conn.cursor()
c.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
tables = [r[0] for r in c.fetchall()]
print('Tables:', tables)
if 'users' in tables:
    c.execute('SELECT COUNT(*) FROM users')
    print('users count:', c.fetchone()[0])
    c.execute('SELECT user_id, real_name, role FROM users LIMIT 10')
    for r in c.fetchall(): print(r)
if 'class_members' in tables:
    c.execute('SELECT COUNT(*) FROM class_members')
    print('class_members count:', c.fetchone()[0])
conn.close()
