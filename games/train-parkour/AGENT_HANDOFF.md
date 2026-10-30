# Agent handoff: Train Parkour

This case packages five existing candidates. Continue from `case.json`, `styles.json`, `GAME.md`, `INTEGRATION_MATRIX.json` and `validation/index.json`. Do not infer the latest version from folder timestamps.

Main's four style entries share `shared/engine-main/{game,art,tools}`. Paper R9 uses `styles/paper-atlas/engine/`; unchanged small source files link back to main, and immutable resources link to the repository-wide hash store. Do not duplicate engines/assets for a style or follow symlinks into a second full project copy.

H07 is frozen from the stable integrated source revision listed in the matrix. The separate frame-rate experiment is in progress and excluded. Do not copy its older base over current train readability, actors, scene or lighting. A new integration requires explicit ownership, file/hash comparison, a scoped change record and affected verification.

Gameplay, route, collision, solver, speed and formal camera remain the baseline authority. Art and adapter changes need native review; headless assembly is not art acceptance. `shared/engine-main/tools/validate_h07_integration.gd` runs a complete H07 assembly and six synthetic-input branches without rendering. Read its limits before interpreting a pass.

Public adapters add clean-view defaults, scene selectors, isolated application names and Editor-compatible Pixel art switches. The original prototype HUD remains available with `--show-hud`. Runtime JSON keeps the necessary placement/asset data while authoring/provider/private metadata is removed; content-bound JSON hashes are updated. `files-manifest.json` records the resulting package bytes.

Keep uncommitted source work in its owning project. This repository's manifests contain public relative paths only. Do not add private local paths, tokens, provider responses, caches or previous rejected builds. Use explicit G1 for any separately authorized new Lux generation; this packaging task generated no new assets.

After changing a resource, update only its content-hash entry and affected manifests. Reuse unchanged assets. After validation, remove only scratch/import outputs created by that change; preserve screenshots, small logs, exact source hashes and named milestones.
