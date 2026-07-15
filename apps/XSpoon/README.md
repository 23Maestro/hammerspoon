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

## Current Global Shortcuts

- `Control-Option-O`: toggle XSpoon menu.
- `Control-Option-I`: inspect current app.
- `Control-Option-E`: capture element.
- `Control-Option-0`: open inspector.

## Build And Run

```sh
cd apps/XSpoon
./script/build_and_run.sh --verify
```

The build script signs and installs `/Applications/XSpoon.app`. Keep this path stable so macOS permissions and user testing stay predictable.

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
