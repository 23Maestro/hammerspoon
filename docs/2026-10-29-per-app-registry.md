# Per-App Registry Migration - 2026-10-29

## Result

XSpoon and Hammerspoon now read captured actions from one canonical file:
`~/.hammerspoon/xspoon_registry.json`.

The document has `schemaVersion: 1` and an `apps` array. Each app parent contains
its ID, display name, bundle identifier, icon, and `actions` children. Captured
children contain the original `payload`, modifier-ledger preset ID, origin, and
review evidence. The UI derives its shortcut rows from those payloads. It does
not persist another copy of the catalog in UserDefaults.

An inherited command instead contains a `legacyShortcut` and `legacyCommand`
origin. It is visible as Legacy Script but is not presented as a captured target.
Its existing hand-written Hammerspoon implementation remains unchanged. These
entries do not introduce duplicate bindings in the saved-capture runtime.

## Live migration receipt

- App parents: **10**.
- Captured records: **3**; all original payloads compare equal after migration.
- Inherited script-command records: **7**.
- Runnable captured actions reported by Hammerspoon: **2**.
- Skipped records: **8** (seven inherited commands plus one blocked capture).
- LaunchServices and running process both resolve `/Applications/XSpoon.app`.

Current captured-action review states:

| App | Action | Review | Runtime |
| --- | --- | --- | --- |
| System Settings | Keyboard Shortcuts, Right Shift+S | Verified | Registered, unchanged |
| ChatGPT | Dictate, Right Command+D | Unverified | Existing binding retained |
| Premiere Pro | Y Value, Right Command+E | Blocked | Not registered: conflicts with global Capture |

The System Settings record is
`system-settings-492E530A-4951-4AA7-B2D0-FDEFAF62E860`. Its original payload,
including its hotkey, target, frame, window frame, and replay intent, is unchanged.
Its existing 2026-10-28 verification evidence was carried into the registry.
No capture, save, click, or replay test of that button was run during this migration.

## Preservation

Migration backup:
`~/.hammerspoon/backups/xspoon-registry-8E6C3853-6A5D-40B2-8924-03B8B711926E/`.

It contains the original action JSON, raw legacy catalog data, and deletion markers.
The original action file remains byte-for-byte unchanged. SHA-256 before and after:
`dcfbac50e4c38dcdfbac51d12951e7fbfd55de976ad24f6c405cffef3d6bf3a2`.
The live legacy UserDefaults catalog also compares byte-for-byte equal to its backup.
No old attempts were deleted, remapped, or automatically declared successful.
Previously removed catalog entries are not silently restored.

The registry file has owner-only file permissions. Writes are atomic. Once the
canonical document exists, invalid data causes a visible load failure, not fallback
to stale action files or an overwrite of the corrupt document.

## Behavior

- Save, recapture, app addition, and deletion update this one registry.
- Reopening XSpoon projects the same app/action records back into the UI.
- Deleted actions do not return from stale UserDefaults or built-in catalog entries.
- Review states are Verified, Unverified, Blocked, Needs Recapture, and Legacy Script.
- Blocked and Needs Recapture entries do not receive saved-action runtime bindings.
- Existing unverified captures remain visible and retain their previous eligible bindings;
  a label in the catalog is not treated as replay proof.
- The unused label-only shortcut editor and hard-coded stale-record purge were removed.
- Hammerspoon was reloaded once to load the canonical reader. Ordinary saves still refresh
  saved-action modals without a full Hammerspoon reload.

## Verification

Public-interface regression tests observed failing behavior before the migration code:

1. Canonical-file precedence failed because the client returned legacy-file records.
2. Migration initially did not import the per-app records or preserve verification state.
3. Save rewrote the legacy file instead of creating the canonical action.
4. The Hammerspoon reader ignored the supplied canonical fixture and returned legacy actions.
5. A stale, corrupt legacy catalog still prevented canonical UI loading after migration.

After fixes:

- `swift test`: **12 tests passed**, zero failures.
- `node scripts/test-registry-runtime.mjs`: passed against the real Hammerspoon JSON reader
  using temporary fixtures. Blocked/inherited entries are skipped; wrong-parent and malformed
  registries fail closed. No action callbacks are executed by this test.
- Lua syntax validation passed for browser automations and XSpoon.spoon.
- Native build, signing, install, launch, modifier-ledger check, and registry readback passed.
- Live registry readback reports `source: canonical`, the canonical path, two runnable actions,
  and the working System Settings action among registered IDs.
- Snapshot comparisons verified preservation of all three live captured payloads and both
  legacy source stores.

This verifies registry ownership and migration, not universal replay support. Menu options,
text-field identity, cold-start lookup latency, and the other apps still require their own
bounded proofs. The working System Settings button remains outside further testing unless
the user reports a new failure.
