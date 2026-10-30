#!/usr/bin/env python3
"""Download one complete archive, joining Release volumes without extra part copies."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import urllib.request
import zipfile

REPOSITORY = 'hbzheng0942/greybox-to-multistyle-art-showcases'
ROOT = Path(__file__).resolve().parents[1]


def get_json(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'showcase-downloader', 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.load(response)


def file_hash(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def download(release, directory):
    assets = {asset['name']: asset for asset in release['assets']}
    spec = get_json(assets['release-files.json']['browser_download_url'])
    archive = directory / spec['archive']['name']
    if archive.exists():
        if archive.stat().st_size != spec['archive']['bytes'] or file_hash(archive) != spec['archive']['sha256']:
            raise RuntimeError(f'Existing archive has different content: {archive}')
        return archive
    partial = archive.with_name(archive.name + '.partial')
    partial.parent.mkdir(parents=True, exist_ok=True)
    if not partial.exists():
        partial.touch()
    offset = 0
    with partial.open('r+b') as output:
        for part in spec['parts']:
            if partial.stat().st_size >= offset + part['bytes']:
                output.seek(offset)
                digest = hashlib.sha256()
                remaining = part['bytes']
                while remaining:
                    block = output.read(min(4 * 1024 * 1024, remaining))
                    if not block:
                        break
                    digest.update(block)
                    remaining -= len(block)
                if remaining == 0 and digest.hexdigest() == part['sha256']:
                    offset += part['bytes']
                    continue
            output.truncate(offset)
            output.seek(offset)
            print(f"Downloading {part['name']} ({part['bytes'] / 1e6:.1f} MB)", flush=True)
            request = urllib.request.Request(assets[part['name']]['browser_download_url'], headers={'User-Agent': 'showcase-downloader'})
            digest = hashlib.sha256()
            count = 0
            with urllib.request.urlopen(request, timeout=180) as response:
                while block := response.read(4 * 1024 * 1024):
                    if count + len(block) > part['bytes']:
                        raise RuntimeError('Release volume exceeds its declared size')
                    output.write(block)
                    digest.update(block)
                    count += len(block)
            output.flush()
            if count != part['bytes'] or digest.hexdigest() != part['sha256']:
                output.truncate(offset)
                raise RuntimeError(f"Volume verification failed: {part['name']}")
            offset += count
        output.truncate(offset)
    if partial.stat().st_size != spec['archive']['bytes'] or file_hash(partial) != spec['archive']['sha256']:
        raise RuntimeError('Complete archive verification failed')
    partial.rename(archive)
    return archive


def extract(archive, directory):
    """Extract regular files first; recreate only relative links inside the package."""
    destination = directory.resolve()
    links = []
    with zipfile.ZipFile(archive) as bundle:
        for info in bundle.infolist():
            name = PurePosixPath(info.filename)
            if name.is_absolute() or '..' in name.parts or '\\' in info.filename:
                raise RuntimeError(f'Unsafe archive member: {info.filename}')
            target = destination.joinpath(*name.parts)
            if not target.resolve().is_relative_to(destination):
                raise RuntimeError(f'Unsafe extraction destination: {info.filename}')
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                relative = bundle.read(info).decode('utf-8')
                if os.path.isabs(relative) or not (target.parent / relative).resolve().is_relative_to(destination):
                    raise RuntimeError(f'Unsafe resource link: {info.filename}')
                links.append((target, relative))
                continue
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if os.path.lexists(target):
                raise RuntimeError(f'Extraction would overwrite an existing file: {target}')
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(info) as source, target.open('wb') as output:
                shutil.copyfileobj(source, output, 4 * 1024 * 1024)
            if mode & 0o111:
                target.chmod(0o755)
        pending = links
        while pending:
            following = []
            for target, relative in pending:
                source = (target.parent / relative).resolve()
                if not source.is_file():
                    following.append((target, relative))
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                if os.path.lexists(target):
                    if target.is_symlink() and os.readlink(target) == relative:
                        continue
                    raise RuntimeError(f'Existing link destination: {target}')
                try:
                    target.symlink_to(relative)
                except OSError:
                    # Windows without symlink permission: keep a usable independent file.
                    shutil.copy2(source, target)
            if len(following) == len(pending):
                raise RuntimeError('Missing or cyclic resource link targets')
            pending = following


def install_resources(archive, root=ROOT):
    """Populate an existing Git checkout without replacing its editable source."""
    root = root.resolve()
    manifest = json.loads((root / 'assets-manifest.json').read_text())
    expected = {item['path']: item for item in manifest['assets']}
    with zipfile.ZipFile(archive) as bundle:
        for relative, item in expected.items():
            name = PurePosixPath(relative)
            if name.is_absolute() or '..' in name.parts or not relative.startswith('shared/assets/sha256/'):
                raise RuntimeError('Invalid resource manifest path')
            destination = root / relative
            if destination.exists():
                if destination.stat().st_size == item['bytes'] and file_hash(destination) == item['sha256']:
                    continue
                raise RuntimeError(f'Existing resource differs: {relative}')
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + '.partial')
            with bundle.open('greybox-to-multistyle-art-showcases/' + relative) as source, temporary.open('wb') as output:
                shutil.copyfileobj(source, output, 4 * 1024 * 1024)
            if temporary.stat().st_size != item['bytes'] or file_hash(temporary) != item['sha256']:
                temporary.unlink()
                raise RuntimeError(f'Resource verification failed: {relative}')
            temporary.rename(destination)
    # Git on Windows may check out symlinks as small files containing their target.
    pending = json.loads((root / 'resource-links.json').read_text())['links']
    while pending:
        following = []
        for item in pending:
            destination = root / item['path']
            relative = item['target']
            if os.path.isabs(relative) or not destination.parent.resolve().is_relative_to(root):
                raise RuntimeError('Invalid resource link destination')
            source = (destination.parent / relative).resolve()
            if not source.is_relative_to(root):
                raise RuntimeError('External resource link target')
            if destination.is_symlink():
                if os.readlink(destination) != relative:
                    raise RuntimeError(f'Existing link differs: {item["path"]}')
                continue
            if not source.is_file():
                following.append(item)
                continue
            if destination.exists():
                if destination.stat().st_size < 4096 and destination.read_bytes().strip() == relative.encode():
                    destination.unlink()
                elif destination.stat().st_size == source.stat().st_size and file_hash(destination) == file_hash(source):
                    continue
                else:
                    raise RuntimeError(f'Existing editable file differs: {item["path"]}')
            destination.parent.mkdir(parents=True, exist_ok=True)
            try:
                destination.symlink_to(relative)
            except OSError:
                shutil.copy2(source, destination)
        if len(following) == len(pending):
            raise RuntimeError('Unresolved source/resource links')
        pending = following
    print(f'Installed and verified {len(expected)} shared resources')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', help='Release tag; default is latest published release')
    parser.add_argument('--output', type=Path, help='Download destination; defaults to downloads/ when installing resources')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--extract', action='store_true', help='Extract next to the archive after SHA256 verification')
    mode.add_argument('--install-resources', action='store_true', help='Install only resources into this Git checkout and repair links')
    args = parser.parse_args()
    if args.output is None:
        args.output = ROOT / 'downloads' if args.install_resources else Path.cwd()
    route = f'tags/{args.tag}' if args.tag else 'latest'
    release = get_json(f'https://api.github.com/repos/{REPOSITORY}/releases/{route}')
    args.output.mkdir(parents=True, exist_ok=True)
    archive = download(release, args.output)
    print(f'Verified: {archive}')
    if args.extract:
        extract(archive, args.output)
        print(f'Extracted: {args.output / "greybox-to-multistyle-art-showcases"}')
    elif args.install_resources:
        install_resources(archive)


if __name__ == '__main__':
    main()
