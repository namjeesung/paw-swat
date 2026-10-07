> 历史记录；当前版本以根目录README-中文.md和Docs/QA/v0.11为准。

# Boss victory-rule regression

Result: 63/63 checks passed, exit code 0, Godot 4.6.3, headless fixed-fps 60, 8.018 wall seconds.

## Scope
The fixture executes the production Level, actual boss spawning, and actual Zombie.take_hit deaths. It freezes actor physics to isolate mission rules. A fixture-copy Game.goto records results instead of opening the results screen or saving/uploading ranks. Spawn failure is injected in a Level subclass; cleanup spy actors record finale_pop requests without taking part in live combat. No production files were edited.

This is mission-rule evidence, not a doorway physics test, whole-game victory playthrough, difficulty assessment, screenshot or phone test.

## Verified
- Required boss counts are 1 / 1 / 2 / 3 across easy / normal / hard / insane
- Failed boss spawns remain pending and retry, including after deadline; skipped schedules spawn every due boss
- Timer caps at 60; ordinary spawn attempts and timed supplies stop at deadline
- Expired HUD displays remaining boss count and 00 seconds
- Live bosses remain alive and block finale and results even after the finale timeline would have elapsed
- Partial boss defeat cannot finish; real deaths count once even with repeated callbacks
- Early defeat still waits for the timer; rescue and living-player prerequisites remain enforced
- Valid completion starts once, sends success results exactly once, and never calls any boss finale_pop
- Ordinary finale cleanup is called; no boss death is manufactured by cleanup
- Player death before completion locks victory and sends one failure result
- Pause holds wave/counts, resume advances without resetting, and new Level resets boss state

## Observed issue
Repeated on_zombie_killed(dead_boss) does not increase the defeated count again, but on this snapshot still adds 500 score and repeats normal kill/effect/drop side effects. This is not a victory-gate failure. Recommended correction: return early for an already recorded boss death ID before any score, HUD, reward or erase side effects. The production Zombie._die itself already guards ordinary duplicate death calls.

## Warnings
Boss agent_height=2.2 is rounded up to the cell_height=0.25 voxel grid and Godot warns about the precision loss. This is expected and not a failed check. No runtime script errors appeared in the run log.

## Reproduce
From the workspace root, run the isolated copied project (not the main source):

    BASE="$PWD/paw-swat-work/boss-qa/victory-qa"
    HOME="$BASE/runtime/home" XDG_CACHE_HOME="$BASE/runtime/cache" XDG_CONFIG_HOME="$BASE/runtime/config" XDG_DATA_HOME="$BASE/runtime/data" godot --headless --path "$BASE/project" --fixed-fps 60 res://qa/victory_fixture.tscn -- --report="$BASE/evidence/victory-report.json"

Harness source: harness/victory_fixture.gd and harness/victory_fixture.tscn
Detailed checks: evidence/victory-report.json
Engine log: logs/victory-run.log
Production snapshot hashes: evidence/source-snapshot.json
