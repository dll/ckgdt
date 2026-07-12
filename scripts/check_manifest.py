import json, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
with open('build/windows/x64/runner/Release/data/flutter_assets/AssetManifest.json', encoding='utf-8') as f:
    data = json.load(f)
keys = list(data.keys())
print(f'Total keys: {len(keys)}')
ckgdt = [k for k in keys if 'CKGDT' in k or 'ckgdt' in k]
print(f'CKGDT keys: {len(ckgdt)}')
for k in ckgdt[:20]:
    print(f'  {k}')
theory = [k for k in keys if '理论' in k]
print(f'理论 keys: {len(theory)}')
for k in theory:
    print(f'  {k}')
quiz = [k for k in keys if '测验' in k]
print(f'测验 keys: {len(quiz)}')
for k in quiz:
    print(f'  {k}')
