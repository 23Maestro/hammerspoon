# Latest XSpoon fixes review — 2026-10-29

## Reviewed scope

Dictate cold lookup, Search plain-typing fix, per-app legacy deletion, their
tests, and the two dated test logs. Exclude unrelated Raycast command/icon/package
removal and the old System Settings/replay/sheet GUI scratch probes.

The user confirmed these workflows now work. Finder selection-based behavior is
the next separate test, not part of this patch or its live verification.

## Initial review

All 13 configured checks passed. The initial pass nevertheless remained
incomplete with one open finding:

`unreadable-canonical-must-not-bypass-deletion-policy` — when the default canonical
registry existed but io.open failed, the reader could fall back to the old action
file and bypass the canonical deletion policy. An actual Hammerspoon public-reader
test with a mode-000 temporary canonical file and readable legacy file reproduced
the fallback: one old action was returned instead of an empty error result.

The fix checks whether the canonical path exists (including a symlink) before
allowing compatibility fallback. An existing unreadable canonical path now returns
an error and disables legacy dispatch rather than reviving removed routes. The
same test passes afterward. A separate case confirms legacy compatibility still
works when the canonical file truly does not exist. No live data was modified.

## Verification boundaries

The verification pass reruns working/staged diff integrity, Swift tests/build,
inspection input, native replay identity/depth/budgets, saved routing, plain Search
typing, legacy deletion dispatch, actual Hammerspoon registry fixtures, modifier
ledger tests/live source validation and Lua syntax.

Runtime tests read temporary files or use isolated OS adapters. They do not press
Dictate, delete the user's Search record, type into a user's document, change
Karabiner configuration, or replay Right Shift+S. Existing user-confirmed live
results are in the associated test logs; those are not repeated merely for review.

Machine-readable checks, initial and verification receipts, and final human gate:

`~/.local/state/singleton-systems/reviews/4c9dc860d84d7c7d7a23d3496967294ad00f816bccf7e0f4393a87c6254ec138.json`

The installed Codex Rabbit runner is used with --repo and an XSpoon-specific
configuration because this Raycast package has no review:codex-rabbit npm script.
The gate binds HEAD, the full active diff (including preserved excluded work) and
contract hashes. A separate staged tree hash identifies the proposed commit.
Human approval of that reviewed scope is required before commit/push. No PR.

## Associated evidence

- [Dictate and AX freeze findings](2026-10-29-chatgpt-dictate-verification.md)
- [Deletion and plain Search typing](2026-10-29-shortcut-delete-and-search-input.md)
