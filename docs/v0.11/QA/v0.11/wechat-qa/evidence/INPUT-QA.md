# PAW S.W.A.T. v0.11 focused Web input repair

## Result and limits

- Final Linux headless native input regression: 41 checks, 14 failures before, 0 after, explicit 2400×1080 viewport
- Initial reproduction retained separately: 30 checks, 7 failures before, 0 after (inherited default square headless viewport)
- Node DOM mocks executing the exact shipped Godot 4.6.3 Web touch handler plus the appended candidate observer: 30 checks, 0 failures
- Final native run has no script/runtime errors. The baseline navigation bake precision warning is unrelated to input
- These are synthetic native events and DOM mocks, not a running Chromium/WebView, real WeChat device, hardware, touch feel, audio-output, or full v0.11 integration pass
- No alternative socket/browser route was attempted after the parent reported that route denied

## Concrete faults and repairs

1. Movement and firing incorrectly used negative contact IDs as idle state. Touch.identifier is a signed long; the exported Godot handler writes it directly to i32. Separate active flags now accept extreme negative IDs and the former -1 sentinel
2. Reusing one contact ID after a lost end could make one finger own both movement and firing. A new press detaches only that ID's previous action before assigning its new zone. Late releases belonging to different old IDs preserve the current owners
3. System cancel produced a release-fire burst, and pause/focus/resize retained cached movement/firing. Cancel now releases only its own zone without firing. Full lifecycle releases clear cached move/shoot/aim/just actions immediately
4. The shipped Web runtime registers touchcancel as ordinary touchend. A small passive canvas capture observer preserves the terminal kind and active contact list. It keeps buffered cancel kinds ordered even when the same ID starts again in the same frame
5. Missing old ends are reconciled from targetTouches on the next DOM event. If a host omits targetTouches, changed-contact tracking remains valid rather than interpreting omission as zero contacts
6. Hidden controls accepted input, held hidden-button owners remained, and the invisible non-rifle reload location intercepted touches. Input and hit-testing now use the relevant visibility rules
7. An already-visible portrait overlay did not pause a newly entered level. Rotation checks now also check the current level; portrait controls cannot drive through the overlay
8. Touch capability detection now also checks maxTouchPoints/msMaxTouchPoints for desktop-style mobile UAs. Non-finite press/drag coordinates cannot poison movement

## Safety and performance boundaries

- Existing audio/style head prefix preserved byte-for-byte. No audio, renderer, joystick UI, or gameplay model change
- Observer listeners exist only on canvas for touch events and are capture/passive. No stopPropagation, preventDefault, document touchmove/dblclick trap, input replay, or synthetic mouse/touch event is added
- The engine's own genuine touch callbacks remain the main input path
- One integer bridge revision read per rendered frame; owner checks only after a touch/lifecycle revision. No per-frame JSON/global state dump
- Observer state is bounded and resets with controller session/pause/visibility/resize releases. Blur, pagehide, and hidden-document observation cancel live contacts
- The tests use a baseline Level/Player with exact candidate controller, pause, and Game input/rotation files. The parent owns final combined v0.11 build and integration QA

## Evidence and reproduction

- `native-final-before-report.json`, `native-final-after-report.json`: all 41 checks and outcomes
- `web-runtime-dom-mock-report.json`: all 30 DOM/runtime mock checks
- `input-final-source-manifest.json`: candidate file and shipped runtime SHA-256 hashes
- `head-preset-sync.txt`, `audio-head-unchanged.txt`: export/head invariants
- External checkpoints and full test logs are retained under this QA directory, not added to production scripts

Run the native scene from the isolated QA project with Godot 4.6.3:

`godot --headless --path candidate-project --resolution 2400x1080 res://qa/native_input_state.tscn`

Run the handler/observer DOM mocks:

`node harness/web_runtime_dom_mock.cjs`

Primary evidence: [W3C Touch Events specification](https://www.w3.org/TR/touch-events/#widl-Touch-identifier), and the actual shipped `build/v010-web/index.js` handlers `_godot_js_input_touch_cb`, `_godot_js_display_touchscreen_is_available`, and `GodotInput.computePosition`.

Signed-ID support is a demonstrated standards-compatible source failure and repair. It is not evidence that a particular WeChat device actually used a negative ID or that this is that device's sole root cause.
