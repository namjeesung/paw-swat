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
