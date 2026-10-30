`engine-main/` preserves one shared `game/`, `art/`, `tools/` layout for Clay P21, Pixel V2, B2 and H07. Paper R9 retains a separate source variant under `styles/paper-atlas/engine/` and links unchanged source files back here.

Large immutable resource bytes are shared once in the repository-wide `shared/assets/sha256/` store. Resource-path symlinks stay inside this repository; the complete archive preserves those relationships. Rebuildable Godot import caches are not delivery inputs.
