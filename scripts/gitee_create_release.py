import os, sys, requests, json

TOKEN = os.environ['GITEE_TOKEN']
REPO = 'osgisOne/mad-fd'
VER = '2.0.2'

# Create release
url = f'https://gitee.com/api/v5/repos/{REPO}/releases'
data = {
    'access_token': TOKEN,
    'tag_name': f'v{VER}',
    'name': f'v{VER} \u2014 \u91cd\u65b0\u6784\u5efa\u4e0e\u90e8\u7f72',
    'body': f'v{VER} \u5168\u7aef\u6784\u5efa\u53d1\u5e03\u3002\n\n\u5305\u542b Android / Windows / Web / HarmonyOS \u56db\u7aef\u3002\n\n\u5df2\u77e5\u95ee\u9898\uff1aWindows \u7aef\u542f\u52a8\u65f6 0xC0000005 \u5d29\u6e83\uff08DLL \u521d\u59cb\u5316\u9636\u6bb5\uff09\uff0c\u9700\u8981\u8fdb\u4e00\u6b65\u6392\u67e5\u3002',
    'target_commitish': 'master',
}
print(f'Creating release tag=v{VER}...')
r = requests.post(url, data=data)
if r.status_code == 201:
    rel = r.json()
    rid = rel['id']
    print(f'Release created: ID={rid} Tag={rel["tag_name"]}')
else:
    print(f'FAILED: {r.status_code} {r.text[:500]}')
    sys.exit(1)

# Upload assets
upload_url = f'https://gitee.com/api/v5/repos/{REPO}/releases/{rid}/attach_files'

assets = [
    (r'D:\FlutterProjects\knowledge_graph_app\dist\CKGDT+windows+v2.0.2.zip', 'CKGDT+windows+v2.0.2.zip'),
    (r'D:\FlutterProjects\knowledge_graph_app\dist\CKGDT+android+v2.0.2.zip', 'CKGDT+android+v2.0.2.zip'),
    (r'D:\FlutterProjects\knowledge_graph_app\dist\CKGDT+web+v2.0.2.zip', 'CKGDT+web+v2.0.2.zip'),
]

session = requests.Session()
for path, display in assets:
    if not os.path.isfile(path):
        print(f'  SKIP (missing): {display}')
        continue
    size_mb = os.path.getsize(path) / (1024*1024)
    if size_mb > 100:
        print(f'  SKIP (over 100MB Gitee limit): {display} ({size_mb:.1f}MB)')
        continue
    submit_name = display.replace('+', '%2B')
    with open(path, 'rb') as fh:
        files = {'file': (submit_name, fh, 'application/octet-stream')}
        params = {'access_token': TOKEN}
        r2 = session.post(upload_url, params=params, files=files, timeout=600)
    if r2.status_code == 201:
        stored = r2.json().get('name', '?') if r2.text else '?'
        print(f'  OK [{r2.status_code}]  {size_mb:>6.1f} MB  {stored}')
    else:
        print(f'  FAIL [{r2.status_code}]  {display}')
        print(f'       {r2.text[:300]}')

print('--- DONE ---')
