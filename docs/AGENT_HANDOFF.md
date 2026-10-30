# Agent handoff

This repository publishes existing editable Godot art prototypes. It does not create gameplay, new assets or new acceptance decisions.

Read `PLAN.md`, `catalog.json` and the relevant `games/<game>/GAME.md`. Each style entry records its exact version, engine entry, progress, screenshot and validation. A playable development candidate can still have unresolved visual, comfort or performance issues.

## Source and resources

Game and style code is tracked in Git. Large immutable resources are keyed by SHA256 under `shared/assets/sha256/` and supplied by the complete Release package. Original engine paths use repository-internal relative links; no author-machine paths should be necessary.

`main` remains the editable source/catalog branch. The independent `large-files` branch carries 8 MiB transfer chunks and `large-files/manifest.json`; completed Release volumes can be reused as additional assembly inputs. Do not merge that branch into `main`. Follow [LARGE_FILES.md](LARGE_FILES.md) for the pinned-commit Actions assembly and hash checks. The initial complete archive remains bound to source commit `799c478fe45278cd5db3f3c3a1eb2ec83709583f`; later transport/documentation commits do not change that frozen game payload.

Do not recursively copy original workspaces or include `.godot`, nested `.git`, provider responses, production jobs, credentials, old build archives or rejected versions. Never update a style to a newer directory based on modification time alone. Preserve source and asset versions in the manifest before changing entry pointers.

## Updating a style

1. Identify the exact current development and last verified resources. Keep user acceptance separate.
2. Stage only changed source and actual runtime dependencies. Preserve existing assets by hash; new bytes receive a new hash.
3. Import and launch the affected entry from this repository; check dynamic resources and fonts as well as literal scene dependencies.
4. Update that style's status, real screenshot and validation receipt. A concept image is not a runtime screenshot.
5. Run the package checker, refresh source/asset manifests and rebuild the complete archive only when its content changed.

For gameplay footage, hide prototype/debug overlays and record native continuous 1080p30 frames. Do not duplicate/interpolate frames or claim real-time performance from an offline render. Record input method and exact version outside the video image.

## Current publication

The initial cleanup retains eleven Hole art candidates, five train art candidates, one museum A01 development variant and WorkBuddy D1, plus each game's runnable greybox. The museum package includes current dog/adult skeletal integration; child/staff skeletal production is incomplete. Read the museum and H07 integration matrices before updating concurrent production components.

Each game's `process/INDEX.md` identifies concept plans, greybox/blockout, rough models, qualification assembly and current results. Process images are real Git-tracked images for browser viewing; model bytes use the shared hash store. Preserve stage identity: a concept is not a native view, a generated final mesh is not a rough blockout, and a qualification trial is not a completed style. Process-only resources can use `.gdignore` to avoid automatic imports when opening the playable project.

Unimplemented directions remain explicit progress records. Qualification assets and selected production stages are included for process recording; rejected and superseded complete project trees are excluded. A colleague can clone this repository, run `python3 tools/download_complete.py --install-resources`, then select a greybox or art entry with `tools/launch.py`.

Private source locations, uncommitted-source diffs and original local receipts stay in the development environment. Public evidence includes relative paths, hashes, relevant technical results and actual version limits. The root agent handles publication and the final archive; game workers own their game directories.
