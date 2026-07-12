import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db)
c = conn.cursor()
c.execute('SELECT course_id, COUNT(*) FROM questions GROUP BY course_id')
print('=== QUESTIONS BY COURSE_ID ===')
for r in c.fetchall(): print(f'  course_id={r[0]}: {r[1]}')
c.execute("SELECT COUNT(*) FROM questions WHERE course_id IS NULL")
print(f'NULL course_id: {c.fetchone()[0]}')
conn.close()
