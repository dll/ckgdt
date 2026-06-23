import os, sys, requests
TOKEN = os.environ['GITEE_TOKEN']
RELEASE_ID = 722286
REPO = 'chzcldl/mad-kgdt'
URL = f'https://gitee.com/api/v5/repos/{REPO}/releases/{RELEASE_ID}/attach_files'
def safe_name(name): return name.replace('+', '%2B')
BRAND = '课程图谱与数字孪生'
DIST = os.path.join(os.path.dirname(__file__), os.pardir, 'dist')
v = '2.1.0'
ASSETS = [
	(os.path.join(DIST, f'{BRAND}+windows+v{v}.zip'),   f'{BRAND}+windows+v{v}.zip'),
	(os.path.join(DIST, f'{BRAND}+android+v{v}.zip'),   f'{BRAND}+android+v{v}.zip'),
	(os.path.join(DIST, f'{BRAND}+web+v{v}.zip'),       f'{BRAND}+web+v{v}.zip'),
	(os.path.join(DIST, f'{BRAND}+harmonyos+v{v}.zip'), f'{BRAND}+harmonyos+v{v}.zip'),
]
session = requests.Session()
for path, display in ASSETS:
	if not os.path.isfile(path):
		print(f'  SKIP (missing): {display}', flush=True); continue
	size_mb = os.path.getsize(path) / 1024 / 1024
	submit_name = safe_name(display)
	with open(path, 'rb') as fh:
		files = {'file': (submit_name, fh, 'application/octet-stream')}
		params = {'access_token': TOKEN}
		r = session.post(URL, params=params, files=files, timeout=600)
	if r.status_code == 201:
		stored = r.json().get('name', '?') if r.text else '?'
		print(f'  OK [{r.status_code}]  {size_mb:>6.1f} MB  {stored}', flush=True)
	else:
		print(f'  FAIL [{r.status_code}]  {display}', flush=True)
		print('       ', r.text[:300], flush=True); sys.exit(1)
print('--- DONE ---')
