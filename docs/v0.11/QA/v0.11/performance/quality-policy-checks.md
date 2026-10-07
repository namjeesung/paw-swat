# Post-benchmark quality policy validation

2026-10-06 UTC. **77 actual-class property/mapping checks passed, exit0.** This is a bounded headless state/algorithm test, not a new performance benchmark. No GUI or browser was used, and no rendered framebuffer or phone behavior was measured.

## Correction tested

The final Level policy calculates the921600pixel budget from root `Window.size`, instead of `ViewportTexture` size metadata. It requests FXAA only outside OpenGL Compatibility. Project default and Web screen-space AA are0; the mobile override is1. MSAA is disabled.

The production Level, HUD and GameCamera are instantiated in a fresh development-only source copy. The scene is disabled for simulation, while the actual `_apply_render_budget()` method is called after setting representative window sizes. This validates real class properties rather than a duplicate implementation. Root window sizes are assigned test inputs, not observed browser/device screens.

| Root Window.size | Actual scale property | Recorded budgeted pixels |
|---|---:|---:|
|640×360|1.000000|230400|
|1180×812|0.980736|921600|
|1920×1080|0.666667|921600|
|2560×1440|0.500000|921600|
|3840×2160|0.333333|921600|
|720×1600|0.894427|921600|

For each size, checks establish that window size is retained, scale equals `min(1,sqrt(921600/(width×height)))`, `_render_profile.viewport` uses those root window pixels, and recorded pixel count is positive and bounded. Renderer reports `gl_compatibility`; actual MSAA and screen-AA state are both disabled. The non-Compatibility/mobile FXAA runtime branch was not executed; its project override was verified only.

## HUD, camera and input invariants

Before/after applying only the quality policy at each given size, all of these remain unchanged:

- Logical viewport rectangle, canvas transform and stretch transform
- Actual HUD Control positions, sizes, scales and global transforms
- Production camera projection matrix and screen-to-world ray origin/direction at a chosen logical screen point
- Production camera screen-to-ground movement direction and Level mouse-to-height-plane world mapping

Changing window size naturally changes logical aspect dimensions. The invariant is that applying the3D quality policy does not further change them. For example,1180×812 reports1920×1321 logical canvas;720×1600 reports1920×4266. There was no native mouse/touch injection or rendered input acceptance in this test.

## Relationship to the native benchmark

This policy correction occurred **after** the native comparison. Frozen baseline/candidate benchmark projects and raw results were not changed or rerun. Their39.7%/49.2% median frame-time reductions and~38–39% draw reductions describe the earlier matched pair only. Neither that pair nor this headless property test proves the corrected pixel cap's rendered FPS benefit. Both earlier screenshot images were1180×812 despite final texture metadata726×500; the corrected policy avoids using that conflicting metadata.

## Integrity and evidence

The isolated post-correction copy has216non-cache files excluding QA folders, with zero manifest hash mismatches. Level SHA256:8f25bebb29162f7b30c6496542b099533bef31a540bbb6ffe682385e07b01539. Project SHA256:45f6d9b3af2793d72d5029e6bda06057d9231c81b1cdfa5182b0b3faaaa8911b. This manifest's QA exclusion differs from the older229-file benchmark manifests.

Evidence: `quality-policy-checks.json`, `../logs/quality-policy-checks.log`, `quality-policy-source-manifest.json`; development harness in `../harness/quality_policy.gd` and corresponding scene. Run the scene in `quality-policy-project` with Godot `--headless --rendering-method gl_compatibility`, passing `--report=<output>` after `--`. Reuse a separate XDG runtime folder.

Raw log retains nav agent-height voxel rounding and one ObjectDB/resource exit leak from early fixture shutdown. No script errors or failed assertions occurred. Production source was not changed by this QA task.
