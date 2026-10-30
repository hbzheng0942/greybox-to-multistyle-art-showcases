# Publication validation

Technical checks apply to the frozen portable package and its recorded resource hashes. They do not grant art, gameplay, animation or real-time performance acceptance.

| Case | Verified scope | Limits / receipt |
|---|---|---|
| Hole |11style source imports and actual gameplay assembly/automatic route checks; independent Showcase application namespaces; current comic/orbital native starts | Historical style previews are labelled; see game validation and files manifest. |
| Train |6native entry frames with no script/shader error; H07 full37-track/nine-region union across6headless branches | Paper saved its correct native frame but capture shutdown required termination. See [validation](../games/train-parkour/validation/index.json). |
| Museum | Current full-museum dog/adult skeletal fixture:37assertions, changing actual bone poses, skin/camera/contact/grab/carry/throw/reset checks; native footage supplied | Only dog and6adult visitors have the new skins;2children/2staff skeletal work remains upstream. See [integration matrix](../games/museum-dog/INTEGRATION_MATRIX.md). |
| Bubble | v9/D1 source import and entry assembly; D1 native current picture and30art bindings; clean mode retains playable menus | Complete art service-loop/H4 and user visual acceptance remain open. See [game](../games/bubble-buddies/GAME.md). |

The root [package check](validation/package-check.json) verifies internal relative-link closure, immutable asset hashes, game file manifests, source/binary privacy and local documentation/catalog references. Source and previews are tracked by Git; large binary resources are excluded from Git and supplied by Release.

Seven small release-tool tests cover verified volume joining/resume, safe extraction, preservation of local edits, installation into an existing checkout, Windows-style text links and first-launch class registration/import failure. The archive builder reads back every member and verifies its SHA256/CRC before publication. Release volumes additionally have independent hashes and a complete-archive hash in `release-files.json`.

Existing video timing and continuity receipts are in [media/validation.json](../media/validation.json). Fixed-step/offline native output is identified explicitly and does not certify real-time FPS. Process material identities and source stages are recorded in each game's process index.
