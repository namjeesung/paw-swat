# PAW v0.12.1 Toy ranking integration

## Runtime behavior

- Web, with no explicit independent-server URL: Toy SDK public ranking; it must run inside the real Toy platform host. A copied ZIP/localhost is not proof of platform integration.
- Native APK, no server URL: local records only. No Bilibili identity is invented and no Toy iframe support is claimed.
- A deliberately configured `leaderboard.cfg` URL retains the optional independent-server path. Its UI says 独立服务器榜. No server was deployed in this work.
- Local records remain available regardless of public submission success. Existing old local runs are not automatically uploaded. One successful completion invokes one score submission; reopening results is deduplicated. A failed result offers explicit retry/query. Outstanding platform submissions share one Promise so a login/consent dialog cannot cause repeated writes.
- Profiles use the platform nickname and avatar. Public rank rows contain nickname/avatar/rank/score, **no UID or Toy open ID**. Own-row highlighting uses the separately confirmed own rank, never nickname equality. Profile IDs are neither displayed nor logged. No cloud storage API is called by this integration.
- Cache until user refreshes; no network polling. Error 307044 establishes an exponential cooldown before manual retry. SDK failures never create fake public rows or appear as success.

## Persistent board protocol

Board 1 = easy, 2 = normal, 3 = hard, 4 = insane; board 5 is unused. Period = `all`.

`score = 16777215 - time_ms`, inverse `time_ms = 16777215 - score`.

Times must be integer milliseconds in 1..16777215. Encoded score is 0..16777214, within the SDK signed range. Faster times have larger scores; platform max-score retention therefore keeps the fastest run. Do not change this encoding or reuse these boards for another metric without a migration/season decision. The displayed time is decoded milliseconds, not the encoded score.

The SDK protects account association and max-score persistence, but client-reported completion is **not** server-authoritative anti-cheat. This integration is unsuitable for prize-bearing competition without additional validation.

## Verified official sources (read 2026-10-06)

- https://github.com/bilibili/toy/blob/main/skills/toy/SKILL.md
- https://github.com/bilibili/toy/blob/main/skills/toy/references/content-checklist.md (§7)
- https://www.bilibili.com/toy/publish/sdk/skill
- Official documentation asset linked by the page: https://s1.hdslb.com/bfs/static/toy/app/publish/assets/index-B3T-BCTU.js
- Official runtime: https://s1.hdslb.com/bfs/seed/toy/app/sdk/toy-sdk.js

Confirmed SDK contracts:

- submitScore({board, score}) -> {score}; returned score is the retained all-time maximum. Must be logged in; first submission uses the platform's own user-data confirmation.
- getRankList({board, period, limit}) -> direct array of {rank, score, nickname, avatar}; guest-readable; ranks unique, ties ordered by first achievement.
- getMyRank({board, period}) -> {ranked, rank, score}; logged-in; check ranked, never infer from score.
- Board 1..5 is confirmed by current prose and runtime validation, despite stale 1..3 comments in one bundled type declaration.
- Profile reference documents direct nickname/avatar/toyOpenId. Current runtime also normalizes an HTTP data wrapper to data.uname/data.face/data.toyOpenId. Both observed shapes are handled; open ID discarded.

## Validation and remaining acceptance

- `node docs/v0.12.1/QA/test_toy_bridge.cjs`: 36 offline mock assertions pass. Covers all four boards, reversible ordering/bounds, strict response schema, retained-score confirmation, no public IDs, caching/manual refresh, login failure, rate cooldown and in-flight submission deduplication.
- Godot 4.6.3 headless editor import: no parse errors.
- `godot --headless --path GodotProject res://scripts/test/qa/ranking_regression.tscn`: 16 assertions pass for native local states and explicitly mocked Toy UI/login failure. Test scenes are excluded by release presets. Godot emitted shutdown resource-in-use warnings from active UI/audio animation during the short fixture run; assertions completed successfully.
- Existing audio/input scripts in the web head were preserved. `web/sync_head_include.py` regenerates the adapter block and export preset without changing those scripts.
- No live Toy account login, score submission, cloud save, publishing or two-real-account check was performed. Two different logged-in accounts must each complete the same difficulty on the uploaded version and see both results. Also check guest read, refused consent, real error recovery, reload/account switch, and Android explicitly local-only behavior.
