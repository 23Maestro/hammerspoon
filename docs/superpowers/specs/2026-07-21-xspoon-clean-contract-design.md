# XSpoon Clean Contract — Design

## Problem

`browser_automations.lua` grew to 2,282 lines by absorbing seven unrelated
responsibilities: Chrome JS execution, job-application form-filling, the
Raycast "List Scripts" catalog, live AX inspection, local element capture,
element-action replay, and JSON persistence for XSpoon captures. Because
capture/dispatch logic for XSpoon lived inside a file meant for Chrome/Raycast
tooling, the two systems tangled:

- `ModuleGenerator.isBuiltIn()` only protects 4 of the 10 registered apps
  (`chrome, codex, finder, keyboard_maestro` — missing `eagle, canva, notion,
  obsidian, raycast, xspoon_menu`; it also lists `prospect_id`, which is not
  a registered app at all). Saving a captured shortcut for any of the six
  unprotected apps would silently overwrite their hand-written, working
  `.lua` module.
- An uncommitted `bindGeneratedHotkeys()` function bound arbitrary captured
  hotkeys with no collision check against the reserved `⌃⌥P/R/C/S/V/M` namespace
  already used by proven modules.
- `saveElementShortcut()` commits to the visible UI list before module
  generation and reload succeed, so failures leave the UI claiming "saved"
  while Hammerspoon has nothing.
- Three Lua functions (`bindElementActionHotkeys`, `reloadElementActionHotkeys`,
  `savedElementHotkeyCount`) and two Swift methods
  (`reloadSavedElementRoutes` ×2) are dead — call sites were removed in a
  prior refactor but the functions were left behind.

## Goal

A single, repeatable, plugin-shaped contract for per-app automation that:
1. Keeps the proven per-app module shape (`M.id`, `M.matches`, `M.actions`)
   completely unchanged.
2. Separates XSpoon's control surface from Raycast/Chrome/job-filling tooling
   so neither can accidentally corrupt the other.
3. Makes captured shortcuts *become* real per-app modules through one atomic,
   verifiable save path — never a parallel JSON-only dispatch path.
4. Never touches Karabiner. XSpoon reads/labels the modifier presets Karabiner
   already remaps (Right Command → `ctrl+alt`, etc.); it never writes
   Karabiner configuration.

## Non-goals

- No change to the five canonical semantic actions (`primary/search/copy/
  shortcutS/voicemail`) or their bindings.
- No change to Karabiner-side remapping.
- Job-filling data/functionality is kept, not deleted — only relocated.

## Architecture — three surfaces

| Surface | Owns | Lives in |
|---|---|---|
| **Raycast extension** | Chrome JS execution engine, job-application form-filling (Prospect ID, NurseHub, HSN, WFLA, Freelance Broadcast, Amazon Flex, Pepsi, Optimal, GAT, SMH, education fillers), selector picker, the `list()`/`execute()` catalog powering "List Scripts" | `raycast_scripts.lua` (renamed/stripped from `browser_automations.lua`) |
| **XSpoon control surface** | Per-app dispatch core, capture (live inspector + local AX + Chrome-site element capture), element-actions JSON store, module generation/reload, hotkey collision checking | `XSpoon.spoon/init.lua` |
| **Per-app plugins** | One file per app: `M.id`, `M.matches(context)`, `M.actions{}`, optional `M.start()` | `XSpoon.spoon/apps/*.lua` |

`XSpoon.spoon` is a formal Hammerspoon Spoon (`init.lua` inside
`XSpoon.spoon/`, loaded via `hs.loadSpoon`), chosen deliberately over a plain
module because the control surface *is* XSpoon's product surface — repeatable,
shapeable, proper packaging matters here. Per-app plugins remain plain Lua
files loaded internally by the Spoon (not each its own Spoon), preserving
today's proven contract exactly.

The repo/runtime symlink split is preserved: `assets/hammerspoon/XSpoon.spoon/`
in the repo, symlinked to `~/.hammerspoon/Spoons/XSpoon.spoon/` at runtime.
Generated per-app modules are written to
`~/.hammerspoon/Spoons/XSpoon.spoon/apps/<slug>.lua` (runtime) — the source
repo only tracks hand-written built-in modules, matching how generated files
work today (never committed, generated on demand).

## Chrome — two identities

Chrome appears in both surfaces, deliberately:

- **`raycast_scripts.lua`**: generic Chrome JS-execution engine, used only for
  job-filling and the Raycast catalog. Unrelated to XSpoon captures.
- **`XSpoon.spoon/apps/chrome.lua`**: site-scoped module. `M.matches` checks
  both bundle ID and active site/URL pattern, the same way other modules match
  a bundle ID alone. A captured shortcut on `docs.google.com` and one on
  `mail.google.com` are different matches. Capture types (button, menu-option,
  text-field) are identical to the AX-based flow — same idea, DOM replay
  instead of `AXPress` replay.

## Hotkey binding — collision detection, no artificial gate

Captured shortcuts are not restricted to the five canonical semantic names.
Any modifier+key combination is allowed, gated only by verifiable reality:

1. Before binding, query `hs.hotkey.getHotkeys()` for the target combo.
2. **Collision** → refuse the save, report exactly what already owns the
   combo (e.g. "⌃⌥S is bound to Notion's shortcutS"), let the user pick another
   key. No silent double-bind, no shadowing.
3. **No collision** → bind it, through `XSpoon.spoon`'s dispatch core, the same
   way the five canonical bindings work today.

This replaces the deleted, uncommitted `bindGeneratedHotkeys()` — same intent,
now provably safe.

## Save flow — atomic

`saveElementShortcut` order changes to:

1. Write `browser_element_actions.json`.
2. Generate/patch `XSpoon.spoon/apps/<slug>.lua`.
3. Hotkey collision check (previous section) — abort and roll back JSON write
   on conflict.
4. Reload Hammerspoon; confirm the module loaded.
5. Only then commit to the visible shortcut list / UserDefaults.

Any failure at steps 1-4 leaves the UI state untouched and surfaces the real
error instead of a false "saved."

## Delete — two-store rule, extended

Deleting a shortcut removes it from `browser_element_actions.json` **and**
regenerates (or deletes, if none remain) the owning app's generated module,
then reloads. Deleting an app removes every generated module it owns.

Built-in modules — `chrome, codex, finder, keyboard_maestro, eagle, canva,
notion, obsidian, raycast, xspoon_menu` — are never touched by generation or
delete. `ModuleGenerator.isBuiltIn()` is corrected to list all ten (currently
lists six, missing `eagle, canva, notion, obsidian, raycast, xspoon_menu`).

## Dead code removed

- Lua: `M.bindElementActionHotkeys()`, `M.reloadElementActionHotkeys()`,
  `M.savedElementHotkeyCount()`.
- Swift: `HammerspoonClient.reloadSavedElementRoutes(actionID:)` and
  `reloadSavedElementRoutes()`.
- Runtime test artifacts (e.g. `textedit.lua`) left over from manual testing.
- The uncommitted, unshipped `bindGeneratedHotkeys()` in `automation_core.lua`
  (superseded by the collision-checked binder inside `XSpoon.spoon`).

## Testing / proof of migration

Since this is a repackaging of proven logic onto a new surface (plain
requires → formal Spoon), the bar is "prove it still works the same,"
per-module:

1. For each built-in app module, trigger its existing proven shortcut
   (e.g. Notion voicemail toggle, Eagle secondary-click, Codex shortcutS) and
   confirm identical behavior after the Spoon migration.
2. Capture one new shortcut end-to-end (save → module generated in
   `XSpoon.spoon/apps/` → reload → physical hotkey fires) for an app that was
   previously unprotected (e.g. Eagle) and confirm it does **not** overwrite
   the hand-written module.
3. Attempt to capture a shortcut on a combo already owned by a canonical
   binding (e.g. ⌃⌥S) and confirm the save is refused with a clear collision
   message, not a silent double-bind.
4. Delete the captured shortcut from (2) and confirm the generated module and
   JSON entry are both removed, built-in modules are unaffected.
