# XSpoon Wayfinder Map

## Destination

Make XSpoon a menu-bar-led control surface for Hammerspoon shortcuts, app focus, inspection, and element capture.

## Known facts

- Hammerspoon remains the action engine and owns global hotkeys.
- XSpoon owns the visual menu, current-app reader, shortcut catalog, and settings pane.
- The universal capture path is `__SCRIPTS__.captureCurrentTarget()`.
- My Apps now includes Finder, Eagle, Notion, Canva, Chrome, Obsidian, ChatGPT, and System Settings.
- Text triggers are out of scope.

## Decisions

- `Control-Option-I`: toggle XSpoon menu.
- `Control-Option-O`: inspect current app.
- `Control-Option-E`: capture element.
- `Command-,`: open the settings/inspector pane.
- Shortcut editing uses colored modifier cards plus a one-key reader.
- Right-side modifier labels remain visible even where Hammerspoon receives normalized modifiers.

## Ticket plan

1. `task` Menu-bar lifecycle and global shortcut router: keep the menu primary, settings on demand, and move the old capture binding from `Control-Option-I` to `Control-Option-E`.
2. `task` My Apps shortcut reader: show every app and shortcut, add System Settings, support adding/editing app entries, and persist the catalog.
3. `prototype` Modifier card editor: support R CMD, R SHFT, TILDE, R BRKT, L BRKT, and R CTRL/OPT cards with one-key pairing.
4. `task` Hammerspoon sync: write edited bindings into the source-of-truth config and reload Hammerspoon without touching text-trigger behavior.

## Blocking order

Shortcut contract -> menu-bar lifecycle -> modifier editor -> Hammerspoon source sync.

## External tracking

The GitHub connector currently cannot access `23Maestro/hammerspoon`; Linear team `23Maestro` is visible but no linked XSpoon project exists. This file is the local canonical map until repository access is corrected.
