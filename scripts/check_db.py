import sys, sqlite3, os
sys.stdout.reconfigure(encoding='utf-8')

appdata = os.environ.get('APPDATA', '')
base = os.path.join(appdata, 'com.example')
for root, dirs, files in os.walk(base):
    for f in files:
        if f.endswith('.db'):
            p = os.path.join(root, f)
            print(f'DB: {p} ({os.path.getsize(p)} bytes)')
            try:
                conn = sqlite3.connect(p)
                c = conn.cursor()
                c.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
                tables = [r[0] for r in c.fetchall()]
                print(f'  Tables ({len(tables)}): {tables}')
                if 'users' in tables:
                    c.execute('SELECT role, COUNT(*) FROM users GROUP BY role')
                    for r in c.fetchall(): print(f'  users by role: {r}')
                if 'classes' in tables:
                    c.execute('SELECT id, name, course_id, is_archived FROM classes')
                    for r in c.fetchall(): print(f'  class: {r}')
                if 'class_members' in tables:
                    c.execute('SELECT c.name, COUNT(*) FROM class_members cm JOIN classes c ON c.id=cm.class_id WHERE cm.role="student" GROUP BY c.name')
                    for r in c.fetchall(): print(f'  members in {r[0]}: {r[1]}')
                if 'achievement_batches' in tables:
                    c.execute('SELECT id, course_name, class_name FROM achievement_batches')
                    for r in c.fetchall(): print(f'  batch: {r}')
                if 'knowledge_concepts' in tables:
                    c.execute('SELECT COUNT(*) FROM knowledge_concepts')
                    print(f'  knowledge_concepts: {c.fetchone()[0]}')
                if 'concept_relations' in tables:
                    c.execute('SELECT COUNT(*) FROM concept_relations')
                    print(f'  concept_relations: {c.fetchone()[0]}')
                if 'graphs' in tables:
                    c.execute('SELECT COUNT(*) FROM graphs')
                    print(f'  graphs: {c.fetchone()[0]}')
                if 'nodes' in tables:
                    c.execute('SELECT COUNT(*) FROM nodes')
                    print(f'  nodes: {c.fetchone()[0]}')
                if 'edges' in tables:
                    c.execute('SELECT COUNT(*) FROM edges')
                    print(f'  edges: {c.fetchone()[0]}')
                conn.close()
            except Exception as e:
                print(f'  Error: {e}')
