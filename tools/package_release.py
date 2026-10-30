#!/usr/bin/env python3
"""Build and verify the single complete ZIP from the final staged repository."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'greybox-to-multistyle-art-showcases'
EXCLUDED = {'.git', '.godot', '__pycache__', '.pytest_cache', 'node_modules', '.venv', '.local', 'private', 'dist', 'downloads', '.DS_Store'}


def paths(root=ROOT):
    for base, directories, files in os.walk(root, followlinks=False):
        directories[:] = sorted(name for name in directories if name not in EXCLUDED)
        for name in directories:
            if (Path(base) / name).is_symlink():
                raise RuntimeError('Directory links require explicit packaging: ' + str(Path(base) / name))
        for name in sorted(files):
            path = Path(base) / name
            if name in EXCLUDED or name.endswith(('.log', '.partial')) or name.startswith('.env'):
                continue
            yield path


def digest_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def snapshot():
    records = []
    for path in paths():
        relative = path.relative_to(ROOT).as_posix()
        if path.is_symlink():
            target = path.resolve(strict=True)
            if not target.is_relative_to(ROOT):
                raise RuntimeError(f'External resource: {relative}')
            link = os.readlink(path)
            records.append({'path': relative, 'type': 'symlink', 'target': link, 'sha256': hashlib.sha256(link.encode()).hexdigest(), 'bytes': len(link.encode())})
        else:
            before = path.stat()
            digest = digest_file(path)
            after = path.stat()
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise RuntimeError(f'Source changed while freezing: {relative}')
            records.append({'path': relative, 'type': 'file', 'sha256': digest, 'bytes': before.st_size})
    return records


def build(output, tag):
    records = snapshot()
    commit = subprocess.check_output(['/usr/bin/git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    manifest = {'schema': 1, 'release_tag': tag, 'source_commit': commit, 'files': records}
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode()
    fingerprint = hashlib.sha256(manifest_bytes).hexdigest()
    receipt_path = output.with_name(output.name + '.receipt.json')
    if output.exists():
        if receipt_path.exists():
            receipt = json.loads(receipt_path.read_text())
            if receipt['manifest_sha256'] == fingerprint and output.stat().st_size == receipt['archive']['bytes'] and digest_file(output) == receipt['archive']['sha256']:
                print(json.dumps(receipt))
                return
        raise RuntimeError('A different archive exists; do not silently create repeated full archives')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + '.partial')
    if temporary.exists():
        raise RuntimeError(f'Inspect incomplete task-owned archive before retry: {temporary}')
    try:
        with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True, strict_timestamps=False) as bundle:
            for index, record in enumerate(records):
                path = ROOT / record['path']
                archive_name = f"{PREFIX}/{record['path']}"
                if record['type'] == 'symlink':
                    info = zipfile.ZipInfo(archive_name)
                    info.create_system = 3
                    info.external_attr = (stat.S_IFLNK | 0o777) << 16
                    bundle.writestr(info, record['target'])
                else:
                    bundle.write(path, archive_name)
                if index % 300 == 0:
                    print(f'Packing {index}/{len(records)}', flush=True)
            bundle.writestr(f'{PREFIX}/PACKAGE_MANIFEST.json', manifest_bytes)
        # Read every compressed member and compare with the frozen content hash.
        with zipfile.ZipFile(temporary) as bundle:
            for record in records:
                digest = hashlib.sha256()
                with bundle.open(f"{PREFIX}/{record['path']}") as source:
                    for block in iter(lambda: source.read(4 * 1024 * 1024), b''):
                        digest.update(block)
                if digest.hexdigest() != record['sha256']:
                    raise RuntimeError(f"Archive verification failed: {record['path']}")
            if bundle.read(f'{PREFIX}/PACKAGE_MANIFEST.json') != manifest_bytes:
                raise RuntimeError('Archive manifest verification failed')
        temporary.rename(output)
        receipt = {'schema': 1, 'tag': tag, 'source_commit': commit, 'manifest_sha256': fingerprint, 'archive': {'name': output.name, 'bytes': output.stat().st_size, 'sha256': digest_file(output)}, 'files': len(records), 'verified_all_member_hashes_and_crc': True}
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt), flush=True)
    except Exception:
        print(f'Incomplete archive retained for inspection: {temporary}', flush=True)
        raise


def release_spec(archive, tag, volume_bytes):
    parts = []
    total = archive.stat().st_size
    with archive.open('rb') as source:
        for index, offset in enumerate(range(0, total, volume_bytes), 1):
            length = min(volume_bytes, total - offset)
            digest = hashlib.sha256()
            remaining = length
            while remaining:
                block = source.read(min(4 * 1024 * 1024, remaining))
                if not block:
                    raise RuntimeError('Unexpected archive end')
                digest.update(block)
                remaining -= len(block)
            name = archive.name if total <= volume_bytes else f'{archive.name}.{index:03d}'
            parts.append({'name': name, 'offset': offset, 'bytes': length, 'sha256': digest.hexdigest()})
    spec = {'schema': 1, 'tag': tag, 'archive': {'name': archive.name, 'bytes': total, 'sha256': digest_file(archive)}, 'parts': parts, 'join_order': [part['name'] for part in parts]}
    destination = archive.parent / 'release-files.json'
    destination.write_text(json.dumps(spec, indent=2) + '\n')
    print(json.dumps({'manifest': str(destination), 'archive_bytes': total, 'volumes': len(parts)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--spec-only', action='store_true')
    parser.add_argument('--volume-bytes', type=int, default=1750 * 1024 * 1024)
    args = parser.parse_args()
    if not args.spec_only:
        build(args.archive.resolve(), args.tag)
    release_spec(args.archive.resolve(), args.tag, args.volume_bytes)
