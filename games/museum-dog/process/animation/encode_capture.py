"""Encode verified fixture frame sequences; retain videos and a few actual stills."""
from pathlib import Path
import hashlib,json,subprocess,sys,shutil

FFMPEG=shutil.which('ffmpeg')
FFPROBE=shutil.which('ffprobe')
if not FFMPEG or not FFPROBE:raise SystemExit('ffmpeg and ffprobe must be available on PATH')
root=Path(sys.argv[1]).resolve()
result_path=root/'result.json'
result=json.loads(result_path.read_text())
receipts=[]
for segment in result['segments']:
    name=segment['name'];directory=root/name
    frames=sorted(directory.glob('frame-*.jpg'))
    if len(frames)!=segment['frames'] or not frames:
        raise ValueError('Incomplete recorded frames for '+name)
    movie=root/(name+'.mp4')
    if movie.exists():raise ValueError('Refusing to overwrite existing movie')
    subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-framerate','30',
        '-i',str(directory/'frame-%04d.jpg'),'-c:v','libx264','-pix_fmt','yuv420p','-crf','21',
        '-movflags','+faststart',str(movie)],check=True)
    checked=subprocess.run([FFPROBE,'-v','error','-select_streams','v:0',
        '-show_entries','stream=width,height,nb_frames,duration','-of','json',str(movie)],
        capture_output=True,text=True,check=True)
    info=json.loads(checked.stdout)
    if int(info['streams'][0]['nb_frames'])!=len(frames):raise ValueError('Encoded frame count differs')
    subprocess.run([FFMPEG,'-v','error','-i',str(movie),'-f','null','-'],check=True)
    # Preserve one middle-phase still so a blend onset does not stand in for the action.
    chosen={0,len(frames)-1}
    phases={}
    for row in result['samples']:
        if row['segment']==name:phases.setdefault(row['phase'],[]).append(row)
    for phase,rows in phases.items():
        row=rows[len(rows)//2]
        chosen.add(min(len(frames)-1,int(row['capture_tick'])//2))
    kept=[]
    for index,path in enumerate(frames):
        if index in chosen:
            nearby=min((r for r in result['samples'] if r['segment']==name),key=lambda r:abs(r['capture_tick']-index*2))
            kept.append({'path':str(path),'frame':index,'phase':nearby['phase'],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        else:path.unlink()
    receipts.append({'name':name,'path':str(movie),'sha256':hashlib.sha256(movie.read_bytes()).hexdigest(),
        'bytes':movie.stat().st_size,'ffprobe':info,'key_frames':kept,
        'scope':'Phase-labelled controlled native fixture. Camera cuts are deliberate; not a natural route or performance benchmark.'})
receipt={'kind':'combined-native-capture-delivery','raw_result':str(result_path),
    'raw_result_sha256':hashlib.sha256(result_path.read_bytes()).hexdigest(),'videos':receipts,
    'assertion_failures':[row for row in result['assertions'] if not row['passed']]}
(root/'delivery.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'videos':[{'name':r['name'],'bytes':r['bytes'],'seconds':r['ffprobe']['streams'][0]['duration']} for r in receipts],
    'failed_assertions':len(receipt['assertion_failures'])}))
