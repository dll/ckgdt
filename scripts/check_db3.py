import os, sys, sqlite3
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db)
c = conn.cursor()

# User columns
c.execute("PRAGMA table_info(users)")
cols = [r[1] for r in c.fetchall()]
print('users columns:', cols)

# Users by role with name field
name_col = 'display_name' if 'display_name' in cols else 'user_name' if 'user_name' in cols else 'user_id'
print(f'Using name column: {name_col}')

q = f"SELECT user_id, {name_col}, role, is_active FROM users ORDER BY role, user_id"
c.execute(q)
print('=== ALL USERS ===')
for r in c.fetchall(): print(f'  {r[0]} | {r[1]} | {r[2]} | active={r[3]}')

# Class members detail
q2 = "SELECT cm.user_id, u.user_id, c.name FROM class_members cm JOIN classes c ON c.id=cm.class_id LEFT JOIN users u ON u.user_id=cm.user_id ORDER BY c.name, cm.user_id"
c.execute(q2)
print(f'\n=== CLASS MEMBERS (total: {len(c.fetchall())} rows) ===')
c.execute(q2)
for r in c.fetchall(): print(f'  user={r[0]} in class={r[2]}')

# Check which class软开23 vs 软件231/232
q3 = "SELECT DISTINCT c.name FROM classes c JOIN class_members cm ON cm.class_id=c.id"
c.execute(q3)
print('\n=== DISTINCT CLASS NAMES ===')
for r in c.fetchall(): print(f'  {r[0]}')

# Students NOT in class_members but in users
q4 = "SELECT u.user_id FROM users u WHERE u.role='student' AND u.user_id NOT IN (SELECT cm.user_id FROM class_members cm)"
c.execute(q4)
orphans = c.fetchall()
print(f'\n=== ORPHAN STUDENTS (no class): {len(orphans)} ===')
for r in orphans[:5]: print(f'  {r[0]}')

# concept_relations
c.execute('SELECT COUNT(*) FROM concept_relations')
print(f'\nconcept_relations: {c.fetchone()[0]}')

# Check course_id on concept_relations
try:
    c.execute('SELECT course_id, COUNT(*) FROM concept_relations GROUP BY course_id')
    print('concept_relations by course:')
    for r in c.fetchall(): print(f'  {r[0]}: {r[1]}')
except: pass

conn.close()
