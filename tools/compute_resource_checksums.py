#!/usr/bin/env python3
"""
compute_resource_checksums.py — 计算 CKGDT 资源包校验和并更新 manifest.json

用法:
    python tools/compute_resource_checksums.py [--course CKGDT]

功能:
1. 读取 data/{course}/配置/ 下所有 JSON 文件
2. 计算每个文件的 SHA-256 校验和（排序键、紧凑 JSON）
3. 更新 manifest.json 中每个资源的 checksum 字段
4. 如果任何资源版本变化，递增 package_version
"""

import json
import hashlib
import os
import sys
import argparse
from pathlib import Path


def normalize_json(file_path: Path) -> str:
    """读取 JSON 文件并返回标准化的字符串（排序键、无空格）"""
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def compute_sha256(content: str) -> str:
    """计算字符串的 SHA-256 校验和"""
    return 'sha256:' + hashlib.sha256(content.encode('utf-8')).hexdigest()


def bump_version(version: str) -> str:
    """递增版本号的 patch 版本"""
    parts = version.split('.')
    if len(parts) == 3:
        parts[2] = str(int(parts[2]) + 1)
    return '.'.join(parts)


def main():
    parser = argparse.ArgumentParser(description='计算资源包校验和')
    parser.add_argument('--course', default='CKGDT', help='课程目录名 (default: CKGDT)')
    args = parser.parse_args()

    project_root = Path(__file__).parent.parent
    config_dir = project_root / 'data' / args.course / '配置'
    manifest_path = config_dir / 'manifest.json'

    if not manifest_path.exists():
        print(f'Error: {manifest_path} not found')
        sys.exit(1)

    # 读取 manifest
    with open(manifest_path, 'r', encoding='utf-8') as f:
        manifest = json.load(f)

    resources = manifest.get('resources', {})
    if not resources:
        print('No resources found in manifest')
        sys.exit(1)

    updated_count = 0
    old_manifest = json.dumps(manifest, ensure_ascii=False, sort_keys=True)

    for key, entry in resources.items():
        if not isinstance(entry, dict):
            # 旧格式：value 是文件名字符串，跳过
            continue

        filename = entry.get('file', f'{key}.json')
        file_path = config_dir / filename

        if not file_path.exists():
            print(f'  [SKIP] {filename} not found')
            continue

        # 计算校验和
        try:
            normalized = normalize_json(file_path)
            checksum = compute_sha256(normalized)
        except Exception as e:
            print(f'  [ERROR] {filename}: {e}')
            continue

        old_checksum = entry.get('checksum')
        if old_checksum != checksum:
            entry['checksum'] = checksum
            updated_count += 1
            print(f'  [UPDATED] {filename} → {checksum[:30]}...')
        else:
            print(f'  [OK] {filename} checksum unchanged')

    # 如果有变更，递增 package_version
    new_manifest = json.dumps(manifest, ensure_ascii=False, sort_keys=True)
    if new_manifest != old_manifest:
        old_version = manifest.get('package_version', '1.0.0')
        manifest['package_version'] = bump_version(old_version)
        print(f'\nPackage version: {old_version} → {manifest["package_version"]}')

    # 写回 manifest
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write('\n')

    print(f'\nDone: {updated_count} checksums updated, manifest written')


if __name__ == '__main__':
    main()
