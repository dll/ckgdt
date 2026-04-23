import json
from collections import defaultdict
from pathlib import Path
import openpyxl

EXCEL = Path(r'D:\FlutterProjects\knowledge_graph_app\data\项目\软件23选88实验分组-20260403.xlsx')
JPATH = Path(r'D:\FlutterProjects\knowledge_graph_app\assets\student_repo_map.json')

wb = openpyxl.load_workbook(EXCEL, read_only=True, data_only=True)
ws = wb.active
rows = []
for row in ws.iter_rows(min_row=2, max_row=87, min_col=1, max_col=6):
    vals = [str(row[i].value).strip() if row[i].value else '' for i in range(6)]
    rows.append(dict(row_n=row[0].row, xh=vals[0], xm=vals[1], ck=vals[2], qm=vals[3], fz=vals[4], sy=vals[5]))
wb.close()
print(f'Loaded {len(rows)} rows')
issues = []
print()
print('=' * 80)
print('1. Repo names (Column C)')
print('=' * 80)
repo_students = defaultdict(list)
for r in rows:
    if r['ck']:
        repo_students[r['ck']].append(r)
    else:
        issues.append(f'Row {r["row_n"]}: ID={r["xh"]} Name={r["xm"]} - repo empty')
for repo in sorted(repo_students.keys()):
    members = repo_students[repo]
    names = ', '.join(m['xm'] for m in members)
    print(f'  [{len(members):2d}] {repo}  <- {names}')
total_covered = sum(len(v) for v in repo_students.values())
print(f'  => {len(repo_students)} unique repos, {total_covered} students')
print()
print('=' * 80)
print('2. Project names (Column F)')
print('=' * 80)
project_students = defaultdict(list)
for r in rows:
    if r['sy']:
        project_students[r['sy']].append(r)
    else:
        issues.append(f'Row {r["row_n"]}: ID={r["xh"]} Name={r["xm"]} - project empty')
for proj in sorted(project_students.keys()):
    print(f'  [{len(project_students[proj]):2d}] {proj}')
print(f'  => {len(project_students)} unique projects')
print()
print('=' * 80)
print('3. Repos with MULTIPLE project names (BUG CHECK)')
print('=' * 80)
repo_projects = defaultdict(set)
for r in rows:
    if r['ck'] and r['sy']:
        repo_projects[r['ck']].add(r['sy'])
cc = 0
for repo in sorted(repo_projects.keys()):
    projects = repo_projects[repo]
    if len(projects) > 1:
        cc += 1
        pl = ' | '.join(sorted(projects))
        msg = f'Repo [{repo}] -> {len(projects)} projects: {pl}'
        print(f'  WARNING: {msg}')
        issues.append(msg)
        for r in repo_students[repo]:
            print(f'      Row {r["row_n"]}: {r["xh"]} {r["xm"]} -> {r["sy"]}')
if cc == 0:
    print('  OK - each repo has exactly one project')
else:
    print(f'  {cc} repos have project conflicts')
print()
print('  Similar project name check:')
pn = sorted(project_students.keys())
for i in range(len(pn)):
    for j in range(i+1, len(pn)):
        a, b = pn[i], pn[j]
        if a in b or b in a:
            msg = f'Possible duplicate: [{a}] vs [{b}]'
            print(f'    WARNING: {msg}')
            issues.append(msg)
        elif len(a) == len(b):
            diff = sum(1 for ca, cb in zip(a, b) if ca != cb)
            if diff <= 2:
                msg = f'Differ by {diff} char(s): [{a}] vs [{b}]'
                print(f'    WARNING: {msg}')
                issues.append(msg)
print()
print('=' * 80)
print('4. Compare with student_repo_map.json')
print('=' * 80)
with open(JPATH, 'r', encoding='utf-8') as f:
    rml = json.load(f)
rm = {str(item['userId']).strip(): item for item in rml}
print(f'  JSON entries: {len(rm)}')
em = {}
for r in rows:
    if r['xh']:
        em[r['xh']] = r
ji = set(rm.keys())
ei = set(em.keys())
oj = ji - ei
oe = ei - ji
co = ji & ei
print(f'  Only in JSON: {len(oj)}')
for sid in sorted(oj):
    item = rm[sid]
    msg = f'JSON-only: {sid} ({item.get("name","?")}) repo={item.get("repo","?")}'
    print(f'    {msg}')
    issues.append(msg)
print(f'  Only in Excel: {len(oe)}')
for sid in sorted(oe):
    r = em[sid]
    msg = f'Excel-only: {sid} ({r["xm"]}) repo={r["ck"]}'
    print(f'    {msg}')
    issues.append(msg)
print(f'  Common IDs: {len(co)}')
rmm = 0
nmm = 0
for sid in sorted(co):
    item = rm[sid]
    jr = str(item.get('repo', '')).strip()
    jn = str(item.get('name', '')).strip()
    er = em[sid]['ck']
    en = em[sid]['xm']
    if jr != er:
        rmm += 1
        msg = f'Repo mismatch: {sid} ({en}) Excel=[{er}] JSON=[{jr}]'
        print(f'    WARNING: {msg}')
        issues.append(msg)
    if jn != en:
        nmm += 1
        msg = f'Name mismatch: {sid} Excel=[{en}] JSON=[{jn}]'
        print(f'    WARNING: {msg}')
        issues.append(msg)
if rmm == 0:
    print('  OK - all repos match')
else:
    print(f'  {rmm} repo mismatches')
if nmm == 0:
    print('  OK - all names match')
else:
    print(f'  {nmm} name mismatches')
jrs = set(item.get('repo','') for item in rml)
ers = set(repo_students.keys())
roj = jrs - ers
roe = ers - jrs
if roj:
    print(f'  Repos in JSON not Excel: {sorted(roj)}')
if roe:
    print(f'  Repos in Excel not JSON: {sorted(roe)}')
print()
print('=' * 80)
print('5. Additional checks')
print('=' * 80)
idc = defaultdict(int)
for r in rows:
    if r['xh']:
        idc[r['xh']] += 1
dups = {k: v for k, v in idc.items() if v > 1}
if dups:
    for sid, cnt in sorted(dups.items()):
        msg = f'Duplicate ID: {sid} appears {cnt} times'
        print(f'  WARNING: {msg}')
        issues.append(msg)
else:
    print('  OK - no duplicate student IDs')
ef = defaultdict(list)
for r in rows:
    for fld, lbl in [('xh','StudentID'),('xm','Name'),('ck','Repo'),('fz','Group'),('sy','Project')]:
        if not r[fld]:
            ef[lbl].append(r['row_n'])
if ef:
    for fld, rn in ef.items():
        msg = f'{fld} empty in rows: {rn}'
        print(f'  WARNING: {msg}')
        issues.append(msg)
else:
    print('  OK - no empty key cells')
us = [r for r in rows if not r['qm']]
sg = [r for r in rows if r['qm']]
print(f'  Signatures: {len(sg)} signed / {len(us)} unsigned')
if us:
    ul = ', '.join(f'{r["xm"]}({r["xh"]})' for r in us)
    print(f'    Unsigned: {ul}')
print()
print('  Group breakdown:')
gm = defaultdict(list)
for r in rows:
    if r['fz']:
        gm[r['fz']].append(r)
for g in sorted(gm.keys(), key=lambda x: (len(x), x)):
    members = gm[g]
    repos = set(m['ck'] for m in members)
    projects = set(m['sy'] for m in members)
    ns = ', '.join(m['xm'] for m in members)
    print(f'    Group [{g}]: {len(members)} members')
    print(f'      Repos: {repos}')
    print(f'      Projects: {projects}')
    print(f'      Members: {ns}')
print()
print('=' * 80)
print('ISSUE SUMMARY')
print('=' * 80)
if issues:
    for i, issue in enumerate(issues, 1):
        print(f'  {i}. {issue}')
    print(f'  => Total: {len(issues)} issues found')
else:
    print('  No issues found!')
