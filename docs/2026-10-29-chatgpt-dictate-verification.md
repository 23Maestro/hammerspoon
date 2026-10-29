# ChatGPT Dictate verification — 2026-10-29

Ticket: https://github.com/23Maestro/hammerspoon/issues/13

## Published baseline

- Reviewed scope committed as `ac3b3207e2710833d6db7be72bbfc676dbf8f0f4`.
- Commit tree matches the human-approved staged tree:
  `4b16403e1e3b10ad84428c409feabfb3309e5d5e`.
- Push included the five previously queued commits. Remote master read back as
  `ac3b3207e2710833d6db7be72bbfc676dbf8f0f4`. No PR created.
- Codex Rabbit status was approved before commit; the two review findings were
  resolved and all eight verification checks passed.

## Existing action, not a new migration

- App display name: ChatGPT; bundle ID: `com.openai.codex`.
- Current saved action: `chatgpt-4C270186-F5DB-4E1C-BF1C-0B0751954866`.
- Name: Click Dictate. AXButton with title and description `Dictate`.
- Replay intent: physicalClick. Physical Right Command+D translates to
  Control+Option+D according to the previously verified modifier ledger.
- This is already a captured canonical action, separate from the inherited
  ChatGPT Focus Shortcut Search command. No need to recreate or convert it.
- Review remains Unverified until live UI behavior is observed.

## Tests completed

- `swift test --package-path apps/XSpoon`: **15 passed**.
- Added a public save/read test proving D rejects a conflicting control within
  the same app, can be reused in another app, and persists through a new client.
- `lua scripts/test-saved-action-routing.lua`: passed. Exercises public Spoon
  start/stop/status with isolated OS/action adapters: app-scoped D routing,
  unrelated-app suppression, cross-app chord reuse, reserved I rejection,
  refresh without duplicate active routes, and failed replay receipt preservation.
- These additions characterize existing behavior; no production fix was needed
  for those tests. They are not substitutes for live microphone/UI evidence.

## Live preflight and current boundary

Runtime readback lists the saved Dictate action as registered. Before any new
replay, its prior lastResult already showed `missing-local-element` with
approximately 37,108 ms elapsed. That is historical runtime state, not a new test
performed in this pass, and is not sufficient to diagnose a particular cause.

The visible workspace was Chrome (workspace 1), while ChatGPT's window was on
AeroSpace workspace 3 with off-screen coordinates. A readonly check at the saved
point therefore hit Chrome, not Dictate. No replay or coordinate click was sent.
An activation/focus probe briefly brought ChatGPT into view, but foreground state
subsequently returned to Chrome. The user was asked for a 20-second idle window
before a microphone-changing live test.

Pending live checks: make the intended ChatGPT window visibly frontmost, verify
the Dictate control and draft state, trigger the actual translated D binding once,
observe recording UI, cancel without sending or altering a draft, and verify
XSpoon relaunch persistence. Do not mark Verified merely because registration or
an event-posting call succeeded. No live saved records have been rewritten here.

Right Shift+S was not invoked or changed. This follow-up's tests/log are separate
local changes after the approved push, not part of the published commit.

## Research

[Hammerspoon hs.axuielement](https://www.hammerspoon.org/docs/hs.axuielement.html)
documents that AX discovery depends on the surfaces the target application
exposes and that changes require readback for confirmation. Its system-wide
element-at-position lookup reads the actual screen point, not a saved app's
abstract control identity. That is why a point hitting Chrome cannot verify
ChatGPT Dictate and must never justify an unverified coordinate click.

## Subsequent user confirmation and freeze diagnosis

This section supersedes the earlier pending-live-test notes. The user deleted
the previous capture and saved a new one:
`chatgpt-FC5E939C-E5E0-4C56-B70C-E59238163CDF`.
The user explicitly confirmed inspection -> Enter -> save Right Command+D ->
dictation started. The supplied screenshot shows Stop dictation and the active
microphone indicator. No automated repetition of that successful press was needed.

The user then reported menu/inspection hotkeys becoming unresponsive. Evidence:

- No hs CLI or osascript process was running at the initial process inventory.
- A read-only Hammerspoon AppleScript ping timed out after 2,504 ms.
- A one-second process sample showed Hammerspoon's main thread inside
  `hotkey_callback`, Lua and `AXUIElementCopyAttributeValue`; XSpoon's sample
  showed a functioning AppKit run loop rather than a blocked IPC wait.
- Raw samples: `/tmp/xspoon-hammerspoon-20261029.sample.txt` and
  `/tmp/xspoon-app-20261029.sample.txt`.
- Hammerspoon was terminated gracefully and relaunched without changing saved
  data or permissions. Subsequent status ping returned in 125 ms.
- The actual translated Control+Option+0 chord changed inspector visibility
  from zero standard visible windows to one. Control+Option+I started inspection
  for com.openai.codex; a second I chord stopped it. No Dictate replay was sent.

### Proven lookup defects and repairs

1. The old walker keyed visited controls by `tostring(element)`, which includes
   each Lua wrapper's address. New wrappers for the same AX control therefore
   bypassed cycle detection. A public replay regression reproduced 541 child
   reads. Comparing AX controls with `==` now deduplicates them. The search also
   has a 1,000-node / 750-ms cooperative budget. This is not a hard wall-clock
   bound on an individual macOS AX IPC call.
2. After recovery, a saved Dictate attempt returned missing-local-element in
   74.2 ms. Read-only live discovery found the exact button at depth 31, below
   the old replay cutoff of 24. A depth-31 public replay regression failed before
   raising the cold-search depth to 64, and passed afterward. Node/time budgets
   remain in force; the working Settings fast path was not changed or replayed.

The new Lua source was reloaded. A fresh-module, cold-cache public replay with
real AX reads and an intercepted click actuator resolved the current saved
Dictate control in **164.302 ms**, returning title/description Dictate, AXButton,
frame x=1504 y=1084 w=34 h=34. The proposed click point was (1521,1101).
**Zero physical clicks were sent in this dry run.** This proves cold resolution,
not microphone activation after the fix; the next user press is the real check.

Tests: `lua scripts/test-native-replay.lua` covers duplicate wrappers/cycles,
depth 31, changed labels without a blind click, and node-budget exhaustion.
The isolated Spoon routing test continues to pass. The pre-existing full Swift
suite had 15 passing tests; these repairs change Lua only. Code/tests/log remain
local follow-up changes after ac3b320; no additional commit/push was performed.

### Firecrawl evidence

The requested Firecrawl helper fetched the official Hammerspoon AX docs with
provider success, HTTP 200, nonempty content and the expected `elementSearch`
text. Receipt:
`/private/tmp/xspoon-firecrawl-2026-10-29/20261029T172455.688709Z-0a1c258bf02d/receipt.json`.
Retained page.md SHA-256:
`3a214bae5d037f8125635bf90cdf1ba4a9bcc8c931339cfe45ebcacd6aa1e8f0`.

[Hammerspoon's AX implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/axuielement/libaxuielement.m)
confirms tostring uses the Lua userdata pointer while equality uses CFEqual.
The official AX documentation exposes explicit depth/count controls and
confirmation/readback requirements. The measured depth of 31 and timings above
come from this live app, not from a general claim in the documentation.
