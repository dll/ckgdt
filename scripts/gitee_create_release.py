import os
import re
import sys
from pathlib import Path

import requests

TOKEN = os.environ['GITEE_TOKEN']
REPO = os.environ.get('GITEE_REPO', 'chzcldl/mad-kgdt')
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
TAG = f'v{VER}'


def find_release_by_tag(tag):
    url = f'https://gitee.com/api/v5/repos/{REPO}/releases'
    for page in range(1, 6):
        r = requests.get(
            url,
            params={
                'access_token': TOKEN,
                'page': page,
                'per_page': 100,
                'direction': 'desc',
            },
            timeout=60,
        )
        r.raise_for_status()
        releases = r.json()
        if not releases:
            return None
        for rel in releases:
            if rel.get('tag_name') == tag:
                return rel
    return None


rel = find_release_by_tag(TAG)
if rel:
    rid = rel['id']
    print(f'Using existing release: ID={rid} Tag={rel["tag_name"]}')
else:
    url = f'https://gitee.com/api/v5/repos/{REPO}/releases'
    data = {
        'access_token': TOKEN,
        'tag_name': TAG,
        'name': f'{TAG} \u2014 CKGDT \u53d1\u5e03',
        'body': f'{TAG} CKGDT \u6784\u5efa\u53d1\u5e03\u3002\n\n\u53d1\u5e03\u9644\u4ef6\u4ee5 dist/ \u76ee\u5f55\u4e2d\u5b9e\u9645\u5b58\u5728\u7684\u8d44\u4ea7\u4e3a\u51c6\u3002',
        'target_commitish': 'master',
    }
    print(f'Creating release tag={TAG}...')
    r = requests.post(url, data=data, timeout=60)
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
