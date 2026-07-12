import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db)
c = conn.cursor()

c.execute('SELECT course_id, COUNT(*) FROM questions GROUP BY course_id')
print('=== QUESTIONS BY COURSE_ID ===')
for r in c.fetchall(): print(f'  course_id={r[0]}: {r[1]}')

c.execute('SELECT DISTINCT source FROM questions LIMIT 10')
print('\n=== DISTINCT SOURCES ===')
for r in c.fetchall(): print(f'  {r[0]}')

c.execute('SELECT question, source FROM questions LIMIT 5')
print('\n=== SAMPLE QUESTIONS ===')
for r in c.fetchall(): print(f'  [{r[1]}] {r[0][:60]}')

c.execute('SELECT id, title, graph_id FROM knowledge_concepts LIMIT 10')
print('\n=== KNOWLEDGE CONCEPTS ===')
for r in c.fetchall(): print(f'  id={r[0]} title={r[1]} graph={r[2]}')

c.execute('SELECT COUNT(*) FROM concept_relations')
print(f'\n=== CONCEPT_RELATIONS: {c.fetchone()[0]} rows ===')

c.execute('SELECT COUNT(*) FROM knowledge_concepts')
print(f'=== KNOWLEDGE_CONCEPTS: {c.fetchone()[0]} rows ===')

conn.close()
