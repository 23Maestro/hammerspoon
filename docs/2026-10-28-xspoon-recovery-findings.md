# XSpoon Recovery Findings - 2026-10-28

## Current result and stop boundary

**Working, user-confirmed:** System Settings -> Keyboard Shortcuts -> Right Shift+S.
The selected modifier ledger maps Right Shift to Option+Command, so the runtime
chord is `alt+cmd+s`. The user saved this action and confirmed replay: "thats instant!"
Do not repeat capture/save/replay on this button without a new, specific failure report.

The durable action ID is `system-settings-492E530A-4951-4AA7-B2D0-FDEFAF62E860`.
Both the XSpoon catalog and action JSON contain that ID and chord at this readback.
The saved target is `com.apple.systempreferences`, AXButton, AXDescription
`Keyboard Shortcuts…`. This proves this action, not every app or capture type.

The sections below preserve initial observations. They are not all current defects.
Use the dated results and remaining-work section at the end for current status.

## First proof

Inspect the Keyboard Shortcuts button in System Settings, capture it in XSpoon,
save an app-scoped shortcut, press it, and observe the actual dialog opening.
Moving the window and restarting XSpoon must not invalidate that capture.

## Initial investigation evidence

- Source repository: `/Users/singleton23/Raycast/hammerspoon`.
- Swift app: `apps/XSpoon`. Live Lua files and XSpoon.spoon link to this repository.
- Existing worktree changes and five unpushed commits predate this investigation.
  They are not a rollback target.
- Live Hammerspoon reports version 1.1.1 and an existing XSpoon runtime with two app modals.
- System Settings opens its Keyboard page through its system URL.
- Its actual Accessibility tree exposes a button with empty AXTitle,
  AXDescription `Keyboard Shortcuts…`, role AXButton, and supported action AXPress.
- This is discovery evidence, not replay proof. No shortcut has been saved or tested in this investigation yet.

## Source observations - runtime impact still requires tests

1. The agreed menu/inspect keys are I/O, but current Lua, README, and settings reverse them.
   July findings still describe I for menu and O for inspect.
2. `stampLiveCapture` calls `writeLiveElement` before the latter's local declaration.
   In Lua that reference resolves as a global, not the later local function.
3. Capture requests copy/read a previous live file rather than always producing a fresh capture.
   Swift can then infer capture success from a process exit code and an older snapshot.
4. Swift and Lua toggle inspection independently. The local Swift toolbar only changes
   Swift state; closing the visual overlay does not stop the Lua timer/event tap.
5. The capture sheet dismisses after Save even when the store reports a save failure.
6. Add Shortcut writes a catalog label without a captured control or runtime binding.
7. Shortcut validation excludes some global chords but not menu/inspect/capture/context chords.
8. XSpoon.spoon treats most unrecognized failure statuses as success. Stopping the runtime
   exits its modals without deleting their hotkey objects.
9. Native captures persist transient window titles and text values as matching requirements.
   The default tree search is limited to eight levels.

## Historical conflicts

GitHub issue #8 and all five comments were read. They describe useful partial fixes,
including unsupported AX actions and arbitrary chords not registered at runtime.
They do not establish the requested System Settings end-to-end proof.

The July 21 design document proposes retiring the legacy dispatcher and using Keyboard
Maestro mouse-position capture. Issue #8 and the current skill instead preserve the
legacy semantic shortcuts and make coordinates fallback-only. The native first proof
does not need a new Keyboard Maestro dependency or migration of existing semantic actions.

## Official documentation reviewed

- AX lookup, ownership, action results, and focus attributes:
  https://www.hammerspoon.org/docs/hs.axuielement.html
- Per-app modal entry, exit, and deletion:
  https://www.hammerspoon.org/docs/hs.hotkey.modal.html
- Application activation/deactivation events:
  https://www.hammerspoon.org/docs/hs.application.watcher.html
- Distributed notifications are expensive and not guaranteed delivery:
  https://www.hammerspoon.org/docs/hs.distributednotifications.html

AXPress accepting a request is not proof that the UI changed. Replay verification must
read the resulting dialog, not merely accept a return value from performAction.

## Test boundaries - approved by the user

1. XSpoon capture/save interface: fresh capture, target-app preservation, durable saved
   shortcut, rejection of conflicts, and visible save errors.
2. Hammerspoon runtime interface: app-scoped activation, replay outcome, and repeatable
   refresh without duplicate bindings. Use public interfaces, not private helper tests.
3. Real macOS interaction: System Settings button -> capture sheet -> saved chord ->
   Keyboard Shortcuts dialog. Verify wrong-app rejection, moved-window replay, and relaunch.
4. TypeScript dependency checks apply only to the existing Raycast source. They cannot
   validate Swift/Lua behavior. If approved, configure and prove the requested deep-module
   checks there without restoring Raycast capture ownership or changing app languages.

## Initial execution log - superseded by the results below

- Investigation and official-doc review complete.
- Domain glossary added.
- Architecture candidates prepared as a temporary HTML review.
- Ticket publication, application edits, TDD cycles, build/install, and replay proof pending
  approval of the ticket breakdown and public test boundaries required by the invoked skills.

## Modifier ledger - fresh evidence, 2026-10-28

The selected live Karabiner profile is `Default`, with 28 complex-modification rules.
The canonical lookup is `assets/hammerspoon/registry/modifier-ledger.jsonl`, generated
only from that selected profile. Its first source fingerprint is
`c9d02b795d1f902130a1ede7fa798b9b7f54b5269a017790142ae73a19d95f3b`.

Eleven custom modifier rules were found, including hold/tap variants and the conditional
Left Control override. Each record preserves the original output events, normalized
Hammerspoon modifiers, timing, tap behavior, input requirements, conditions, and possible
earlier same-key overrides. No profile, remap, app binding, or application behavior changed.

Source-verified examples:

- Right Shift -> Option+Command.
- Right Command -> Control+Option.
- Right Option -> Control+Command.
- Tilde -> Control+Option+Command, unless an earlier mouse-mode rule consumes it.
- Left Bracket -> Control+Option+Shift, with earlier Premiere label-mode rules recorded.
- Right Bracket -> Option+Shift+Command, with earlier Premiere label-mode rules recorded.
- Right Control is not configured as a custom remap. The current XSpoon label grouping
  it with Right Option is not a reliable source for physical-key behavior.

Config verification does not establish physical keypress behavior or replay. Both are
explicitly marked `not-tested` in the ledger. The CLI refuses stale data and unknown
aliases instead of guessing. Regression checks use a temporary config, never the live
Karabiner source. They test lookup, condition preservation, stale rejection, and refresh.
These are post-implementation ledger regression checks, not a claimed TDD cycle for the
still-pending application repair.

Observed verification results:

- `node --test scripts/modifier-ledger.test.mjs`: passed (1 integration test).
- `node scripts/modifier-ledger.mjs check`: current, 11 records, source fingerprint matches.
- `node scripts/modifier-ledger.mjs lookup 'right shift'`: returned `alt, cmd`.
- `node scripts/modifier-ledger.mjs lookup 'right control'`: rejected with exit 1 as expected.
- Temporary-fixture config drift caused lookup to fail; refresh restored successful lookup
  with the new fixture modifiers. The live Karabiner config was not a test write target.

REA route decision: a complete source repository is available for XSpoon and the
Raycast extension. The REA skill explicitly directs ordinary source analysis to normal
repository tools. No binary/provider setup is warranted by the current evidence gap.
Use artifact/runtime analysis only if an installed app demonstrably differs from source.

Hammerspoon capability decision: its docs support app-scoped modal hotkeys and AX
inspection/actions. Side-specific raw flags are exposed but documented as experimental.
That does not establish a need for a new Karabiner dependency. Preserve existing physical
remaps as optional inputs; prove the Hammerspoon capture/replay loop before alternatives.

## Approved recovery work and observed results

GitHub tickets created and read back:

- #10: Restore XSpoon capture-save-replay in System Settings.
- #11: TypeScript deep-module checks for the remaining Raycast source, scheduled separately.

The latest user shortcut contract supersedes the earlier I/O discussion:

- Right Command+I (`ctrl+alt+i`) inspects the frontmost target app.
- `ctrl+alt+o` toggles the XSpoon menu.
- `ctrl+alt+e` captures a control and is reserved, not an app action chord.
- Right Shift+S (`alt+cmd+s`) opens Keyboard Shortcuts in System Settings only.
- Tab is present in the ledger and modifier choices: tap Tab; hold Control after 50 ms,
  with earlier mouse-mode overrides preserved in the ledger.

### Tests and fixes

Observed red -> green checks through public capture/save interfaces:

1. Native capture was locked to the observed window title -> native title is no longer
   a mandatory saved-control matcher.
2. Reserved `ctrl+alt+i` could be saved -> reserved control chords are rejected.
3. Tab incorrectly resolved to Right Command -> presets now load the canonical ledger.
4. Capture could be assigned to a different app -> the selected app must match the capture.
5. A runtime error inside successful AppleScript execution counted as success -> structured
   errors now fail the request.
6. An old live snapshot bypassed capture -> a new receipt and matching capture ID are required.
7. Recapturing the same control/chord was rejected as a duplicate -> evidence can be updated
   while preserving the existing action ID. Different controls still conflict.

The six-test Swift suite passed together; the subsequently added seventh test passed in
its focused run. Do not describe that as a later full-suite run. Ledger CLI regression
checks passed. Lua syntax checks passed. Native build, signing, installation, and process
verification passed through the project build script.

Native integration observations:

- Capture probe failed on the old route because it lacked a fresh capture ID.
- Updated capture probe returned the actual button, bundle ID, supported actions, and
  the same fresh capture ID in its receipt and saved payload.
- The actual XSpoon sheet showed the captured System Settings button and ledger presets,
  including Tab. A reserved I save displayed an error and kept the sheet open.
- A duplicate attempt at the user's already-saved Right Shift+S action was rejected before
  the same-control update fix. That was not evidence that the existing action was missing.
- Runtime refresh now reports registered action IDs and refreshes saved modals without
  restarting all Hammerspoon behavior.
- Native app startup no longer declares a competing empty SwiftUI Settings scene. The
  AppKit controller owns the inspector; SwiftUI still renders its content.

### Working replay and latency

The original native route used AXPress, which can block while opening a modal dialog.
The repaired button route resolves and verifies the AX identity in the correct frontmost
app, then clicks the control's current frame. It does not click an unverified saved point.

Recorded callback duration: **206.409333 ms** for the saved Right Shift+S action; another
run recorded 228.330292 ms. These measure resolution and click submission, not full display
render time. The user confirmed the visible behavior felt instant. Accessibility readback
also found the actual AXSheet with the Keyboard Shortcuts sidebar and Done button.

One moved-window run opened that dialog successfully, but took **2794.78275 ms** after
falling back to a tree search. This is a latency limitation, not a lost shortcut. An
in-memory verified-target cache was subsequently added; its moved-window performance was
not fully verified before the user stopped further button testing. Do not claim otherwise.

Later redundant capture/save automation hit an `hs` CLI exception
(`NSDestinationInvalidException`, HSClient target thread exited). This was a test-driver
failure, not evidence that the saved action or XSpoon crashed. Exact trigger is unresolved.
No further UI tests of this button are authorized by this task.

Reference for the blocking-action caveat:
https://www.hammerspoon.org/docs/hs.axuielement.html#performAction

## Remaining app-wide work - not implemented by this logging pass

### Required ownership model

Use the Leader Key reference as an organization pattern, not a request to reproduce its
leader-key sequence system or use literal filesystem folders:

```text
My Apps
  System Settings [bundle ID]
    Keyboard Shortcuts
      Shortcut: Right Shift + S
      Target: captured button identity
      Action: click
      Verification: verified, 2026-10-28
  Premiere Pro [bundle ID]
    Y Value
      Shortcut: Right Command + E
      Verification: blocked - reserved Capture chord
  ChatGPT [bundle ID]
    Dictate
      Verification: saved - not verified in this recovery pass
```

The app is the parent. Every saved action is its child. Modifier presets are references
to the shared ledger, not independent app/action stores. Browser actions additionally
carry site scope. Display names do not replace bundle IDs as app identity.

### Source-backed gaps

1. **One canonical app/action registry.** The current app catalog is persisted separately
   from runtime action JSON; some listed shortcuts are legacy commands rather than captures.
   Unify ownership and expose legacy origin explicitly instead of presenting every label as
   an executable captured action. Existing legacy commands must not be silently deleted.
2. **Review old attempts.** Inventory and mark actions as verified, unverified, blocked, or
   needing recapture. The three current captured runtime records are System Settings Keyboard
   Shortcuts, ChatGPT Dictate, and Premiere Y Value. The catalog also contains inherited
   commands. This is a current inventory, not proof all earlier experiments have been recovered.
3. **Resolve conflicts visibly.** Premiere Y Value currently uses `ctrl+alt+e`, the reserved
   Capture chord. Keep it visible as blocked and let the user choose a replacement. Do not
   register a competing binding or silently change its modifier.
4. **Finish control-specific replay.** Buttons, text fields, menu options, and Chrome-site
   controls need separate verified behavior. A text field's changing value must not be its
   identity; generic labels such as Premiere's `UI_HotText` need more distinguishing evidence.
   The System Settings button proof does not verify these other types or apps.
5. **Bound resolution cost and failure.** Keep current-app checks, detect stale/ambiguous
   targets, cap lookup time, and show a recapture result rather than a long silent scan or
   arbitrary coordinate click. Cache invalidation and cold-start/moved-window timing remain
   work to verify on another representative action, not repeated tests of the proven button.
6. **Keep save/edit/delete consistent.** Runtime registration, canonical saved data, and visible
   action state must agree after edits, deletion, and relaunch. Maintain per-action last
   result and verification evidence rather than treating presence in a list as proof.

Next recommended slice: reconcile the per-app action tree and review legacy attempts
read-only first. Then choose one other app/control for the next proof. Leave the verified
System Settings action alone. No legacy actions were deleted or remapped during this audit.

## Rebuild and application registration - 2026-10-28

Requested rebuild completed through `apps/XSpoon/script/build_and_run.sh --verify`.
The full seven-test Swift suite passed with zero failures on this run. This supersedes
the earlier six-test full-suite checkpoint plus seventh focused test.

- Build, signing, install, and launch succeeded.
- `/Applications/XSpoon.app` passed strict/deep signature verification.
- LaunchServices registration completed successfully.
- `NSWorkspace.urlForApplication(withBundleIdentifier: "com.singleton23.XSpoon")`
  resolved to `/Applications/XSpoon.app`.
- The running application's bundle URL was also `/Applications/XSpoon.app`.
- Modifier ledger check passed before packaging; the selected-profile fingerprint matched.
- No System Settings button capture or replay tests were run during this rebuild.

This rebuild packages the current implementation. The unified per-app registry migration
described above is the next code change, not a feature claimed by this installation.
