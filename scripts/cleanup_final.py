import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
db = r'C:\Users\ldl\AppData\Roaming\CKGDTv2.5.15\databases\knowledge_graph.db'
conn = sqlite3.connect(db, timeout=10)
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('PRAGMA busy_timeout=10000')
c = conn.cursor()

# ONLY these user_ids should exist
allowed = {
    '419116',                          # admin
    '203014', '203045', '206004',      # teachers (from students.json)
    '910910',                          # teacher (from roster)
    '2023211981', '2023211982', '2023211983', '2023211984', '2023211985',  # CKGDT students
}

# Delete ALL non-allowed class_members
placeholders = ','.join(['?'] * len(allowed))
c.execute(f'DELETE FROM class_members WHERE user_id NOT IN ({placeholders})', list(allowed))
print(f'Deleted class_members: {c.rowcount}')

# Delete ALL non-allowed users
c.execute(f'DELETE FROM users WHERE user_id NOT IN ({placeholders})', list(allowed))
print(f'Deleted users: {c.rowcount}')

# Delete teacher_ prefix duplicates
c.execute("DELETE FROM users WHERE user_id LIKE 'teacher_%'")
print(f'Deleted teacher_ prefix users: {c.rowcount}')

# Update class student count
c.execute('SELECT id FROM classes')
for (class_id,) in c.fetchall():
    c.execute('SELECT COUNT(*) FROM class_members WHERE class_id = ?', (class_id,))
    count = c.fetchone()[0]
    c.execute('UPDATE classes SET student_count = ? WHERE id = ?', (count, class_id))

conn.commit()

# Final verification
c.execute("SELECT user_id, real_name, role FROM users ORDER BY role, user_id")
rows = c.fetchall()
print(f'\n=== ALL USERS ({len(rows)}) ===')
for r in rows: print(f'  {r[0]} {r[1]} [{r[2]}]')

c.execute("SELECT COUNT(*) FROM class_members")
print(f'\nClass members: {c.fetchone()[0]}')

c.execute("SELECT COUNT(*) FROM lab_tasks")
print(f'Lab tasks: {c.fetchone()[0]}')

conn.close()
