# XSpoon

XSpoon is the native macOS app surface for the Hammerspoon automation system in this repository.

It is designed to become a small paid Mac utility for people who live across a handful of apps and need reliable shortcuts for controls that were never built with keyboard workflows in mind.

## What XSpoon Owns

- Menu bar entry point.
- Inspector window.
- Live capture review.
- App shortcut catalog.
- Saved element action flow.
- User-facing shortcut labels and settings.

## What Hammerspoon Owns

- Global hotkeys.
- Accessibility reads and presses.
- Chrome DOM/selector helpers.
- Per-app dispatch.
- Saved action execution.
- Runtime notifications back to XSpoon.

The boundary matters: XSpoon should make capture and shortcut setup feel native; Hammerspoon should remain the engine that touches apps.

## Saved Actions

`~/.hammerspoon/xspoon_registry.json` is the canonical per-app registry. XSpoon
projects its My Apps rows from that document and writes saves/deletions there;
Hammerspoon reads the same captured payloads for its app-scoped bindings. The
legacy action file and UserDefaults catalog are backed up during one-time import
and are no longer written as parallel stores.

Review labels distinguish Verified, Unverified, Blocked, Needs Recapture, and
Legacy Script records. Inherited script commands remain managed by their existing
implementations; blocked captures are visible but not bound. See the
[migration receipt](../../docs/2026-10-29-per-app-registry.md).

## Current Global Shortcuts

- `Control-Option-O`: toggle XSpoon menu.
- `Control-Option-I`: inspect current app.
- `Enter` while inspecting: capture the control under the pointer on key release.
- `Escape`: cancel inspection. `Right Command-E` is available for saved app shortcuts.
- `Control-Option-0`: open inspector.

## Build And Run

```sh
cd apps/XSpoon
./script/build_and_run.sh --verify
```

The build script signs and installs `/Applications/XSpoon.app`. Keep this path stable so macOS permissions and user testing stay predictable.

The app build does not install or rewrite Hammerspoon's user configuration. The
live setup links `assets/hammerspoon/scripts` into `~/.hammerspoon/scripts` and
`assets/hammerspoon/Spoons/XSpoon.spoon` into `~/.hammerspoon/Spoons/XSpoon.spoon`.
After the existing app modules and global routes are registered, `init.lua` must
start the saved-action runtime:

```lua
hs.loadSpoon("XSpoon")
xspoonRuntime = spoon.XSpoon:start()
```

Keep that startup in one place. The user-owned `init.lua` is outside this source
repository; do not overwrite it with a generated configuration.

## Repository Contract

XSpoon lives inside the Hammerspoon repository on purpose. Do not ship app behavior changes as if this were only a Raycast extension repo.

When updating capture, shortcuts, saved actions, or inspector behavior, review both sides before pushing:

```sh
git diff -- apps/XSpoon assets/hammerspoon
```

If XSpoon writes a new action shape, the Hammerspoon runtime must know how to execute it. If Hammerspoon adds or renames a notification, XSpoon must read the matching event.

## Product Standard

The app should feel like a future Mac utility, not a debug panel:

- Controls should be visible without explaining them in the UI.
- Captured elements should copy enough detail for debugging.
- Per-app shortcuts should use the same dispatcher path as proven hand-written shortcuts.
- Settings should describe the current shortcut contract accurately.
- Failed automation should leave a concrete status, not a guess.
