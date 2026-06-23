import os
import sys

import requests

token = os.environ['GITEE_TOKEN']
repo = os.environ.get('GITEE_REPO', 'chzcldl/mad-kgdt')
url = f'https://gitee.com/api/v5/repos/{repo}/releases'
r = requests.get(url, params={'access_token': token, 'per_page': 100})
if not r.ok:
    print(f'Error: {r.status_code} {r.text[:200]}')
    sys.exit(1)
for rel in r.json():
    print('ID=%s tag=%s title=%s' % (rel['id'], rel['tag_name'], rel['name']))
