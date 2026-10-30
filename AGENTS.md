# Working on the showcases

Start with PLAN.md, catalog.json, docs/AGENT_HANDOFF.md and the relevant games/<game>/GAME.md. Use the recorded style entry and content hashes, not a guessed latest directory.

Keep shared gameplay and assets reusable; style variants retain clear entries and status. Preserve the distinction between development, technically verified and user accepted. Do not turn concept images or qualification assemblies into completed-game claims.

Large immutable resources live once under shared/assets/sha256. Engine paths may use repository-internal relative links. No absolute or external links, private local paths, credentials, provider responses, caches, obsolete builds or nested .git directories belong in public source or archives.

Do not copy whole source projects for checkpoints. Keep source history in Git and evidence as small logs, relevant captures and manifests. Reuse the current complete archive; only rebuild after its content changes. Never overwrite canonical assets or another agent's work.

New Lux3D generation, if separately authorized, uses explicit version G1 and omits enablePbr. Existing assets retain their actual provenance.
