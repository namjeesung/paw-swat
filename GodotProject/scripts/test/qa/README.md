# PAW S.W.A.T. targeted QA

These development-only tests use the production Player, Level, Zombie, Pickup and pause/restart classes. The Web and Android export presets exclude scripts/test/*, including these scenes and scripts. They never enable --god. Test scenes disable leaderboard requests and write evidence to user:// rather than modifying game resources.

Import after extracting the source:

    godot --headless --path GodotProject --import

Run the damage/shield regression (43 assertions; exit 0 means all passed):

    godot --headless --path GodotProject res://scripts/test/qa/shield_regression.tscn

The test prints individual PASS/FAIL results and the absolute path to user://qa-regression-report.json. Checks include damage in phases 0–5, actual ordinary/boss zombie strikes, existing roll/dash protection, finite hit grace, normal regeneration, five-second shield, rejected refresh/stacking, final-second warning, expiration and renewed damage, pause/resume and slow-motion timing, pickup consumption, twelve-second ground lifetime, bounded 22-second drop opportunities, death, new-run initialization and actual restart from the pause menu state. This is a deterministic logic scenario; it is not evidence that a human can beat a difficulty setting.

Run the deterministic rendered visual scenario on a supported native display:

    godot --rendering-method gl_compatibility --path GodotProject --resolution 1920x1080 res://scripts/test/qa/visual_driver.tscn

It saves seven PNGs to user://qa-evidence. Optional custom output directory:

    godot --rendering-method gl_compatibility --path GodotProject --resolution 1920x1080 res://scripts/test/qa/visual_driver.tscn -- --qa-shots=/absolute/output/directory

The visual scenario disables enemy simulation, places real zombie models and pickups, and calls the production pickup collection method directly to show loot, shield countdown, pause, warning and expiration reliably. Its screenshots demonstrate rendered UI, not ordinary gameplay survival. Normal difficulty regeneration can restore HP during waits; damage statistics separately prove whether a hit was applied.

Run the existing complete menu-to-results bot without permanent immunity:

    godot --headless --path GodotProject -- --autotest --diff=normal

For full-flow screenshots, omit --headless, select a supported native renderer/display and add --shots=/absolute/output/directory. The --autotest and --shots options are project-specific. The original bot's results stage may print duplicate results briefly because multiple pending screenshot/result coroutines complete; the final process exit code is still the stopping condition.

For isolated tests, set XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME to a temporary test directory so test settings and local scores do not affect an existing installation.

Evidence must be labeled by actual engine, renderer, resolution and test mode. Headless timing is not browser/mobile GPU performance. Dummy audio can test stream/bus state but cannot verify audible sound; Safari/iPhone audio must be tested on the intended device.


Additional v0.9 healing checks (whole-package root):

    godot --headless --path GodotProject res://scripts/test/qa/heal_budget_regression.tscn
    godot --headless --path GodotProject res://scripts/test/qa/heal_tip_metrics.tscn

These cover the shared1/2/3/4 spawn budget, one-ground limit, full-HP preservation, capped actual healing, idempotent collection, pause/restart and production-font layout. They do not verify browser audio output.

v0.12.1 horde transition regression (37 assertions):

    godot --headless --path GodotProject res://scripts/test/qa/horde_transition_regression.tscn -- --lite

Verifies staged font-cache preparation, cancellation on scene removal, constant fog-enabled state, original horde onset and density tween, artifact drop, timer and boss gate. Headless frame timings are CPU-only; they are not browser/mobile GPU evidence. transition_probe.tscn measures cold/warm glyph CPU cost only. The full autotest now uses Results.data.success for its exit status instead of merely checking hostage rescue.

Desktop/hybrid input-mode regression:

    node GodotProject/scripts/test/qa/web_input_mode_test.cjs
    godot --headless --path GodotProject res://scripts/test/qa/input_mode_regression.tscn -- --lite

The Web bridge test executes the exact production input-observer script with deterministic DOM mocks (40 assertions): desktop Edge/Chrome, Windows touch-capable hybrids, Android, iPhone, iPad desktop UA, primary coarse/no-hover devices, real touch/mouse/keyboard changes, compatibility-mouse suppression, cancellation, callback ordering and resize. It also verifies that the export preset contains the authoritative Web head unchanged.

The Godot test uses the production HUD, Player, TouchControls and pause menu (33 assertions): desktop ownership, first genuine touch, simultaneous sticks, mouse/keyboard return, stale-action cleanup, resize/orientation, pause-option layout, repeated switching, forced --touch, test-bot ownership and actually freed/queued Enemy targeting references. It never finishes a run or writes a score. These are logic and engine-state tests, not real Edge, browser rendering, touchscreen/controller hardware or audio-output evidence.
