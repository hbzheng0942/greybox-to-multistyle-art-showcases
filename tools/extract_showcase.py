#!/usr/bin/env python3
"""Offline, cross-platform extraction of the complete showcase ZIP. Python3 only."""
import argparse, hashlib, os, shutil, stat, zipfile
from pathlib import Path, PurePosixPath
EXPECTED_SHA256 = '9e7e8608f3e109215712d62d654b34171f08e35157c537e76502ac71f44bef1d'

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

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive',nargs='?',type=Path,default=Path(__file__).parent/'greybox-to-multistyle-art-showcases-v0.1.0-20261030.zip')
    parser.add_argument('--output',type=Path,default=Path.cwd())
    args=parser.parse_args()
    digest=hashlib.sha256()
    with args.archive.open('rb') as stream:
        for block in iter(lambda:stream.read(4*1024*1024),b''):digest.update(block)
    if digest.hexdigest()!=EXPECTED_SHA256:raise SystemExit('Archive SHA256 mismatch; copy/download again.')
    print('SHA256 verified; extracting source and shared assets...',flush=True)
    extract(args.archive,args.output)
    print('Ready: '+str(args.output.resolve()/'greybox-to-multistyle-art-showcases'))

if __name__=='__main__':main()
