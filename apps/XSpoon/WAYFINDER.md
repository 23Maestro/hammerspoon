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

- `Control-Option-O`: toggle XSpoon menu.
- `Control-Option-I`: inspect current app.
- `Control-Option-E`: capture element.
- `Control-Option-0`: open the inspector pane.
- Shortcut editing uses colored modifier cards plus a one-key reader.
- Right-side modifier labels remain visible even where Hammerspoon receives normalized modifiers.

## Ticket plan

1. `task` Live inspector verification: confirm the Wooshy-style reader stays stable while moving the mouse and while capture is triggered.
2. `task` Modifier onboarding research: review the closest per-app modifier tools and keep only the onboarding ideas that reduce setup friction.

## Blocking order

Live inspector verification -> modifier onboarding research -> final modifier UX decision.

## External tracking

GitHub issues `#6` and `#7` are the current Wayfinder route. The matching Linear issues live in the `XSpoon` project under team `23Maestro`.
