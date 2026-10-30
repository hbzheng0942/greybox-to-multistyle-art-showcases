# Museum integration matrix

Full museum source environment, with dog and adult skeletal development integration; child/staff skeletal work remains upstream. Static composition is not animation acceptance.

Current package headless integration:37/37 controlled behavior/contact assertions; actual dog pose hashes55 variants and adult109;18 adult skin camera hulls. Native controlled sequence review also passed: seven Skeleton3D / 19 skinned meshes, actual pose changes and native grab/throw/reset. [Videos, replay and limits](process/animation/README.md). Some NPCs partly occlude the fixture camera; no full camera-route or final acceptance claim.

| Component | Fixed754b | Current package | Verification |
|---|---|---|---|
| A01 full museum + native gameplay | included | included | staged full-environment headless/native fixture passed 37 assertions |
| Dog27-bone skinned mesh | absent | included | Controlled headless/native integration passed; actual changing poses and bound physics seen |
| Dog skeletal gait/idle/trot/run/turn/stop/reset | absent | included | Controlled headless/native integration passed; actual changing poses and bound physics seen |
| Adult humanoid52-bone skin + two base motion clips | absent | included | Controlled headless/native integration passed; actual changing poses and bound physics seen |
| Adult retargeting, clap, ragdoll attachment, recovery, reset and camera hulls | absent | included | Controlled headless/native integration passed; actual changing poses and bound physics seen |
| Two child visitors skeletal upgrade | absent | upstream pending | preflight input ready; no produced rig/motion GLB located; upstream production pending |
| Two staff visitors skeletal upgrade | absent | upstream pending | preflight input ready; no produced rig/motion GLB located; upstream production pending |
| 12 detachable mammoth skeleton segments / grab / throw / reset | included | included | Controlled headless/native integration passed; actual changing poses and bound physics seen |
| Mouth anchor and held-object collision | included | included | Controlled headless/native integration passed; actual changing poses and bound physics seen |
| Bear/wolf/taxidermy and other exhibit models | included | included | source rigging plan targets dog+3human appearances, not these static exhibits |

Dog:27-bone actual skin, distance-driven skeletal IK, no embedded clips by design. Adult:52-bone actual skin with two source clips sampled bone by bone; imported AnimationPlayers are removed after extracting permitted bone tracks. Native visitor ragdoll still owns three rigid bodies; mammoth bones are12 physical fragments, not GPU skin animation.

The two child and two staff rig/motion outputs are not yet produced. Their existing procedural cut-mesh motion remains. The package does not claim all10 newly skinned visitors or H4/H5 acceptance. Exact source hashes and private upstream handoff locations are retained outside this public repository.

Latest upstream development now points to adult `18261f4a5bec5e58` v7 local garment/head-neck repair, explicitly pending targeted inner-thigh patch and native replay. This package keeps the separately frozen and captured `3d8c86aed09c7328` + v6 combination; newer development is not assigned the package's verification.
