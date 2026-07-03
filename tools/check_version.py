import sys, io, re
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

base = r'D:\FlutterProjects\knowledge_graph_app'
files = {
    'pubspec.yaml': f'{base}/pubspec.yaml',
    'version.dart': f'{base}/lib/core/version.dart',
    'strings.xml': f'{base}/android/app/src/main/res/values/strings.xml',
    'CMakeLists.txt': f'{base}/windows/CMakeLists.txt',
    'main.cpp': f'{base}/windows/runner/main.cpp',
    'Runner.rc': f'{base}/windows/runner/Runner.rc',
    'index.html': f'{base}/web/index.html',
    'manifest.json': f'{base}/web/manifest.json',
    'app.json5': f'{base}/ohos/AppScope/app.json5',
}

checks = [
    ('pubspec.yaml', r'version:\s*2\.5\.0'),
    ('version.dart', r"display = '2.5.0'"),
    ('strings.xml', r'CKGDTv2\.5\.0'),
    ('CMakeLists.txt', r'BINARY_OUTPUT_NAME.*CKGDTv2\.5\.0'),
    ('main.cpp', r'CKGDTv2\.5\.0'),
    ('Runner.rc', r'FileDescription.*CKGDTv2\.5\.0'),
    ('Runner.rc', r'OriginalFilename.*CKGDTv2\.5\.0\.exe'),
    ('Runner.rc', r'ProductName.*CKGDTv2\.5\.0'),
    ('index.html', r'application-name.*CKGDTv2\.5\.0'),
    ('index.html', r'apple-mobile-web-app-title.*CKGDTv2\.5\.0'),
    ('index.html', r'<title>CKGDTv2\.5\.0</title>'),
    ('manifest.json', r'"name":\s*"CKGDTv2\.5\.0"'),
    ('app.json5', r'versionName.*2\.5\.0'),
    ('app.json5', r'versionCode.*250'),
]

all_pass = True
for fname, pattern in checks:
    with open(files[fname], encoding='utf-8') as f:
        content = f.read()
    found = bool(re.search(pattern, content))
    status = 'PASS' if found else 'FAIL'
    if not found:
        all_pass = False
    print(f'  {status} {fname}: {pattern}')

print()
print('All checks passed' if all_pass else 'Some checks failed')
