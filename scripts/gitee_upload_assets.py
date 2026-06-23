import os
import re
import sys
from pathlib import Path

import requests

TOKEN = os.environ['GITEE_TOKEN']
REPO = os.environ.get('GITEE_REPO', 'chzcldl/mad-kgdt')
ROOT = Path(__file__).resolve().parents[1]
BRAND = 'CKGDT'


def read_pubspec_version():
    text = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    match = re.search(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+\d+)?\s*$',
        text,
        re.MULTILINE,
    )
    if not match:
        raise RuntimeError('Cannot read version from pubspec.yaml')
    return match.group(1)


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


def safe_name(name):
    return name.replace('+', '%2B')


version = os.environ.get('GITEE_RELEASE_VERSION') or read_pubspec_version()
tag = f'v{version}'
release_id = os.environ.get('GITEE_RELEASE_ID')

if release_id:
    rid = release_id
else:
    rel = find_release_by_tag(tag)
    if not rel:
        print(f'Release not found for {tag}; create it first.')
        sys.exit(1)
    rid = rel['id']

url = f'https://gitee.com/api/v5/repos/{REPO}/releases/{rid}/attach_files'
dist = ROOT / 'dist'
assets = [
    (dist / f'{BRAND}+windows+v{version}.zip', f'{BRAND}+windows+v{version}.zip'),
    (dist / f'{BRAND}+android+v{version}.zip', f'{BRAND}+android+v{version}.zip'),
    (dist / f'{BRAND}+web+v{version}.zip', f'{BRAND}+web+v{version}.zip'),
    (
        dist / f'{BRAND}+harmonyos+v{version}.zip',
        f'{BRAND}+harmonyos+v{version}.zip',
    ),
]

session = requests.Session()
for path, display in assets:
    if not path.is_file():
        print(f'  SKIP (missing): {display}', flush=True)
        continue
    size_mb = path.stat().st_size / 1024 / 1024
    submit_name = safe_name(display)
    with path.open('rb') as fh:
        files = {'file': (submit_name, fh, 'application/octet-stream')}
        params = {'access_token': TOKEN}
        r = session.post(url, params=params, files=files, timeout=600)
    if r.status_code == 201:
        stored = r.json().get('name', '?') if r.text else '?'
        print(f'  OK [{r.status_code}]  {size_mb:>6.1f} MB  {stored}', flush=True)
    else:
        print(f'  FAIL [{r.status_code}]  {display}', flush=True)
        print(f'       {r.text[:300]}', flush=True)
        sys.exit(1)
print('--- DONE ---')
