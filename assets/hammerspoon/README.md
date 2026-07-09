# Hammerspoon Browser Automations

Use `scripts/browser_automations.lua` for repeatable Chrome DOM actions.

For local app automation discoveries, promotion rules, and app-specific workflow notes, use `APP_AUTOMATION_DISCOVERY_LOG.md`.

## DevTools Copy Choice

Prefer this order when capturing a target from Chrome DevTools:

1. `Copy selector` when the selector is anchored by an ID, class, ARIA label, or stable DOM shape.
2. `Copy XPath` when the selector is too broad or the target is easier to anchor from a known container.
3. `Copy full XPath` only as a last resort. It is usually brittle because it depends on every ancestor position.

The live runtime should symlink back to this extension source:

```bash
ln -sfn /Users/singleton23/Raycast/hammerspoon/assets/hammerspoon/scripts/browser_automations.lua \
  /Users/singleton23/.hammerspoon/scripts/browser_automations.lua
```

The native Hammerspoon `init.lua` only needs the stable `require("scripts.browser_automations")` bridge.

## Adding A Script

Add an entry to the `catalog` table:

```lua
{
  id = "chrome.example",
  name = "Chrome Example",
  description = "Clicks a visible target in Chrome.",
  keywords = { "chrome", "example" },
  run = function()
    return M.click({
      selector = "#some-id button.save",
      xpath = "//*[@id=\"some-id\"]//button[contains(., 'Save')]",
      label = "Save",
    })
  end,
}
```

Raycast's Hammerspoon extension reads the global `__SCRIPTS__` object. This config sets:

```lua
__SCRIPTS__ = chromeBrowserAutomations
```

## Clipboard Variable Flow

Raycast's native Hammerspoon `List Scripts` command executes by script ID and does not pass custom arguments. For quick browser targets, use the clipboard as the variable:

1. In Chrome DevTools, choose `Copy selector` or `Copy XPath`.
2. Run `Chrome Click Clipboard Selector` or `Chrome Click Clipboard XPath` from Raycast.
3. Promote the working selector into the `catalog` table only if it becomes a repeated workflow.

`Chrome Click Clipboard Selector` accepts either a raw selector or a captured element JSON payload.

## Hotkeys

- `ctrl+alt+i`: Auto-pick a selector from the current pointer location

## Selector Picker

Use `ctrl+alt+i` instead of automating Chrome DevTools menus. It injects a picker into the active page, waits briefly, then triggers the trusted current-pointer click shortcut (`ctrl+alt+return`):

1. Press `ctrl+alt+i`.
2. Keep the pointer over the page element you want.
3. Hammerspoon sends `ctrl+alt+return`.
4. A JSON element payload is copied to the clipboard.
5. Run `Chrome Click Clipboard Selector` to test it.
6. Promote it into the catalog when it becomes a repeated browser workflow.

The manual Raycast action `Chrome Pick Selector` still arms the picker and waits for your next click.

Each captured element is also saved to:

```text
/Users/singleton23/.hammerspoon/browser_element_latest.json
```

Payload shape:

```json
{
  "kind": "hammerspoon-browser-element",
  "selector": "#example",
  "url": "https://example.com/page",
  "title": "Example Page",
  "text": "Save",
  "tag": "button",
  "id": "",
  "className": "btn btn-primary",
  "capturedAt": "2026-06-11T00:00:00.000Z"
}
```

That file is the handoff point for Raycast forms that create durable element actions.

This is more reliable than right-clicking `Inspect` and driving DevTools UI because it reads the DOM target directly from the page click.
