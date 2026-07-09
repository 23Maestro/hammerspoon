# App Automation Discovery Log

This log tracks what works, what fails, and what should become app-specific automation for the Raycast/Hammerspoon local app reader.

## 2026-06-19

### Direction

The durable system should not ask the operator to read raw `AXFocusedUIElement` output. The raw Accessibility tree is capture evidence. Raycast should translate that evidence into a short human label, then let the operator promote one or more candidates into a saved Hammerspoon action.

Preferred flow:

1. Read front app controls.
2. Summarize captured controls in normal language.
3. Let the operator select one or more candidates.
4. Choose an action template.
5. Save as a Hammerspoon hotkey, palette item, or app-specific workflow step.

Raycast owns capture review and promotion. Hammerspoon owns fast repeated execution.

### AI/Natural-Language Layer

There is a useful middle layer between raw capture and saved action:

- Input: compact JSON from the front app, including bundle ID, window title, focused element, visible controls, menu items, popovers, frames, roles, titles, values, and descriptions.
- Output: concise labels such as `Selected extension row`, `Context menu item: Uninstall Extension`, `Shape palette: Rectangle`, or `Color grid cell near red`.
- Constraint: the AI/model should only label and rank candidates from captured evidence. It should not invent selectors, roles, app state, or workflow steps.
- Promotion remains operator-approved through an ActionPanel action.

This makes the Raycast surface usable without turning every AX node into a visible list item.

### Promotion Templates

Initial templates worth supporting:

- Press AX element: verify app/window and press a matching role/title/value/description.
- Open menu then press item: verify app/window/selection, open a menu or context menu, then press a matching `AXMenuItem`.
- Popover coordinate click: verify app/window/popover evidence, then click a coordinate relative to the popover frame.
- Multi-step sequence: ordered steps with per-step verify, delay, and action.

For bulk processing, the promotion UI should support selecting multiple candidates and saving them as a sequence. Each step should store:

- `verify`: app bundle, window title, required role/title/value/description, or required popover/menu evidence.
- `action`: press, click relative point, keyboard shortcut, menu item press, or run existing script.
- `delayMs`: default delay after the step.
- `continueOnMissing`: false by default for destructive or state-changing workflows.

### Raycast Beta Settings Example

The context menu screenshot should be treated as a multi-step app-specific flow, not a single generic `AXPress`.

Likely shape:

1. Verify Raycast Beta is frontmost.
2. Verify the Extensions/settings pane and selected extension row.
3. Open the context menu for the selected row.
4. Verify the context menu contains `Uninstall Extension`.
5. Press the `AXMenuItem` titled `Uninstall Extension`.

What should not happen:

- Do not assume the context menu item exists without reading the open menu.
- Do not blindly click a fixed screen coordinate unless the selected row and menu frame were verified first.
- Do not treat this as equivalent to a Chrome DOM selector.

### Preview And CleanShot Annotation Example

Shape buttons may be directly pressable AX buttons. Those are good candidates for simple `Press AX element` promotion.

Color palettes and shape popovers may expose weak labels. For those, a reliable action can still exist, but it should be app-specific:

1. Verify the annotation toolbar exists.
2. Press the color or shape popover button.
3. Verify the expected popover exists.
4. Click a coordinate relative to the popover frame, not the screen.

This is acceptable when the app does not expose useful labels, but it must be logged as coordinate-backed and app-specific.

### One-Off Vs App-Specific

Use a simple one-off saved action when:

- The element is directly pressable by AX.
- The role/title/value/description are stable.
- One app/window verification is enough.
- The workflow is not destructive.

Create an app-specific module when:

- A context menu, popover, palette, or selected-row state is involved.
- The action needs two or more steps.
- The same UI has multiple similar controls.
- The workflow is destructive or bulk-processing oriented.
- Coordinate clicks are needed.

### Open Questions

- How compact can the capture JSON be while still giving the model enough evidence to label controls?
- Should the first Raycast review surface group candidates by `Focused`, `Buttons`, `Menus`, `Popovers`, and `Coordinates`?
- Should saved actions live in one JSON registry, or should promoted app-specific sequences graduate into Lua modules once repeated enough?

### Raycast Action Menu Failure Log

- `Cmd+B` in Raycast/Raycast Beta is intended to open the selected command's action menu, then type `st` into the action search field.
- Fixed sleeps after `Cmd+K` were unreliable: `st` sometimes typed into the main Raycast search field instead of the action search field.
- Auto-pressing Return after typing was worse because Raycast action-menu results can still be settling.
- AX-clicking the action-search field by scanning for `Search for actions...` was also unreliable in practice and made the flow feel messier.
- Current rollback behavior: send `Cmd+K`, wait up to `1.5s` until the focused AX element contains `Search for actions`, then type `st`; if the action field never gets focus, type nothing.
- Next research target: find a Raycast-supported or AX-stable way to open/focus the action panel search field directly instead of relying on timing.

### Universal Context Menu Primitive

Added first universal local-app primitive:

- Script ID: `local.open-context-menu`
- Raycast title: `Open Focused Local Context Menu`
- Scope: Finder, Raycast, Raycast Beta, and Eagle.
- Contract: this primitive uses `AXShowMenu` only. It should not move the mouse or synthesize a click.
- Explicit fallback script: `local.right-click-focused-target`.

Behavior:

1. Verify the frontmost app is in the allowed set.
2. Prefer selected rows/children/cells from the focused element.
3. Fall back to the focused element when it has a frame.
4. Fall back to selected rows/children/cells from the focused window.
5. Try `AXShowMenu` on that target.
6. If `AXShowMenu` is unavailable, report that state instead of moving/clicking.
7. Use `local.right-click-focused-target` only when coordinate fallback is acceptable.
8. Do not fall back to right-clicking the whole window.

This is intentionally only the first stage. It opens the menu. Repetitive context-menu commands that are unavailable in the top menu, such as Raycast Beta `Uninstall Extension`, should be separate second-stage shortcuts that read the open menu and press a verified `AXMenuItem`.
