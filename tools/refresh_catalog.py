#!/usr/bin/env python3
"""Normalize game-owned indexes into the public query/launcher catalog."""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = {'hole': 'Hole 黑洞', 'train-parkour': '列车跑酷', 'museum-dog': '狗闹博物馆', 'bubble-buddies': 'Bubble Buddies'}


def refresh():
    games = []
    for game_id, name in NAMES.items():
        base = ROOT / 'games' / game_id
        raw = json.loads((base / 'styles.json').read_text())
        entries = []
        for style in raw['styles']:
            item = {'id': style['id'], 'name': style['name'], 'status': style.get('status', style.get('progress')), 'version': style.get('version', style.get('source_revision')), 'source_index': f'games/{game_id}/styles.json'}
            if 'project' in style:
                item['project'] = f"games/{game_id}/{style['project']}"
                item['scene'] = style.get('scene')
            elif 'engine_root' in style:
                item['project'] = f"games/{game_id}/{style['engine_root']}/project.godot"
                item['scene'] = style.get('entry_scene')
                item['engine_args'] = ['--rendering-driver', 'vulkan']
            elif style.get('entry'):
                item['project'] = f'games/{game_id}/project.godot'
                item['scene'] = 'res://' + style['entry']
            image = style.get('preview', style.get('thumbnail'))
            if image:
                item['screenshot'] = f'games/{game_id}/{image}'
            elif game_id == 'bubble-buddies' and style['id'] == 'd1-animal-city':
                item['screenshot'] = f'games/{game_id}/previews/d1-r9-native.png'
            elif game_id == 'museum-dog' and style['id'] == 'A01':
                previews = [base / 'previews/current-skeletal-native.png'] if (base / 'previews/current-skeletal-native.png').is_file() else sorted((base / 'previews').glob('*.png'))
                if previews:
                    item['screenshot'] = str(previews[0].relative_to(ROOT))
            item['verification'] = {key: value for key, value in style.items() if key in {'technical_validation', 'native_validation', 'native_verified', 'human_art_acceptance', 'human_playtest', 'user_accepted'}}
            entries.append(item)
        games.append({'id': game_id, 'name': name, 'guide': f'games/{game_id}/GAME.md', 'styles': entries})
    catalog = {'schema': 1, 'engine': 'Godot 4.7.2', 'status_note': 'Technical packaging checks do not imply art, animation, gameplay or performance acceptance.', 'games': games}
    (ROOT / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    assets = []
    for path in sorted((ROOT / 'shared/assets/sha256').glob('*/*')):
        assets.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': path.stem, 'bytes': path.stat().st_size})
    (ROOT / 'assets-manifest.json').write_text(json.dumps({'schema': 1, 'assets': assets, 'count': len(assets), 'bytes': sum(item['bytes'] for item in assets)}, indent=2) + '\n')
    links = []
    from package_release import paths
    for path in paths():
        if path.is_symlink():
            links.append({'path': path.relative_to(ROOT).as_posix(), 'target': os.readlink(path)})
    (ROOT / 'resource-links.json').write_text(json.dumps({'schema': 1, 'links': links}, indent=2) + '\n')
    print(json.dumps({'games': len(games), 'runnable_entries': sum(bool(s.get('project')) for g in games for s in g['styles'])}))


if __name__ == '__main__':
    refresh()
