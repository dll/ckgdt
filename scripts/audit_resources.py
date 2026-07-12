import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db)
c = conn.cursor()

# resource_files schema
c.execute("PRAGMA table_info(resource_files)")
cols = [r[1] for r in c.fetchall()]
print('resource_files columns:', cols)

# All resource_files
c.execute('SELECT id, file_name, file_type, chapter, file_path, file_size FROM resource_files ORDER BY file_type, chapter, id')
print('\n=== ALL RESOURCE FILES ===')
for r in c.fetchall():
    print(f'  id={r[0]} name={r[1]} type={r[2]} ch={r[3]} path={r[4][:60] if r[4] else "None"} size={r[5]}')

# Count by type
c.execute('SELECT file_type, COUNT(*) FROM resource_files GROUP BY file_type')
print('\n=== COUNT BY TYPE ===')
for r in c.fetchall(): print(f'  {r[0]}: {r[1]}')

# Duplicate check: same name patterns
c.execute('SELECT file_name, COUNT(*) as cnt FROM resource_files GROUP BY file_name HAVING cnt > 1')
print('\n=== DUPLICATE NAMES ===')
for r in c.fetchall(): print(f'  {r[0]}: {r[1]}')

# Check for patterns like "第一章" vs "第1章"
c.execute("SELECT id, file_name, file_type FROM resource_files WHERE file_name LIKE '%第%章%' ORDER BY file_name")
print('\n=== CHAPTER-RELATED FILES ===')
for r in c.fetchall(): print(f'  id={r[0]} name={r[1]} type={r[2]}')

# Check video script files
c.execute("SELECT id, file_name, file_path FROM resource_files WHERE file_name LIKE '%视频%' OR file_name LIKE '%脚本%' ORDER BY id")
print('\n=== VIDEO/SCRIPT FILES ===')
for r in c.fetchall(): print(f'  id={r[0]} name={r[1]} path={r[2][:80] if r[2] else "None"}')

conn.close()
