# v0.11 integrated loot regression

Result: 269/269 checks passed, all four engine runs exited 0. No production files were edited. The tested Level, Pickup, Enemy, Player and Zombie are byte-identical to the current v011 production candidate; hashes are recorded in source-manifest.json.

## Runs
- New integrated loot: 46/46
- Existing healing-budget regression: 110/110
- Existing shield regression: 43/43
- Existing all-boss victory regression: 70/70

All logs contain zero runtime script errors and zero engine ERROR entries. The unchanged shield fixture still logs an ObjectDB retained-instance warning at shutdown; its 43 functional checks pass. This warning was not suppressed and the production code was not changed to make a test pass.

## Verified integrated loot
- Every source uses the central two-successful-grenade-crate budget, with one grenade crate on ground
- A burst of real Enemy._go_down calls produces one crate; an overlapping air supply cannot double it
- First successful grenade opportunity is guaranteed. A seeded 10,000-roll sample of later opportunities verifies the intended rare 12% implementation; rolling itself never spends budget
- Air supply begins after the 24s interval and shares the same budget
- Ground-cap, full-inventory, finished and dead-player rejections do not spend successful-spawn budgets
- Collection and expiry never refund budgets; all sources stop at two even after grenades are used
- Full grenade inventory leaves an existing crate on the ground; partial inventory caps at three
- Optional weapons share a three-successful-spawn cap and one-ground limit
- Four optional pickup types can coexist; extra optional requests are rejected without spending
- Story-critical gatling spawns even when optional ground capacity is full, spends no optional-weapon budget, and has no TTL
- Grenade20s / optional weapon30s / shield12s boundary checks pass, remove pickup-array entries at expiry and free the nodes
- Heal and story gatling remain persistent
- Ground TTL starts after landing, pauses with the game, and remains actual non-paused time under slow motion
- Actual Game.goto restart clears loot budgets and ground items and captures the new difficulty

## Legacy behavior preserved
The existing 110 healing checks retain the 1/2/3/4 difficulty budgets, one-ground rule, full-HP leave behavior, capped actual healing/feedback, shared-source budgets, pause and actual restart semantics. The 43 shield checks retain damage/protection, five-second duration, no refresh/stack, pause/slowmo, ground expiry, death and restart behavior. All 70 victory checks retain required boss counts, real-death accounting, pending spawn retry, timer/rescue/alive-player gates, no fake finale boss kills and exactly-once results. No behavior assertions were edited for this candidate.

## Intentional changes versus v0.10
v0.10 used two grenade crates on ground, a 14s air interval, 30% later enemy rolls and a roll-side counter. v0.11 uses one ground crate, 24s air interval, 12% later rolls and successful-spawn accounting shared by every source. New optional-weapon/total optional caps and grenade/weapon TTL are intentional throttling changes. Shield TTL, persistent healing and persistent story gatling are preserved. The source v0.10 Level/Pickup remain intact; only an isolated copy was tested.

## Scope
Actual production classes were exercised in a headless copied project at fixed-fps 60. Other actor simulation was frozen where needed to isolate loot; real pause/slowmo/restart were used. This is functional evidence, not FPS, audible audio, rendered screenshot, full playthrough or real-phone evidence. Online.server_url is blank.

Fixture-only changes: report output paths, and a disabled-by-default Game result recorder used only by the victory fixture. The other three fixtures use actual Game.goto for restart. No rank results were opened or uploaded.

## Evidence and reproduction
Full reports: loot-report.json, heal-budget-regression-report.json, shield-regression-report.json and victory-report.json
Logs: ../logs/loot-run.log, heal-run.log, shield-run.log and victory-run.log
Exit codes: legacy-exit-codes.txt (legacy three) and successful loot-run completion
Source hashes: source-manifest.json
New harness: ../harness/loot_fixture.gd and loot_fixture.tscn

From the workspace root:

    BASE="$PWD/paw-swat-work/v011/loot-qa"
    export HOME="$BASE/runtime/home" XDG_CACHE_HOME="$BASE/runtime/cache" XDG_CONFIG_HOME="$BASE/runtime/config" XDG_DATA_HOME="$BASE/runtime/data"
    godot --headless --path "$BASE/project" --fixed-fps 60 res://qa/loot_fixture.tscn -- --report="$BASE/evidence/loot-report.json"
    godot --headless --path "$BASE/project" --fixed-fps 60 res://qa/heal_budget_regression.tscn
    godot --headless --path "$BASE/project" --fixed-fps 60 res://qa/shield_regression.tscn
    godot --headless --path "$BASE/project" --fixed-fps 60 res://qa/victory_fixture.tscn -- --report="$BASE/evidence/victory-report.json"
