> 历史记录；当前版本以根目录README-中文.md和Docs/QA/v0.11为准。

> 历史 v0.9 记录；当前 v0.10 的包结构与复现入口以根目录 README-中文.md 为准。

# Final exported-pack regression

This portable SceneTree bootstrap loads only an external Node test driver. Production classes and resources come from the supplied Web/index.pck. It does not load the browser/WASM runtime and cannot verify audible output.

From the extracted package root, with Godot 4.6.3 installed:

    godot --headless --main-pack Web/index.pck --script "$PWD/Docs/QA/packed_qa_driver.gd" -- --lb= "--qa-harness=$(pwd)/GodotProject/scripts/test/qa/heal_budget_regression.gd"

Expected: 110 checks, no failures, exit0. The existing shield suite:

    godot --headless --main-pack Web/index.pck --script "$PWD/Docs/QA/packed_qa_driver.gd" -- --lb= "--qa-harness=$(pwd)/GodotProject/scripts/test/qa/shield_regression.gd"

Expected:43 checks, no failures, exit0, with the previously documented single SceneTreeTimer shutdown warning. Use independent XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME directories to avoid affecting existing local settings and scores.

Test reports are written to user://. The external Node harnesses disable server requests; --lb= also explicitly blanks the configured leaderboard destination. These tests are development tools and should remain outside release exports.
