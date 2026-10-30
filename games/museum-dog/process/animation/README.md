# Actual skeletal integration evidence

These are silent native frame-sequence recordings from the **controlled full-museum fixture**, not human live play or a real-time FPS certificate. Overlay UI is hidden. The package includes the27-bone dog and6 adult52-bone skins; child/staff new rigs are still upstream pending.

- [Adult patrol / clap / knockdown / recovery / reset](visitors.mp4),347 native frames at30fps.
- [Dog E acquisition / carrying walk / turn / stop / Space / R](dog-carry.mp4),234 native frames at30fps.
- [Machine-readable checks and limits](VALIDATION.json).37 assertions passed; actual skeleton matrices change over time (dog55/adult109 sampled unique poses). Some NPCs occlude the fixture camera.

To record the same staged source, import the game with Godot4.7.2, then run:

```sh
godot --path games/museum-dog --fixed-fps 60 --script res://process/animation/replay_fixture.gd -- --out=/tmp/museum-skeletal-fixture-new
python games/museum-dog/process/animation/encode_capture.py /tmp/museum-skeletal-fixture-new
```

Choose a new output directory each time. The encoder needs FFmpeg/ffprobe on PATH; it validates frame count and full decode before removing disposable sequence frames. The remaining keyframes retain actual poses. Camera cuts, a controlled neck-bone floor fixture and explicit native gag state are part of the disclosed test. No supplier calls occur.
