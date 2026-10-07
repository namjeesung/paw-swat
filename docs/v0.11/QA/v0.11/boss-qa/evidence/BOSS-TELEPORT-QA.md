# v0.11 Boss stuck-recovery QA

Result: 33/33 functional checks passed; exit 0. Tested production Zombie SHA256: 5b6a54a74e1dc2c36ae0bba5663267126c0e5c4661f2ed8532cfb6cde1d8376c. The tested Zombie file is byte-identical to v011/project. Final verbose log contains zero runtime script errors and zero shutdown retained-resource/ObjectDB warnings after the fixture drains completion timers.

## Changed module
Only production scripts/actors/zombie.gd was edited by this worker. Level and Pickup ownership remain with the parent.

- Boss lack of net displacement is tracked over a rolling 2.5-second horizon, including doorway oscillation; an earlier forced repath comes first
- Persistent landing ring/text and smoke warn for 1.0 game second before the jump
- Landing is 2–3m from the current player, on the dedicated boss map; exact radius 0.7 / height 2.2 capsule, center +1.16m, is checked against world, cover, player, enemies and hostage
- Destination/player position/map route are revalidated at expiry; no safe destination cancels/repaths rather than forcing a jump
- Successful jumps have an 8s cooldown and 0.6s attack recovery; HP, speed, normal attack timing and damage vulnerability otherwise stay unchanged
- Attack windup, stun, rise, pause, player death, boss death and level finish cannot trigger recovery; pending warnings cancel on interruptions and actor exit
- Ordinary followers get bounded stalled-waypoint repaths without teleport; initial path requests are staggered while recurring cadence stays unchanged

## Actual physics evidence
- Physically boxed-in boss warns at 2.65s, waits the full warning, and lands 2.60m from player with no overlap
- A moving player invalidates the warning destination and the jump cancels; a later newly warned destination succeeds
- A wall added during the warning invalidates the jump and it cancels
- Closed player enclosure yields repeated route retries and zero unsafe jumps
- Oscillation covers 2.26m accumulated travel but only 0.30m net displacement and is detected
- Second jump is blocked through seven seconds; its next warning starts about 8.07s after the first landing and lasts a full second
- Deliberate hits still damage the boss during warning and recovery; attacks resume after the recovery
- Guard, pause, cancellation, actor reset, and ordinary-stall scenarios pass
- Normal fixed-target doorway crossing walks 6.58m with zero teleport
- Continuously moving Player CharacterBody3D walks about 44.1m; boss pursues about 26.5m and crosses inside/outside doorway, with zero false teleports or unsafe landings

## Scope and limitations
Live CharacterBody3D movement and collision run at the Web/mobile 60Hz setting in headless Godot. Other AI is frozen to isolate the boss. The continuous-player fixture owns movement input and applies production knock damping; time effects are reset in that pursuit case to keep the controlled input cadence. This is not FPS, real-phone, full gameplay difficulty or rendered screenshot evidence. Marker child presence and lifetime are checked; final appearance remains visual QA.

A first moving-player harness attempt omitted Player's normal knock damping while its AI was disabled. That fixture-only failure and log are retained as teleport-report-moving-fixture-knock-bug.json and teleport-run-moving-fixture-knock-bug.log; the corrected final run passes. A short initial run ended before all detached completion timers drained and logged retained resources. Final verbose run drains timers and shuts down cleanly.

## Reproduce
    BASE="$PWD/paw-swat-work/v011/boss-qa"
    HOME="$BASE/runtime/home" XDG_CACHE_HOME="$BASE/runtime/cache" XDG_CONFIG_HOME="$BASE/runtime/config" XDG_DATA_HOME="$BASE/runtime/data" godot --headless --verbose --path "$BASE/project" --fixed-fps 60 res://qa/teleport_fixture.tscn -- --report="$BASE/evidence/teleport-report.json"

Detailed results: evidence/teleport-report.json
Final engine log: logs/teleport-run.log
Hashes/scope manifest: evidence/source-manifest.json
External harness: harness/teleport_fixture.gd and harness/teleport_fixture.tscn
