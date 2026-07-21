# XSpoon

XSpoon is a native macOS control surface for app-aware Hammerspoon automation.

The goal is simple: let a person point at a real app control, capture it once, assign a shortcut, and run it later from a consistent per-app command map. The product is built for the apps people actually use every day, including surfaces that do not expose friendly keyboard shortcuts.

This repository is the canonical home for both sides of the system:

- `apps/XSpoon`: the SwiftUI menu bar app, inspector, capture flow, shortcut catalog, and settings surface.
- `assets/hammerspoon`: the Lua runtime, app adapters, Accessibility helpers, Chrome DOM helpers, and global hotkey bindings.
- `~/.hammerspoon`: the live local runtime path, symlinked back into this repo for the maintained Lua modules.

This is not extension-only maintenance. The Raycast extension still lives at the repo root, but XSpoon app changes are first-class repository changes and should be reviewed, committed, and pushed with the matching Hammerspoon runtime work.

## Product Direction

XSpoon is becoming a small, reliable Mac utility for personal app automation.

The first paid version should make these workflows feel native:

- Capture a button, menu item, field, or selected item from the frontmost app.
- Save the capture as a named app shortcut.
- Reuse the same shortcut key per app without collisions.
- Run saved actions through Hammerspoon with the same per-app dispatcher as the proven hand-written shortcuts.
- Keep clipboard and capture artifacts inspectable so failures can be debugged instead of guessed.

The operating principle is: XSpoon owns the interface and catalog; Hammerspoon owns the automation runtime.

## Current Shortcut Contract

Global XSpoon shortcuts are handled by Hammerspoon:

- `Control-Option-O`: toggle the XSpoon menu.
- `Control-Option-I`: inspect the current app.
- `Control-Option-E`: capture the current element.
- `Control-Option-0`: open the inspector window.

Saved app actions use the same per-app dispatcher pattern as the existing working shortcuts. For example, a physical right-side modifier can be normalized by Karabiner into `ctrl+alt`, then Hammerspoon receives the real `Control-Option-<key>` combo and dispatches the action for the frontmost app.

## Build XSpoon

```sh
cd apps/XSpoon
./script/build_and_run.sh --verify
```

The script builds the Swift package, signs `dist/XSpoon.app`, installs it to `/Applications/XSpoon.app`, registers Launch Services, launches the app, and verifies that the process starts.

## Reload Hammerspoon

```sh
hs -c 'hs.reload()'
```

Hammerspoon may invalidate the CLI message port while reloading. That is expected when the reload succeeds and the IPC connection drops mid-command. Re-run a small check after a second if proof is needed:

```sh
hs -c 'print(hs.inspect(hs.hotkey.getHotkeys()))'
```

## Runtime Map

The main runtime pieces are:

- `assets/hammerspoon/scripts/browser_automations.lua`: global hotkeys, live inspector/capture path, Chrome helpers, local Accessibility primitives, and Raycast script entrypoints.
- `assets/hammerspoon/scripts/automation_core.lua`: semantic per-app dispatcher.
- `assets/hammerspoon/scripts/apps/`: app-specific Lua modules and saved capture actions.
- `apps/XSpoon/Services/HammerspoonClient.swift`: Swift bridge for reading/writing Hammerspoon artifacts.
- `apps/XSpoon/Stores/InspectorStore.swift`: app state, capture flow, shortcut persistence, and clipboard write path.

## Maintenance Rule

Keep XSpoon and Hammerspoon changes in this repository together. A UI change that affects capture, shortcuts, or saved actions should land with the matching Lua runtime change and README update.

Do not treat `apps/XSpoon` as a throwaway prototype folder. It is the app surface for this repository.

Before pushing, check all three maintained surfaces:

```sh
git status --short
git diff -- apps/XSpoon assets/hammerspoon README.md XSPOON_PROJECT_OPERATIONS.md
```

If the change touches capture, shortcuts, saved actions, or Hammerspoon notifications, the push should usually include both:

- the XSpoon Swift files under `apps/XSpoon`
- the Hammerspoon Lua files under `assets/hammerspoon`

Raycast extension-only pushes are only appropriate for changes limited to the Raycast commands, extension metadata, or TypeScript extension code.
