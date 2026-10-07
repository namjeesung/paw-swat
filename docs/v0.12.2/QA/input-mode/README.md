# Desktop/hybrid input fix verification

- Node production-Web-bridge DOM mocks: 40/40 checks passed
- Godot 4.6.3 Linux headless production-HUD/input checks: 33/33 passed
- Prior v0.11 synthetic native touch/cancellation regression rerun against current source: 41/41 passed
- No script errors or failed checks in these final three logs
- Audio head prefix and complete Toy adapter suffix are byte-identical to the original delivered source
- No browser process, physical Edge device, real controller, native GPU rendering, audible sound, public deployment or score submission was performed for this input fix

Root cause: the former startup check equated DisplayServer touchscreen capability or any positive maxTouchPoints with touch-control mode. Windows desktop/hybrid browsers can expose those capabilities while the player is using a mouse. TouchControls then enabled virtual/bot input, hiding the desktop UI and bypassing keyboard/mouse actions.

The revised policy uses mobile/iPad/primary-coarse-pointer hints for startup, then actual touch, mouse or gameplay keyboard events. Screen dimensions never choose a mode. The DOM capture observer sets the mode before forwarding the original touch event through Godot, without canceling, replaying or synthesizing input. Touch-generated compatibility mouse events are ignored. A live HUD switch clears stale touch actions and restores normal Player input. Hidden desktop touch controls do not run a per-frame update. Existing touch cancellation/reconciliation, audio and Toy bridge behavior remains intact.

The game did not contain physical controller action mappings, and this fix does not add or change them. It preserves the action map and mobile virtual sticks/buttons.

Reproduction commands and detailed coverage are in GodotProject/scripts/test/qa/README.md. The legacy touch harness is retained in docs/v0.11/QA/v0.11/wechat-qa/harness; it was temporarily loaded under scripts/test/qa for the rerun and then removed. Logs and a scoped source manifest are beside this report.
