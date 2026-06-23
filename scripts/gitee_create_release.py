import os
import re
import sys
from pathlib import Path

import requests

TOKEN = os.environ['GITEE_TOKEN']
REPO = 'osgisOne/mad-fd'
ROOT = Path(__file__).resolve().parents[1]


def read_pubspec_version():
    pubspec = ROOT / 'pubspec.yaml'
    text = pubspec.read_text(encoding='utf-8')
    match = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+\d+)?\s*$',
                      text, re.MULTILINE)
    if not match:
        raise RuntimeError(f'Cannot read version from {pubspec}')
    return match.group(1)


VER = os.environ.get('GITEE_RELEASE_VERSION') or read_pubspec_version()

# Create release
url = f'https://gitee.com/api/v5/repos/{REPO}/releases'
data = {
    'access_token': TOKEN,
    'tag_name': f'v{VER}',
    'name': f'v{VER} \u2014 CKGDT \u5168\u7aef\u53d1\u5e03',
    'body': f'v{VER} CKGDT \u5168\u7aef\u6784\u5efa\u53d1\u5e03\u3002\n\n\u5305\u542b Android / Windows / Web / HarmonyOS \u56db\u7aef\u8d44\u4ea7\uff08\u82e5\u5b58\u5728\uff09\u3002',
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
    (ROOT / 'dist' / f'CKGDT+windows+v{VER}.zip', f'CKGDT+windows+v{VER}.zip'),
    (ROOT / 'dist' / f'CKGDT+android+v{VER}.zip', f'CKGDT+android+v{VER}.zip'),
    (ROOT / 'dist' / f'CKGDT+web+v{VER}.zip', f'CKGDT+web+v{VER}.zip'),
    (ROOT / 'dist' / f'CKGDT+harmonyos+v{VER}.zip', f'CKGDT+harmonyos+v{VER}.zip'),
]

session = requests.Session()
for path, display in assets:
    if not path.is_file():
        print(f'  SKIP (missing): {display}')
        continue
    size_mb = path.stat().st_size / (1024*1024)
    if size_mb > 100:
        print(f'  SKIP (over 100MB Gitee limit): {display} ({size_mb:.1f}MB)')
        continue
    submit_name = display.replace('+', '%2B')
    with path.open('rb') as fh:
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
