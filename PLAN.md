# Showcase publication plan

Status: game directories frozen and locally verified; preparing the first complete Release. The user authorized a public personal GitHub repository named `greybox-to-multistyle-art-showcases` on 2026-10-30. This supersedes the earlier inventory-only packaging hold.

Deliverables:
1. Current editable Godot showcase projects grouped by game, shared code/assets, and style. Exclude rejected, abandoned and superseded engineering versions.
2. A concise game / style / progress / screenshot README with exact launch instructions and honest development status.
3. A complete self-contained download archive, public repository and reproducible agent handoff records.

Ownership:
- Hole worker: `games/hole/`, eleven current full-project candidates.
- Train worker: `games/train-parkour/`, clay, pixel V2, paper R9, B2 and H07.
- Museum/Bubble worker: `games/museum-dog/` and `games/bubble-buddies/`, fixed A01, v9 greybox and WorkBuddy D1; unimplemented directions are status entries only.
- Root: shared staging tools, README/catalog, asset archive, privacy/portability checks, GitHub publication and final verification.

All workers share this checkout. Preserve other workers' changes. Original projects remain read-only for this task. Do not copy whole repositories, caches, historical builds or production/provider records. Stage explicit runtime/source dependencies only. Use one repository-wide content-hash asset store under `shared/assets/sha256/` and repository-internal relative links at original resource paths.

Repository source, preview images and manifests are tracked by Git on `main`. Large resource bytes are delivered in the complete release archive. At the user's request, transfer uses 8 MiB ordinary Git chunks in a separate `large-files` branch, existing verified Release volumes, and GitHub Actions assembly. Keep source clones on `main` with `--single-branch`. No LFS billing or paid generation is authorized by this plan. The GitLab route was cancelled by the user.

Keep actual local source paths, dirty-source diffs and private provenance outside the public repository. Public manifests contain relative paths, content hashes and status. Preserve third-party notices. A technical launch check is distinct from visual/user acceptance.

Before publication: check resource/link closure, detect private paths/secrets, import/launch selected entries, inspect representative real frames, freeze the package source and hashes, create the one final archive, verify its contents and then publish. Do not upload an incomplete placeholder repository as completed work.
