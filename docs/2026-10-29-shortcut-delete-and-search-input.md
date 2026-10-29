# Verification labels, deletion and Search typing — 2026-10-29

## User contract

- The user confirmed the replacement ChatGPT Dictate capture works after the
  lookup fixes. Only that current record was marked Verified, with a dated user
  confirmation. Its payload and chord were unchanged; the original registry was
  backed up. Other captured records, including Right Shift+S, were unchanged.
- The user explicitly requested Delete remove the row AND stop the background
  shortcut, not merely hide the row. The user also requested Search NOT be deleted
  during this work. No real legacy entry was deleted for verification.
- The user reported plain S being swallowed after Search focused its field.
  Right Command+S should run Search; plain S must type normally.

## Why plain S was intercepted

`scripts/apps/codex.lua` installed a persistent keyDown event tap that explicitly
called focusSearchField for unmodified S and a separate action for unmodified
apostrophe. This was not a stuck modifier or a modal failing to exit. It was
intentional legacy single-letter interception with no disengagement condition.

The tap was stopped live, then its installation removed from source. The existing
start() entry point remains to clean up the previous watcher and keep the user's
init.lua compatible. Search still runs through the existing modifier-key
dispatcher. Ordinary S and apostrophe are not bound by this app module anymore.

## Real legacy deletion

The Swift UI and client previously blocked legacyCommand deletion. The client
now atomically removes the row and saves an app/key/modifier disable rule in the
canonical registry. Semantic-dispatch and context-menu hotkeys read those rules
before invoking legacy handlers. The rule survives relaunch and app removal, and
does not disable the same chord in another app. Shared script source is retained;
the deleted app-specific route no longer executes.

The optional disabledLegacyShortcuts field is backward-compatible with existing
registry documents. Swift and Lua validate it; unreadable policy fails closed.
Trash buttons are enabled for legacy rows. Removing an app also disables its
legacy routes instead of leaving hidden commands running.

This change does not redesign the existing reserved-global-chord policy or make
every deleted global chord available for a new captured binding.

## Test evidence

1. Public Search-input regression failed before the fix: Plain S must type
   normally, not focus Search. It now passes S/apostrophe passthrough before and
   after focus, no repeated automation notification, and correct-app Search.
2. Public Swift legacy-delete regression failed before the change because the
   client rejected inherited commands. It now proves row removal, persisted
   disable policy after relaunch, and preservation of another app's identical S.
3. Public Hammerspoon registry test failed before the policy API was implemented;
   it now reads actual temporary JSON and verifies matching route disabled,
   different app/key unaffected, malformed JSON/entries fail closed.
4. Isolated public core/context dispatch test runs the real Lua modules and
   proves deleted Search and M routes do not execute, another app remains active,
   and malformed policy fails closed. No real keys/actions or live data touched.
5. Swift app-removal test proves inherited S/C routes get disable rules and
   captured actions are removed, while another app remains.
6. Full Swift suite: **17 passed**, zero failures. Inspection-input lifecycle,
   native replay identity/depth/budget, Lua syntax and diff-integrity checks pass.

Live Hammerspoon readback after reload: plainLetterWatcherEnabled=false,
searchDisabled=false, inspection inactive. The Search entry remains in the
catalog, and its Right Command+S route was not disabled or deleted. No actual
typing was inserted into the user's Search field by these tests.

XSpoon was rebuilt and installed with its existing bundle ID/signing path;
Hammerspoon reloaded the fixed Lua source. No Accessibility grant requested.
No saved Dictate or System Settings action was replayed during this work.
These changes are local follow-up work; no new commit or push was requested.
