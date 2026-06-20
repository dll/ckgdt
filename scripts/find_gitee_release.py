import requests, os

token = os.environ['GITEE_TOKEN']
url = 'https://gitee.com/api/v5/repos/osgisOne/mad-fd/releases'
r = requests.get(url, params={'access_token': token, 'per_page': 100})
if not r.ok:
    print(f'Error: {r.status_code} {r.text[:200]}')
    sys.exit(1)
for rel in r.json():
    print('ID=%s tag=%s title=%s' % (rel['id'], rel['tag_name'], rel['name']))
