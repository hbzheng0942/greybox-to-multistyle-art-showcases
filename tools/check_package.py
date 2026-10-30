#!/usr/bin/env python3
"""Check internal resource closure, asset hashes and publication privacy."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys

from package_release import ROOT, EXCLUDED, paths, digest_file


def check(write=False):
    errors = []
    files = list(paths())
    asset_count = 0
    asset_bytes = 0
    links = 0
    registered = set()
    for manifest in ROOT.glob('games/*/files-manifest.json'):
        registered.update(row['path'] for row in json.loads(manifest.read_text())['files'])
    patterns = {
        'author-machine-path': re.compile(('/' + 'Users/' + r'[^\s\x00\x22\x27<>]+').encode()),
        'private-company-link': re.compile(('(?:cf|gitlab)\\.' + 'qunhequnhe\\.com').encode()),
        'github-credential': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,})'),
        'api-credential': re.compile(rb'(?:sk-[A-Za-z0-9_-]{30,}|AKIA[A-Z0-9]{16})'),
    }
    for base, directories, _ in os.walk(ROOT, followlinks=False):
        directories[:] = [name for name in directories if name not in EXCLUDED]
        for name in directories:
            if (Path(base) / name).is_symlink():
                errors.append({'path': str((Path(base) / name).relative_to(ROOT)), 'issue': 'directory-symlink-needs-explicit-packaging'})
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        if path.is_symlink():
            links += 1
            if not path.exists():
                errors.append({'path': relative, 'issue': 'missing-resource'})
                continue
            if os.path.isabs(os.readlink(path)) or not path.resolve().is_relative_to(ROOT):
                errors.append({'path': relative, 'issue': 'external-resource'})
                continue
            # Link target bytes are scanned through their canonical regular file.
            continue
        if relative.startswith('shared/assets/sha256/'):
            asset_count += 1
            asset_bytes += path.stat().st_size
            if path.stem != digest_file(path):
                errors.append({'path': relative, 'issue': 'asset-hash-mismatch'})
        elif relative.startswith('games/') and path.stat().st_size > 1024 * 1024 and relative not in registered:
            if path.suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp', '.glb', '.scn', '.bin', '.res', '.wav', '.ogg'} and not ('/previews/' in relative or path.name in {'preview.png', 'thumbnail.jpg'}):
                errors.append({'path': relative, 'issue': 'unregistered-large-binary-possible-import-artifact'})
        # Streaming inspection also catches embedded source locations in GLB/SCN data.
        found = set()
        tail = b''
        with path.open('rb') as stream:
            while block := stream.read(4 * 1024 * 1024):
                data = tail + block
                for label, pattern in patterns.items():
                    if label not in found and pattern.search(data):
                        found.add(label)
                tail = data[-512:]
        for label in sorted(found):
            errors.append({'path': relative, 'issue': label})
    checked_records = 0
    for manifest in sorted(ROOT.glob('games/*/files-manifest.json')):
        records = json.loads(manifest.read_text())['files']
        for record in records:
            path = ROOT / record['path']
            checked_records += 1
            if not path.is_file():
                errors.append({'path': record['path'], 'issue': 'manifest-resource-missing'})
            elif path.stat().st_size != record['bytes'] or digest_file(path) != record['sha256']:
                errors.append({'path': record['path'], 'issue': 'manifest-content-drift'})
    catalog_path = ROOT / 'catalog.json'
    if catalog_path.exists():
        for game in json.loads(catalog_path.read_text())['games']:
            for style in game['styles']:
                for key in ('project', 'screenshot'):
                    if style.get(key) and not (ROOT / style[key]).is_file():
                        errors.append({'path': style[key], 'issue': 'catalog-reference-missing'})
    for document in ROOT.rglob('*.md'):
        if any(part in EXCLUDED for part in document.relative_to(ROOT).parts):
            continue
        content = document.read_text(errors='replace')
        for match in re.finditer(r'\[[^\]]*\]\(([^)]+)\)|<img[^>]+src="([^"]+)"', content):
            target = (match.group(1) or match.group(2)).strip('<>')
            if '://' in target or target.startswith(('#', 'mailto:')):
                continue
            target = target.split('#')[0]
            if write and (document.parent / target).resolve() == ROOT / 'docs/validation/package-check.json':
                # This report is created by the current --write invocation.
                continue
            if target and not (document.parent / target).exists():
                errors.append({'path': str(document.relative_to(ROOT)), 'issue': 'documentation-reference-missing', 'target': target})
    report = {'schema': 1, 'result': 'pass' if not errors else 'fail', 'checked_file_paths': len(files), 'relative_resource_links': links, 'unique_assets': asset_count, 'unique_asset_bytes': asset_bytes, 'game_manifest_records': checked_records, 'checks': ['repository-internal link closure', 'SHA256-addressed immutable resources', 'current game manifest hashes', 'streamed source and binary privacy scan', 'excluded cache/private folders'], 'errors': errors}
    if write:
        output = ROOT / 'docs/validation/package-check.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    report = check(args.write)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    sys.exit(0 if report['result'] == 'pass' else 1)
