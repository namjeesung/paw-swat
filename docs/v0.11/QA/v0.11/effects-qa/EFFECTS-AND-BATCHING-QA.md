# PAW S.W.A.T. v0.11 effects and Zombie batching QA

## Scope

Production edits are limited to `scripts/core/fx.gd`, `scripts/actors/bullet.gd`, `scripts/core/models.gd`, and `scripts/core/char_model.gd`. The original source at `paw-swat-work/source/godot-project` was not edited. All harnesses in this directory are external development QA and must not become game entry points.

This is structural, geometry, collision, and lifecycle evidence. Headless runs are **not** frame-rate/device-performance or visual acceptance. Matched native frame/draw-call measurements and actual screenshots are owned by the separate profiling pass.

## Changes

- Parent-local pools reuse spark/dust emitters, muzzle quads/lights, rings, simple two-part ghosts, labels and shells. Caps: sparks64, dust48, muzzle16, lights8, rings24, ghosts16, damage labels48, notices32, shells36. Cosmetic overload reuses the oldest slot; it never removes a projectile, changes damage, or limits a combat target.
- Original particle counts, colors, mesh geometry and durations remain. Notice labels have a separate budget. Muzzle/ring/ghost updates retain original interpolation curves and durations without creating per-effect Tweens. Label popups retain their original animation.
- Cosmetic spark/dust/ghost/rocket-tip shadow flags are off. The original character geometry, colors, outline style, animation parents and ordinary hit feedback remain.
- Bullet uses one ray-query resource per projectile, updated with the same positions, masks and exclusions. Rockets share their immutable base/outline material; other glow materials were already cached in v0.10.
- Zombie-only rigid parts with the same animated parent and same per-character material are combined into cached geometry. Only unit-scale parts are batched. Nonuniform-scaled body/belly/tongue pieces retain their original mesh nodes to preserve shading and outline extrusion. Feet, tail, head/body parents and cuffs remain independently animated/controlled. Cache entries contain geometry only, never character materials.
- Popup Tween references are cleared at release and killed/cleared at pool exit, preventing slot/Tween retention cycles. No static parent-ID registry exists; each pool is a child of its effect owner.

## Structural stress: 100 calls in a single burst per family

| Family | Source | Candidate |
| --- | ---: | ---: |
| Muzzle nodes including root/light | 201 | 26 |
| Muzzle lights | 100 | 8 |
| Spark emitters | 100 | 64 |
| Dust emitters | 100 | 48 |
| Ghost nodes including root | 301 | 50 |
| Ghost mesh instances | 200 | 32 |
| Ring mesh instances/materials | 100/100 | 24/24 |
| Ring unique geometry resources | 100 | 1 |
| Damage labels | 100 | 48 |
| Notice labels | 100 | 32 |
| Rocket unique materials across100 rockets | 201 | 3 |

Candidate node counts include one extra pool node. Every instance in this table is below or at a documented cap. Counts are measured scene/resource structure, not actual GPU draw-call counters. Source spark/dust/ghost geometry had shadow flags on (100/100/200); candidate flags are off. Rocket tip flags100→0. Transparency may already exclude some of these from shadow rendering, so flag counts are not claimed as measured shadow draws.

`baseline-counts.json` and `candidate-counts.json` include full counts. Fx-family figures remain applicable after the lifecycle fix; the separate geometry comparison is the authoritative final Zombie count.

## Authored Zombie geometry and animation

- Normal Zombie: visible meshes25→13; visible base+outline geometry passes42→24; triangles8,788→8,788
- Boss Zombie: visible meshes31→14; visible base+outline geometry passes54→26; triangles8,936→8,936
- Hidden cuff geometry is included in triangle totals, excluded from visible-mesh/pass figures
- Triangle winding/counts/material groups, colors, toon/rim settings, outline widths, crown geometry, head/body/feet/tail transforms and rest/animated AABBs pass
- Maximum position difference1.192×10⁻⁷m; UV difference0; AABB difference≤1.192×10⁻⁷m; outline vertex difference≤2.608×10⁻⁶m
- Maximum normal-component difference1.085×10⁻⁴; maximum angular normal difference0.006709°. Normals are not claimed as bit-identical: ArrayMesh read-back uses Godot's uint16 octahedral normal representation. Strict1e-5 position/UV/outline thresholds remain; normal tolerance is separately0.0002 with its rationale recorded
- Separate instances retain independent flash and xray/outline materials

Primary implementation references: [SurfaceTool4.6 implementation](https://github.com/godotengine/godot/blob/4.6-stable/scene/resources/surface_tool.cpp#L951-L989) and [Godot4.6 normal packing](https://github.com/godotengine/godot/blob/4.6-stable/servers/rendering/rendering_server.cpp#L557-L574). SurfaceTool transforms normals with the transform basis; this is why nonuniform-scaled pieces are excluded from batching. No normals are regenerated and no faces are simplified.

`geometry-comparison.json` records all checks, tolerances and counts. The original/candidate raw triangle samples are in `*-geometry.json`. Six below-cap Fx signatures (spark, dust, muzzle, ring, ghost, popup) have identical appearance/settings/texture hashes in `signature-comparison.json`.

## Combat correctness

Both source and candidate pass10 deterministic tests using the actual Bullet implementation and recording collision bodies:

1. Shooter exclusion and exact1.25 damage
2. Near low cover (<1.8m) passthrough
3. Distant low cover blocks
4. World walls block
5. Pierce2 hits exactly three distinct targets
6. Safe bullets skip hostages
7. Unsafe bullets hit hostages and stop
8. Invulnerable target passthrough
9. Enemy mask ignores enemies and hits player
10. Rocket range expiry retains explosion radius3.4 and damage1.25

See `*-collision.json` and logs. These are collision-unit regressions, not complete gameplay/difficulty acceptance.

## Lifecycle

All eight Fx families pass pause, expiry and reuse checks. Repeated bursts create no additional effect nodes after the pool is warm. Candidate10-parent teardown/restart cycles alternate active-Tween teardown with completed-Tween teardown:

- Every family stays within its cap
- Parent, pool and RefCounted slot weak references become invalid after teardown
- Completed popups drop Tween references
- Shell count returns to0 after each exit
- After warmup, object/node/resource/orphan counters plateau: objects1768, nodes48, resources95, orphan nodes0
- No runtime errors or shutdown leaks are logged

See `candidate-teardown.json`/`.log`. The initial weak-slot assertion retained its own Array iterator in the test function; moving inspection into a function-scoped helper removed that test-induced retention. The production lifecycle fix remained unchanged.

## Reproduction and limitations

Engine used: Godot4.6.3.stable.official.7d41c59c4, compatible with this4.x project. Use the external bootstrap with the original/candidate project as `--path`. `run_qa.sh <source-project> <candidate-project>` runs the structural/signature/collision/geometry/lifecycle checks serially. Do not run these while collecting an isolated native performance sample.

Do not ship `runtime/` cache/config/data directories or modification scratch scripts as gameplay assets. Physical Windows/macOS/Android/iOS/Web device performance is not established by this QA. Actual corrected native Gatling inside/outside screenshots were inspected for both versions: silhouettes, crown/eyes/ears/stitches/arms/feet/tails, outline language, hit flashes and damage labels remain intact, with no obvious missing batched parts or material errors. These active-white-flash frames do not establish pixel-identical static palettes; geometry/material signatures cover that. See `native-visual-review.json`. Matched renderer measurements and full integration remain owned by the main profiling pass.
