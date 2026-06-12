import os, sys, requests
TOKEN = os.environ['GITEE_TOKEN']
RELEASE_ID = 705199
REPO = 'osgisOne/mad-fd'
URL = f'https://gitee.com/api/v5/repos/{REPO}/releases/{RELEASE_ID}/attach_files'
def safe_name(name): return name.replace('+', '%2B')
ASSETS = [
	(r'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+windows+v1.20.0.zip',   '移动图谱与数字孪生+windows+v1.20.0.zip'),
	(r'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+android+v1.20.0.zip',   '移动图谱与数字孪生+android+v1.20.0.zip'),
	(r'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+web+v1.20.0.zip',       '移动图谱与数字孪生+web+v1.20.0.zip'),
	(r'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+harmonyos+v1.20.0.zip', '移动图谱与数字孪生+harmonyos+v1.20.0.zip'),
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
