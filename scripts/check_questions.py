import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db)
c = conn.cursor()

# questions schema
c.execute("PRAGMA table_info(questions)")
cols = [r[1] for r in c.fetchall()]
print('questions columns:', cols)

# Count by source
c.execute('SELECT source, COUNT(*) FROM questions GROUP BY source')
print('\n=== COUNT BY SOURCE ===')
for r in c.fetchall(): print(f'  {r[0]}: {r[1]}')

# Sample questions
c.execute('SELECT id, question, source, chapter FROM questions LIMIT 5')
print('\n=== SAMPLE QUESTIONS ===')
for r in c.fetchall():
    q = r[1][:80] if r[1] else 'None'
    print(f'  id={r[0]} src={r[2]} ch={r[3]} q={q}')

# Check if any question mentions 移动
c.execute("SELECT COUNT(*) FROM questions WHERE question LIKE '%移动%' OR source LIKE '%移动%'")
print(f'\n移动-related questions: {c.fetchone()[0]}')

c.execute("SELECT COUNT(*) FROM questions WHERE question LIKE '%知识图谱%' OR question LIKE '%数字孪生%'")
print(f'CKGDT-related questions: {c.fetchone()[0]}')

conn.close()
