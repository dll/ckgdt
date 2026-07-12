import os, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
os.environ['PYTHONIOENCODING'] = 'utf-8'
files = sorted(os.listdir('data/CKGDT/理论'))
for f in files:
    print(f)
