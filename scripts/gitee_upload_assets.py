"""
Upload Gitee release assets with proper UTF-8 multipart filename encoding.

Why a Python script instead of curl: Windows curl uses ANSI/GBK to encode
the multipart `Content-Disposition: filename=...` header. Gitee stores the
raw bytes and Web UI displays them as broken latin-1 → garbled Chinese.
`requests` always emits the filename as UTF-8 in the multipart body,
which Gitee correctly stores and renders.

Why we percent-encode `+` in display names: Gitee's server URL-decodes
the multipart filename field, treating literal `+` as space. Pre-encoding
`+` → `%2B` survives that round-trip and is stored as literal `+`.
(Verified empirically — Gitee API does **not** percent-decode `%XX` in
multipart filenames, so other ASCII chars and UTF-8 bytes pass through
unchanged.)
"""
import os
import sys
import requests

TOKEN = os.environ['GITEE_TOKEN']
RELEASE_ID = 691059
REPO = 'osgisOne/mad-fd'
URL = f'https://gitee.com/api/v5/repos/{REPO}/releases/{RELEASE_ID}/attach_files'

# Pre-encode `+` so Gitee doesn't strip it. Other Unicode chars pass through.
def safe_name(name: str) -> str:
    return name.replace('+', '%2B')

# (local_path, display_name)
ASSETS = [
    (r'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+windows+v0.13.1.zip',  '移动图谱与数字孪生+windows+v0.13.1.zip'),
    (r'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+android+v0.13.1.zip',  '移动图谱与数字孪生+android+v0.13.1.zip'),
    (r'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+web+v0.13.1.zip',      '移动图谱与数字孪生+web+v0.13.1.zip'),
    (r'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+harmonyos+v0.13.1.zip','移动图谱与数字孪生+harmonyos+v0.13.1.zip'),
    (r'D:\FlutterProjects\knowledge_graph_app\dist\MAD-windows-v0.13.1.zip',                'MAD-windows-v0.13.1.zip'),
    (r'D:\FlutterProjects\knowledge_graph_app\dist\一键安装-Windows.bat',                    '一键安装-Windows.bat'),
    (r'D:\FlutterProjects\knowledge_graph_app\dist\安装手册.pdf',                            '安装手册.pdf'),
]

session = requests.Session()
for path, display in ASSETS:
    if not os.path.isfile(path):
        print(f'  SKIP (missing): {display}', flush=True)
        continue
    size_mb = os.path.getsize(path) / 1024 / 1024
    submit_name = safe_name(display)
    with open(path, 'rb') as fh:
        files = {'file': (submit_name, fh, 'application/octet-stream')}
        params = {'access_token': TOKEN}
        r = session.post(URL, params=params, files=files, timeout=600)
    if r.status_code == 201:
        try:
            stored = r.json().get('name', '?')
        except Exception:
            stored = '?'
        # Show stored name as raw UTF-8 bytes so terminal codepage doesn't lie
        print(f'  OK [{r.status_code}]  {size_mb:>6.1f} MB  utf8={stored.encode("utf-8")!r}', flush=True)
    else:
        print(f'  FAIL [{r.status_code}]  {display}', flush=True)
        print('       ', r.text[:300], flush=True)
        sys.exit(1)

print('--- DONE ---')
