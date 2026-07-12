import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db, timeout=10)
conn.execute('PRAGMA busy_timeout=10000')
c = conn.cursor()

# Get all tables
c.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
tables = [r[0] for r in c.fetchall()]

print(f'Total tables: {len(tables)}')
for t in tables:
    c.execute(f'SELECT COUNT(*) FROM [{t}]')
    count = c.fetchone()[0]
    if count > 0:
        # Check if table has course_id column
        c.execute(f'PRAGMA table_info([{t}])')
        cols = [col[1] for col in c.fetchall()]
        has_course = 'course_id' in cols
        has_user = 'user_id' in cols
        extra = ''
        if has_course:
            c.execute(f'SELECT DISTINCT course_id FROM [{t}] WHERE course_id IS NOT NULL LIMIT 5')
            courses = [r[0] for r in c.fetchall()]
            extra += f' courses={courses}'
        if has_user:
            c.execute(f'SELECT COUNT(DISTINCT user_id) FROM [{t}]')
            users = c.fetchone()[0]
            extra += f' distinct_users={users}'
        print(f'  {t}: {count} rows{extra}')
    else:
        print(f'  {t}: (empty)')

conn.close()
