# XSpoon Clean Contract

## Boundaries

| Surface | Owns | Does not own |
|---|---|---|
| Raycast | Job helpers and Chrome DOM scripts, including Prospect ID | XSpoon capture or saved shortcuts |
| XSpoon app | Capture, app catalog, save, deletion | Accessibility replay or global hotkeys |
| Hammerspoon | AX/DOM replay, per-app modal runtime | A second configuration UI |

## Runtime

There is exactly one per-app hotkey mechanism: `hs.hotkey.modal` plus
`hs.application.watcher`, scoped one modal per app. `core.dispatch()`'s
cross-app walk over `matches()` predicates is retired entirely — it is not
kept for the canonical five and layered under the new mechanism for captures.
Modal entry already selects the correct app; there is nothing left to walk.

`init.lua` loads `XSpoon.spoon`. At load, the Spoon builds one
`hs.hotkey.modal` per registered app (hand-written module or JSON capture) and
binds every action that app owns — its hand-written semantic actions
(`primary/search/copy/shortcutS/voicemail`, etc.) and its captured
shortcuts — directly into that app's modal. A single `hs.application.watcher`
tracks exactly one active-modal reference. On activation it exits whatever
modal is currently held (if any) and enters the new frontmost app's modal,
then updates the reference — so a late deactivation event for the app just
left can never exit the modal that now belongs to the newly frontmost app.
Only one modal is ever active system-wide.

**Enforcement, not detection:** two apps' shortcuts on the identical key
combo cannot collide, because only one app's modal exists in the active state
at any moment — there is no shared global table for them to contend over.
The one collision that remains possible is *within* a single app's own
modal (two of its own bindings landing on the same key), checked once at
save time.

Saved actions are data, not generated Lua modules. Their browser identity is
URL/selector/title; their native or web-app identity is bundle ID plus AX
role/title/value/description/actions. The three capture types are button, menu
option, and focus field.

## Capture and replay — physical click is first-class, not a last resort

Finding, from Premiere Pro's Effects Controls: `AXFocus`/`AXPress` reported
failure on a real, visible control, while a physical click at the same screen
point worked every time. The AX identity was correct; the AX replay action
was not reliable. This generalizes past Premiere — any capture can hit an app
whose AX replay is flaky even though its AX identity resolves fine.

Hammerspoon's own mouse-position **capture** during the inspect/click flow is
the unreliable half. Keyboard Maestro's position capture (the `⌃⌥\`` macro
that stashes the current mouse position into a KM variable, from the
`/km-assembler-mode` one-click template) is the half that is proven reliable.
Hammerspoon's click **execution** is fine on its own — it is specifically the
capture that is not. So the split is:

- **Capture** (Keyboard Maestro, triggered from Hammerspoon): when XSpoon's
  inspect+left-click flow fires (the same `leftMouseDown` handler the live
  inspector already uses), Hammerspoon shells out to trigger the existing KM
  macro bound to `⌃⌥\`` that stashes the current mouse position into a KM
  variable. Hammerspoon then reads that variable's value back via AppleScript
  to Keyboard Maestro Engine (`getvariable`) and stores it as the capture's
  real click point, alongside (not instead of) its AX
  role/title/value/description.
- **Replay** (Hammerspoon): `hs.eventtap.leftClick()` at that stored,
  KM-sourced coordinate. Hammerspoon performs the actual click itself —
  execution is not the unreliable part, capture is.

The only change to the AX side is ordering: the KM-sourced physical click is
tried **first** for button captures, with AX-based `findLocalActionElement` +
`performAction` as the fallback, not the other way around. Menu option and
focus field captures are unaffected — they still replay through
`AXShowMenu`/`AXFocus` since those AX paths are the ones actually verified to
work for those capture types.

This is a capture/replay policy change inside XSpoon's own pipeline, adding a
Keyboard Maestro handoff for button *capture* specifically (not replay). It
does not touch Karabiner, or Premiere's existing motion-property macros
(Horizontal/Vertical/Scale/Rotate) — those stay exactly as they are, on their
own rails, unmigrated. Premiere becoming a registered XSpoon app (for other,
non-motion-layer shortcuts) is possible future scope, not part of this pass.

## Hook and test — enforcing single-active-modal

A small runtime hook in `XSpoon.spoon` exposes the currently-held modal
reference (e.g. `XSpoon.activeModalAppID()`), so the invariant is directly
observable rather than assumed. The proof step below exercises it. A minimal
automated check: switch focus rapidly between two apps with bound modals and
assert `activeModalAppID()` never reports both, and never reports the
previous app after the watcher's activation callback has fired for the new
one — this is the concrete regression test for the community-documented
double-fire caveat (`application.watcher` sends activate-then-deactivate on
every switch).

## Save and delete

XSpoon rejects a same-app duplicate shortcut before writing JSON — checked
against that app's modal binding table only, since cross-app collision is
structurally impossible. It writes the JSON, reloads Hammerspoon (which
rebuilds every app's modal from its hand-written actions plus current JSON),
then updates its visible catalog. Delete removes the JSON entry, reloads
Hammerspoon, and removes the matching catalog entry. Hand-written modules
under `assets/hammerspoon/scripts/apps/` are never generated, overwritten, or
deleted — their semantic actions are read and bound into the app's modal at
Spoon load time, same as before, just via modal instead of global bind.

## Proof

1. Capture and save one button, menu option, and focus field.
2. Confirm each modal exists only while its app is frontmost, via
   `XSpoon.activeModalAppID()`.
3. Confirm the identical key combo fires the correct, different action in two
   different apps — no shared table, no shadowing.
4. Rapidly alt-tab between two bound apps and confirm the double-fire/late
   deactivation caveat never leaves the wrong modal active.
5. Confirm a same-app duplicate key is refused at save time.
6. Delete one capture and confirm both stores no longer contain it and its
   modal binding is gone after reload.
7. Capture a button in an app with known-flaky AX replay, confirm the KM
   position-stash variable is read correctly into the capture, and confirm
   Hammerspoon's own click at that coordinate fires reliably without needing
   an AX fallback.
