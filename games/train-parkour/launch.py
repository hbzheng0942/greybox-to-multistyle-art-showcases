#!/usr/bin/env python3
"""Launch a complete local Train Parkour showcase with an existing Godot 4.7.2."""
from pathlib import Path
import argparse,json,os,shutil,subprocess,sys

ROOT=Path(__file__).resolve().parent
ALIASES={'h07':'halloween-comic','b2':'odd-logistics','pixel':'pixel-v2','paper':'paper-atlas'}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--style',default='halloween-comic')
    parser.add_argument('--godot',default=os.environ.get('GODOT_BIN'))
    parser.add_argument('--renderer',default='vulkan')
    parser.add_argument('--editor',action='store_true')
    parser.add_argument('--show-hud',action='store_true',help='Show the retained prototype/debug HUD')
    parser.add_argument('--list',action='store_true')
    parser.add_argument('--check-assets',action='store_true')
    args=parser.parse_args()
    styles=json.loads((ROOT/'styles.json').read_text())['styles']
    if args.list:
        for style in styles:print(f"{style['id']}: {style['name']} — {style['version']}")
        return 0
    sid=ALIASES.get(args.style,args.style)
    style=next((x for x in styles if x['id']==sid),None)
    if style is None:parser.error('Unknown style. Use --list.')
    repo=ROOT.parents[1]
    manifest=json.loads((ROOT/'files-manifest.json').read_text())
    missing=[row['path'] for row in manifest['files'] if row.get('asset') and not (repo/row['path']).is_file()]
    if missing:
        print('Large resources are missing. Download/extract the complete release archive described in the repository README.',file=sys.stderr)
        print('\n'.join(missing[:5]),file=sys.stderr)
        return 2
    if args.check_assets:
        print('All required resource links resolve inside the complete checkout.')
        return 0
    binary=args.godot or shutil.which('godot') or shutil.which('godot4')
    if not binary:
        candidate=Path('/Applications/Godot.app/Contents/MacOS/Godot')
        binary=str(candidate) if candidate.is_file() else None
    if not binary:parser.error('Godot 4.7.2 is required. Supply --godot or GODOT_BIN.')
    version=subprocess.check_output([binary,'--version'],text=True).strip()
    if not version.startswith('4.7.2'):parser.error(f'Expected Godot 4.7.2, found {version}')
    project=ROOT/style['engine_root']
    if not args.editor and not (project/'.godot/global_script_class_cache.cfg').is_file():
        print('First launch: importing the native project and registering its script/resource types.')
        subprocess.run([binary,'--headless','--editor','--path',str(project),'--import'],check=True)
    cmd=[binary,'--path',str(project),'--rendering-driver',args.renderer]
    if args.editor:cmd.append('--editor')
    cmd.append(style['entry_scene'])
    if args.show_hud:cmd+=['--','--show-hud']
    return subprocess.call(cmd)

if __name__=='__main__':raise SystemExit(main())
