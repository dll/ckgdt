import os, sys, sqlite3
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
print(f'Size: {os.path.getsize(db)} bytes')
conn = sqlite3.connect(db)
c = conn.cursor()

c.execute('SELECT role, COUNT(*) FROM users GROUP BY role')
print('=== USERS ===')
for r in c.fetchall(): print(f'  {r[0]}: {r[1]}')

c.execute('SELECT id, name, course_id, is_archived FROM classes')
print('=== CLASSES ===')
for r in c.fetchall(): print(f'  id={r[0]} name={r[1]} course_id={r[2]} archived={r[3]}')

q = "SELECT c.name, c.id, COUNT(*) FROM class_members cm JOIN classes c ON c.id=cm.class_id WHERE cm.role='student' GROUP BY c.id"
c.execute(q)
print('=== CLASS MEMBERS ===')
for r in c.fetchall(): print(f'  {r[0]} (id={r[1]}): {r[2]} students')

c.execute('SELECT id, course_name, class_name FROM achievement_batches')
print('=== ACHIEVEMENT BATCHES ===')
for r in c.fetchall(): print(f'  id={r[0]} course={r[1]} class={r[2]}')

c.execute('SELECT COUNT(*) FROM knowledge_concepts')
print(f'knowledge_concepts: {c.fetchone()[0]}')
c.execute('SELECT COUNT(*) FROM concept_relations')
print(f'concept_relations: {c.fetchone()[0]}')
c.execute('SELECT COUNT(*) FROM graphs')
print(f'graphs: {c.fetchone()[0]}')
c.execute('SELECT COUNT(*) FROM nodes')
print(f'nodes: {c.fetchone()[0]}')
c.execute('SELECT COUNT(*) FROM edges')
print(f'edges: {c.fetchone()[0]}')

c.execute('SELECT user_id, name, role FROM users WHERE role="student" LIMIT 10')
print('=== FIRST 10 STUDENTS ===')
for r in c.fetchall(): print(f'  {r[0]} {r[1]}')

q2 = 'SELECT u.user_id, u.name FROM users u LEFT JOIN class_members cm ON cm.user_id=u.user_id WHERE cm.user_id IS NULL AND u.role="student"'
c.execute(q2)
print('=== STUDENTS WITHOUT CLASS ===')
for r in c.fetchall(): print(f'  {r[0]} {r[1]}')

# Show active student scope
q3 = "SELECT user_id, name FROM users WHERE role='student' AND is_active=1"
c.execute(q3)
print(f'=== ACTIVE STUDENTS: {len(c.fetchall())} ===')

# Show which students are in which classes
q4 = "SELECT u.user_id, u.name, c.name as cls FROM users u JOIN class_members cm ON cm.user_id=u.user_id JOIN classes c ON c.id=cm.class_id WHERE u.role='student' ORDER BY c.name, u.user_id"
c.execute(q4)
print('=== STUDENTS IN CLASSES ===')
for r in c.fetchall(): print(f'  {r[0]} {r[1]} -> {r[2]}')

conn.close()
