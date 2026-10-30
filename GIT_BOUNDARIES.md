# Repository boundary

This directory is an independent publication repository. The original game workspaces and their Git histories remain independent and must not be recursively added or cleaned.

Track source, small native previews, manifests and portable tools. Large resources live in the ignored `shared/assets/sha256/` store and are included in the complete Release archive. A source-only Git checkout requires the resource download before importing a game. Reproducible engine caches, provider jobs, local provenance and credentials are excluded.

The separate `large-files` branch is a bounded transfer store for 8 MiB archive chunks and its hash manifest. Do not merge it into `main`, copy its chunks into source projects, or rebuild a duplicate archive for a transfer retry. Clone `main` with `--single-branch`; restore resources through the Release installer. The Actions assembly reads a pinned resource commit and verifies both chunk and complete archive hashes before publication.
