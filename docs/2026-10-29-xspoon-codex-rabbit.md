# XSpoon pre-commit review — 2026-10-29

## Scope

XSpoon recovery and shared canonical registry, modifier ledger, app-scoped Lua
runtime, Enter capture routing, tests, and dated findings. The earlier registry
work is required by the current app, not an unrelated new feature.

Excluded: legacy Raycast command/icon/package removal and the three old native
System Settings/replay/sheet scratch probes. Preserve those working-tree changes.
Do not retest or modify the verified Right Shift+S saved action.

## Initial pass

The Codex Rabbit initial pass ran eight checks successfully but intentionally
returned incomplete with two open findings:

1. `preserve-registration-error`: public shortcut save discarded the actual
   registration error and showed a generic reload failure. A new isolated Swift
   regression test reproduced that failure. The fix uses `Result.get()` and
   retains the saved record for retry; the focused test now passes.
2. `registry-scalar-entry-fails-closed`: valid JSON with a numeric app/action
   record caused a Lua indexing exception. The public reader test reproduced the
   native Hammerspoon exception. Guards now validate app, record, payload and
   review types; the same malformed fixtures return readable error receipts.

The second reading also reconciled the root README's obsolete two-store wording
with the canonical registry and documented the existing user-owned Spoon startup
requirement. No user's `init.lua` or live action data was modified by this review.

## Verification and approval

Verification checks cover Swift tests/build, inspection input lifecycle, modifier
ledger source/test fixtures, Lua syntax, canonical runtime reader, and diff
integrity. No new GUI replay is required for these error-path fixes; the separate
[live input receipt](2026-10-29-inspect-enter-capture.md) records the real Finder
capture-to-sheet check.

The review runner is the installed Singleton Systems Codex Rabbit implementation,
invoked with this repository as `--repo` and an XSpoon-specific check configuration.
This repository has no `review:codex-rabbit` npm script, so its unrelated Raycast
package metadata was not changed merely to wrap the runner.

Machine-readable pass receipts, findings and human-approval status are stored at:

`~/.local/state/singleton-systems/reviews/62dd44a8d12f427047f465690cfbf8547adf6daf2ecd083fb9ad01f7fba4fe4c.json`

The review binds HEAD, active diff and contract hashes. In this mixed checkout,
the gate also inventories excluded dirty files; the separately reported staged
tree identifies the proposed commit. Human approval of that exact scope is
required after the verification pass, before commit or push. No PR is needed.

## Research

- [Hammerspoon JSON API](https://www.hammerspoon.org/docs/hs.json.html#decode)
  decodes JSON; it does not promise the application's nested record schema.
- [Lua values and types](https://www.lua.org/manual/5.4/manual.html#2.1)
  distinguish tables and numbers. A successful JSON decode cannot establish
  that each nested value is safe to index as a record.
- [Swift Result.get](https://developer.apple.com/documentation/swift/result/get())
  preserves a failure by throwing its associated error rather than replacing it
  with a generic message.
