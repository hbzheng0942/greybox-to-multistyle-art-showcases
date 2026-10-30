"""Explicit-file staging with APFS clones and one repository-wide hash asset store."""
from pathlib import Path
import ctypes, errno, hashlib, json, os, shutil, stat, tempfile

REPO = Path(__file__).resolve().parents[1]
ASSETS = REPO / 'shared/assets/sha256'
BINARY_SUFFIXES = {'.glb','.bin','.png','.jpg','.jpeg','.webp','.wav','.ogg','.mp3','.ttf','.otf','.woff','.woff2','.blend','.scn','.res','.exr','.hdr','.ktx','.ktx2','.dds','.tga'}
_CACHE = {}
_LIBC = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
_LIBC.clonefile.argtypes = [ctypes.c_char_p,ctypes.c_char_p,ctypes.c_int]
_LIBC.clonefile.restype = ctypes.c_int

def sha256(path):
    path=Path(path);s=path.stat();key=(str(path.resolve()),s.st_ino,s.st_size,s.st_mtime_ns)
    if key not in _CACHE:
        h=hashlib.sha256()
        with path.open('rb') as f:
            for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
        _CACHE[key]=h.hexdigest()
    return _CACHE[key]

def clone_file(source, destination):
    source=Path(source).resolve();destination=Path(destination)
    destination.parent.mkdir(parents=True,exist_ok=True)
    expected=sha256(source)
    if destination.exists():
        if sha256(destination)!=expected:raise FileExistsError(f'Different existing file: {destination}')
        return destination
    if _LIBC.clonefile(os.fsencode(source),os.fsencode(destination),0):
        code=ctypes.get_errno()
        if code==errno.EEXIST and destination.exists() and sha256(destination)==expected:return destination
        # No silent multi-GB physical-copy fallback. Small source files are inexpensive.
        if source.stat().st_size>=256*1024:raise OSError(code,'APFS clone unavailable; large copy refused',str(source))
        shutil.copy2(source,destination)
    assert sha256(destination)==expected
    assert source.stat().st_ino!=destination.stat().st_ino, 'Mutable source must have an independent inode'
    return destination

class Stage:
    def __init__(self, game_root, private_root):
        self.game_root=Path(game_root).resolve();self.private_root=Path(private_root).resolve()
        assert self.game_root.is_relative_to(REPO/'games')
        self.game_root.mkdir(parents=True,exist_ok=True);self.private_root.mkdir(parents=True,exist_ok=True)
        self.records={}

    def add_file(self, source, destination, kind='auto', binary=None):
        """destination is relative to game_root. kind=source/asset/preview/auto."""
        source=Path(source).resolve();dest=self.game_root/Path(destination)
        assert dest.absolute().is_relative_to(self.game_root)
        assert source.is_file()
        if source.name.startswith('.env') or any(x in {'.git','.godot','node_modules','.venv','__pycache__','workbench_provider'} for x in Path(destination).parts):
            raise ValueError(f'Excluded private/cache path: {destination}')
        h=sha256(source);before=source.stat();is_binary=(source.suffix.lower() in BINARY_SUFFIXES) if binary is None else binary
        if kind in {'source','preview'}:is_binary=False
        if kind=='asset':is_binary=True
        target=None
        if is_binary:
            target=ASSETS/h[:2]/(h+source.suffix.lower())
            clone_file(source,target)
            dest.parent.mkdir(parents=True,exist_ok=True)
            relative=os.path.relpath(target,dest.parent)
            if os.path.lexists(dest):
                if not dest.is_symlink() or dest.resolve()!=target.resolve():raise FileExistsError(dest)
            else:dest.symlink_to(relative)
        else:clone_file(source,dest)
        after=source.stat()
        if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns):raise RuntimeError(f'Source drift during staging: {source}')
        self.records[str(dest.relative_to(REPO))]={'path':str(dest.relative_to(REPO)),'source':str(source),'source_sha256':h,'sha256':h,'bytes':before.st_size,'kind':'asset' if is_binary else kind,'asset':str(target.relative_to(REPO)) if target else None}
        return dest

    stage_file=add_file

    def write_manifests(self):
        for record in self.records.values():
            path=REPO/record['path']
            record['sha256']=sha256(path)
            record['bytes']=path.stat().st_size
            record['transformed']=record['source_sha256']!=record['sha256']
        private=list(self.records.values())
        (self.private_root/'staged-files.json').write_text(json.dumps(private,ensure_ascii=False,indent=2)+'\n')
        public=[{k:v for k,v in row.items() if k not in {'source','source_sha256'}} for row in private]
        (self.game_root/'files-manifest.json').write_text(json.dumps({'schema':1,'files':public},ensure_ascii=False,indent=2)+'\n')
        return public

    refresh_manifest=write_manifests

    def summary(self):
        assets={r['asset']:r['bytes'] for r in self.records.values() if r['asset']}
        return {'files':len(self.records),'unique_asset_count':len(assets),'unique_asset_bytes':sum(assets.values()),'project_tree_copies':0}
