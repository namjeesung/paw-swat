# PAW S.W.A.T. v0.10 → v0.11 native performance comparison

Test date: 2026-10-06 UTC. Corrected matched pair launched serially at11:34:35; both finished by11:36:29. No parallel Godot profiling/stress jobs ran during the pair.

## Result

The candidate significantly reduced native frame time and draw submissions in this bounded cloud scene. It **does not establish a playable FPS target or measured browser/phone improvement**. The cloud native renderer is Mesa llvmpipe (LLVM19.1.7), not a phone GPU. User-reported Web3–5FPS and phone10–20FPS remain unverified on those devices.

| Metric | Inside baseline | Inside candidate | Outside baseline | Outside candidate |
|---|---:|---:|---:|---:|
| Samples |10|16|9|20|
| Median frame, ms |1143.842|689.563|1118.930|568.851|
| Mean frame, ms |1191.038|721.893|1195.983|599.535|
| p95 frame, ms |1537.836|1210.069|1642.316|722.660|
| p99/max frame, ms |1537.836|1210.069|1642.316|844.048|
| Sampled FPS |0.840|1.385|0.836|1.668|
| Mean visible draws |3846.1|2347.9|3672.6|2278.7|
| Mean primitives |545901|543007|540638|540576|
| Mean process monitor, ms |1144.869|662.275|1120.060|581.986|
| Mean physics monitor, ms |8.110|16.807|18.347|10.281|
| Delivered Gatling shots |22|68|20|84|
| Delivered physics steps |132|204|120|252|
| Wall measurement, s |13.445|12.052|12.003|12.480|

Median frame time fell39.7% inside and49.2% outside. Mean visible draw submissions fell39.0%/38.0%, with nearly unchanged primitive counts. Every sampled frame still exceeded100ms. Nearest-rank p95/p99 are unstable with such small sample counts; they are descriptive, not repeat-run confidence bounds.

## Matched setup and important differences

- Godot4.6.3, Linux native OpenGL Compatibility, API4.5 Core Mesa25.0.7. Same launcher resolution1180×812. All four saved screenshots are1180×812; logical canvas size reported1920×1321.
- Same seed20261006, actual Level/Zombie/Player classes, fixed37 living actors (34normal,3bosses), Insane difficulty, actual Gatling with1400initial ammo. Bandit simulation disabled, hostage removed, staff door physically breached before measurements. No network submissions.
- Initial population is reset using the same ring positions projected on the corresponding production nav maps. Player is fixed inside at(0,0,5.3), then outside at(0,0,11). Live AI, collisions, shooting, hit effects and damage remain enabled.
- Finite10000HP actors keep population stable. This is a deterministic development performance fixture, not normal-play or survivability acceptance.
- Four wall-clock seconds warmup followed by at least12wall-clock seconds sampling per phase. First interval is excluded at the process-frame boundary. Screenshot readback happens after each measured phase.
- Baseline has120Hz physics and4×MSAA. Candidate intentionally changes to60Hz and disables MSAA. Candidate requested FXAA, but Godot explicitly warns screen-space AA is unavailable in Compatibility; **working FXAA was not observed**.
- Both final reports say texture size726×500 and scale1.0, conflicting with captured1180×812 images. Treat internal3D buffer metadata as unverified. This pair does not prove the921600pixel-budget behavior or high-DPI Web behavior.
- Severe render-frame stalls hit the engine's12physics-steps-per-frame catch-up cap. Consequently candidate delivered1.55×/2.10× more physical steps and3.09×/4.20× more shots, and crowd positions/damage evolved further. Equal seed/population/window is not equal simulated workload or camera image. Candidate AI/path recovery also differs. This is a whole-candidate performance comparison, not isolated causal attribution to any one patch.

## Hotspot evidence

Actual frame intervals and draw counts support render-path cost as the primary optimization target in this cloud fixture. Wrapped Zombie logic cost totals206/283ms baseline and471/373ms candidate across~12s phases. Nav-direction totals14/33ms and51/31ms respectively; separation totals82/102ms and161/151ms. These counts increase with delivered simulation; raw aggregate growth is not proof of regression. Level `_process` totals remain below3.1ms per entire phase. The process monitor includes engine/render-related work and is not an isolated script timer. No GPU timestamp or main-thread stack profile was captured.

New-node observations show useful effect reuse despite the higher fire count:

| Observation | Inside baseline→candidate | Outside baseline→candidate |
|---|---:|---:|
| Nodes added |132→188|124→169|
| Nodes per100shots |600→276.5|620→201.2|
| Mesh nodes per100shots |236.4→129.4|235→100|
| Particle nodes added |39→10|52→1|
| New light nodes |5→0|5→0|
| Peak reported video bytes |95,238,461→64,809,679|95,169,643→64,739,603|

The fixture counts nodes when they enter the tree and first-seen mesh/material IDs attached to those nodes. It does not count every Resource allocation. Both variants' new mesh/material ID counts were zero during measurement after warmup; this is not a global zero-allocation claim. Particle/hit distributions differ as AI advances, so per-shot values are descriptive. Shadow render-info returns0 in both runs, although production directional shadows remain visible/configured; do not read that counter as proof that shadows cost nothing.

The measured draw reduction with stable triangle counts supports batching rigid mesh parts and removing duplicate draw work. Removing4×MSAA and pool reuse also reduce render/resource pressure. Exact contribution of each change was not isolated. Further device acceptance should use the actual browser/device renderer, production Web resolution/DPR, matched gameplay and repeated frametime captures; this report alone cannot guarantee desktop or phone FPS.

## Visual and integrity checks

All four native screenshots were opened. Map, HUD, player, Gatling, small zombies and bosses rendered; candidate screenshots show genuine damage overlays and denser progressed crowd positions. Pixel equality is not expected for live simulations. No claim of identical effects visibility or working anti-aliasing is made.

Both frozen source manifests were independently verified after the pair:229files each, zero SHA256 mismatches. Baseline non-cache source is6,728,068bytes; candidate6,748,552bytes. Their only changed files are project.godot, Bullet, Zombie, CharModel, Fx, Models, Level and Pickup. Shared profiling script files are byte-identical in both projects. Complete hashes are in baseline-source-manifest.json and candidate-source-manifest.json; candidate Fx is3e9c6b60ece5bac8bc174f2b74cbc482dca41e4e2c410d10673997c65a6e7506.

Both phases and DONE markers are present in each raw log/report. Preserve warnings: driver cannot change V-Sync, ALSA fails and uses dummy audio, nav agent height voxel rounding, unsupported candidate screen-space AA, and inherited two static ImageTexture/GL texture shutdown leaks (8520bytes each). No audible-audio or clean-shutdown claim.

## Reproduce and artifacts

From the perf-v011 directory, run `bash harness/launch_baseline_native.sh` then `bash harness/launch_candidate_native.sh` through the supported native GUI terminal. Do not use headless mode for performance measurement, and do not run other stress jobs in parallel. Launchers contain the environment's resolved project path; relocate it when replaying elsewhere. `python3 harness/summarize_native.py` recomputes saved-report statistics without launching Godot.

- Corrected authoritative pair: reports/baseline-gatling-native.json, reports/candidate-native.json; corresponding logs/*.log and reports/*-shots/*.png
- Machine-readable statistics: reports/native-comparison.json
- Frozen source and hash manifests: baseline-project, candidate-project; reports/*-source-manifest.json
- Shared development-only harness: harness/*.gd, dense_native_profile.tscn; never include it in the exported release
- Earlier reports/baseline-native.json is a preliminary rifle probe mistakenly labelled Gatling in its old fixture string. It was retained honestly and is excluded from this final comparison.

## Later correction, validated separately

After this benchmark, final Level changed the render-budget input to root `Window.size` and disabled requested FXAA for Compatibility. A separate headless actual-class property suite passed77checks across six sizes, including unchanged HUD/camera/input mappings. See quality-policy-checks.md and its raw JSON/log. This does not change the benchmark above or establish a rendered pixel-cap performance benefit; no new native performance variant was run.
