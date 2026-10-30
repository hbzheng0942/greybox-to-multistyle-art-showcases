# Integration record

Agent: Codex showcase integration, 2026-10-30. Original projects were read-only. Only explicit runtime dependencies were staged; immutable resources use one repository-wide hash store and internal relative links.

Changes: resource paths rebased into this game/shared/style layout; portable SystemFont selection; private provider IDs removed from runtime registries where present; no API/provider ledger or cache copied.

The staged package is a distinct portability revision. Source acceptance was not promoted to package acceptance. Technical validation results are recorded separately after staging.

Transformed staged source/data files: 19. Runtime content hashes and relative file mapping are in `files-manifest.json`. Private source locations and exact diffs remain outside the public repository.

The final recording adapter defaults to clean presentation for both art and greybox entries; `--show-hud` restores development UI. Eight final headless visibility/menu/proxy checks passed with zero engine errors. Current gameplay/skin/controller hashes still match the controlled native capture. Main project import caches and generated texture/material sidecars were removed after validation; Godot rebuilds them on first import.
