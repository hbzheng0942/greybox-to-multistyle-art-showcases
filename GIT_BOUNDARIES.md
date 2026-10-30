# Repository boundary

This directory is an independent publication repository. The original game workspaces and their Git histories remain independent and must not be recursively added or cleaned.

Track source, small native previews, manifests and portable tools. Large resources live in the ignored `shared/assets/sha256/` store and are included in the complete Release archive. A source-only Git checkout requires the resource download before importing a game. Reproducible engine caches, provider jobs, local provenance and credentials are excluded.
