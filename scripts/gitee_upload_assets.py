import os, sys, requests
TOKEN = os.environ['GITEE_TOKEN']
RELEASE_ID = 712284
REPO = 'osgisOne/mad-fd'
URL = f'https://gitee.com/api/v5/repos/{REPO}/releases/{RELEASE_ID}/attach_files'
def safe_name(name): return name.replace('+', '%2B')
ASSETS = [
	(r'D:\FlutterProjects\knowledge_graph_app\dist\课程图谱与数字孪生+windows+v2.0.1.zip',   '课程图谱与数字孪生+windows+v2.0.1.zip'),
	(r'D:\FlutterProjects\knowledge_graph_app\dist\课程图谱与数字孪生+web+v2.0.1.zip',       '课程图谱与数字孪生+web+v2.0.1.zip'),
	(r'D:\FlutterProjects\knowledge_graph_app\dist\课程图谱与数字孪生+harmonyos+v2.0.1.hap', '课程图谱与数字孪生+harmonyos+v2.0.1.hap'),
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
