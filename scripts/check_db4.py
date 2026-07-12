import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db)
c = conn.cursor()

c.execute('SELECT id, concept_name, concept_type, chapter, course_id FROM knowledge_concepts ORDER BY id')
print('=== KNOWLEDGE CONCEPTS ===')
for r in c.fetchall():
    print(f'  id={r[0]} name={r[1]} type={r[2]} ch={r[3]} course={r[4]}')

c.execute('SELECT COUNT(*) FROM concept_relations')
print(f'\nconcept_relations: {c.fetchone()[0]}')

c.execute('SELECT id, graph_id, title, graph_type FROM graphs ORDER BY id')
print('\n=== GRAPHS ===')
for r in c.fetchall():
    print(f'  id={r[0]} gid={r[1]} title={r[2]} type={r[3]}')

c.execute('SELECT id, graph_id, title, node_type FROM nodes LIMIT 20')
print('\n=== FIRST 20 NODES ===')
for r in c.fetchall():
    print(f'  id={r[0]} gid={r[1]} title={r[2]} type={r[3]}')

conn.close()
