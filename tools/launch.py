#!/usr/bin/env python3
"""List showcase entries or import/run a selected game and visual style."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('game', nargs='?')
    parser.add_argument('style', nargs='?')
    parser.add_argument('--godot', default=shutil.which('godot') or shutil.which('godot4') or 'godot')
    parser.add_argument('--import', dest='import_only', action='store_true')
    args, extra = parser.parse_known_args()
    catalog = json.loads((ROOT / 'catalog.json').read_text())
    if not args.game or not args.style:
        for game in catalog['games']:
            for style in game['styles']:
                if style.get('project'):
                    print(f"{game['id']:18} {style['id']:22} {style['name']}")
        return
    game = next(item for item in catalog['games'] if item['id'] == args.game)
    style = next(item for item in game['styles'] if item['id'] == args.style)
    if not style.get('project'):
        parser.error('This direction has no runnable project yet')
    resource = ROOT / 'shared/assets/sha256'
    if not resource.is_dir() or not any(resource.glob('*/*')):
        parser.error('Download the complete Release archive before importing; see README.md')
    engine_root = (ROOT / style['project']).parent
    command = [args.godot, '--path', str(engine_root)]
    if args.import_only:
        raise SystemExit(subprocess.call(command + style.get('engine_args', []) + ['--headless', '--editor', '--import'] + extra))
    if not (engine_root / '.godot/global_script_class_cache.cfg').is_file():
        print('First launch: importing resources and registering script classes...', flush=True)
        result = subprocess.call(command + style.get('engine_args', []) + ['--headless', '--editor', '--import'])
        if result:
            raise SystemExit(result)
    command += style.get('engine_args', [])
    if style.get('scene'):
        command.append(style['scene'])
    command += extra
    raise SystemExit(subprocess.call(command))


if __name__ == '__main__':
    main()
