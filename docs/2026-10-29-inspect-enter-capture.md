# Inspection input receipt — 2026-10-29

Ticket: https://github.com/23Maestro/hammerspoon/issues/12

## Contract

- Right Command+I (canonical Karabiner translation: Control+Option+I) toggles inspection.
- Unmodified Return/Enter down is consumed only while inspecting. Capture happens
  on release, using a fresh Accessibility hit test at the pointer, not the last poll.
- Repeated key-down events do not capture or reach the shortcut sheet.
- Escape cancels inspection without capture. Other keys and modified Enter pass through.
- Right Command+E is no longer a global capture binding or reserved saved-action chord.
- Removed the inspector Capture button and obsolete capture-request notification route.
- Hammerspoon remains the input/AX owner; no Swift global hotkey or permission prompt added.

## Test-first evidence

1. `lua scripts/test-inspection-input.lua <temporary-directory>` failed on
   `Enter down must be consumed during inspection` before the routing change.
   After implementation it passes lifecycle, release capture, repeats, modified
   Enter, Escape, I toggle, keypad Enter, error retry, and no global E binding.
   OS adapters are simulated here; this does not itself prove macOS delivery.
2. Swift public save test `testRightCommandECanBeSavedForAnAppControl` failed with
   `E is reserved by a global Hammerspoon shortcut` before the reservation change.
   It now saves and reads the app-scoped action from an isolated temporary registry.
3. `swift test`: 13 passed, zero failures. Migration expectation for the generic
   Premiere target is now Needs Recapture rather than a shortcut conflict.
4. Lua syntax checks passed for browser_automations and XSpoon.spoon.
5. `node scripts/test-registry-runtime.mjs`: passed canonical-reader/fail-closed checks;
   no saved actions executed by this test.
6. Modifier ledger lookup verified the selected live configuration hash:
   `c9d02b795d1f902130a1ede7fa798b9b7f54b5269a017790142ae73a19d95f3b`.

## Live integration evidence

`node scripts/probe-inspection-input.mjs --run` passed through the installed app
and real Hammerspoon event tap. This opt-in probe creates a temporary Finder
window, targets a live hit-tested Back button, and sends the translated
Control+Option+I chord, Escape, then another inspection followed by Enter.

- Live payload: Finder, AXButton, description `back`.
- Escape stopped inspection without changing the capture ID.
- Enter produced capture ID `8C7224BC-D0CE-4DE8-BA37-1DB39DBD167C`.
- Inspection stopped after successful capture.
- XSpoon AX readback: exactly one AXSheet and one Save Shortcut button.
- Registry hash unchanged across this live check; nothing saved or replayed.
- Probe cancels its setup sheet, closes its temporary Finder window, and restores
  pointer, clipboard data, and preceding app focus.

Initial harness attempts did not count as passes: an existing Finder window
returned off-screen/stale child coordinates; a later attempt had no Finder
window; finally the sheet scanner looked only at AXTitle although SwiftUI exposes
the button label in AXDescription. The harness now creates its own window,
requires a live AXButton hit before sending capture keys, and reads either label.
These were test setup/readback failures, not evidence of successful capture.

## Installation and preservation

`apps/XSpoon/script/build_and_run.sh --verify` passed. Installed
`/Applications/XSpoon.app` with the existing bundle ID and stable signing identity;
strict signature validation passed. Hammerspoon was reloaded once.
Final runtime readback: Control+Option+I has one binding, O has one, E has zero;
inspection is inactive. Ticket #12 was updated and closed with local evidence.

The verified System Settings record
`system-settings-492E530A-4951-4AA7-B2D0-FDEFAF62E860` remains byte-equivalent as a
decoded payload to its original migration backup, including Alt+Command+S.
Its verified review/date are unchanged. No System Settings button was tested.

The existing Premiere Y Value payload/chord was not changed. Only its review was
updated from obsolete global-shortcut conflict to Needs Recapture: `UI_HotText`
without a stronger identifier remains ambiguous. Releasing E does not prove replay.

## Boundaries

- Live input was synthesized at the translated chord; physical Right Command
  delivery is supported by the verified ledger, not a new physical-key test.
- Enter outside inspection and modified Enter were tested at the input adapter,
  not by typing into a user's document.
- No Chrome selector-path changes or all-app replay claims in this pass.
- No commit, push, or pull request requested or performed.

## API sources

- [Hammerspoon event taps](https://www.hammerspoon.org/docs/hs.eventtap.html#new):
  callbacks can consume input by returning true; taps have explicit start/stop.
- [Event flags and types](https://www.hammerspoon.org/docs/hs.eventtap.event.html):
  distinguish key-down/key-up and modifiers instead of globally binding Return.
