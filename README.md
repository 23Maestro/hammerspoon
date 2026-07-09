# Hammerspoon

Control 🔨 Hammerspoon directly from Raycast.

## Local Automation Contract

This setup has two runtime engines and three user-facing target labels.

- `Website`: Chrome DOM / selector capture. Use this when the target is a webpage button, field, or element.
- `Mac App`: macOS Accessibility capture. Use this when the target is a selected item, focused field, app button, or context menu in a native app.
- `Web App Window`: Electron/webview app. Use a DOM/devtools adapter for saved controls. Accessibility is only for coarse app/window state, not repeatable button selection.

The core rule is: capture the target with `RightCmd + I`, save the action in Raycast, then run it later through Hammerspoon. Codex is for adding or repairing adapters, not for running the shortcut every time.

Current app-module lanes:

- `Chrome`: website selector capture and URL-scoped clicks.
- `Finder`: selected item -> context menu.
- `Codex`: app-specific macOS Accessibility actions.
- `Notion`: macOS Accessibility first; custom adapter only if needed.
- `Keyboard Maestro`: editor/engine Accessibility helpers.
- `Eagle`: Mac App Accessibility lane.
  - Bundle IDs: `tw.ogdesign.eagle`, `com.eagle.cool`.
  - Current profile: selected/focused target -> frame right-click. Needs user-present selected-item test before deeper actions.
- `Canva`: Web App Window lane; Accessibility first.
  - Bundle ID: `com.canva.CanvaDesktop`.
  - Proven AX limitation: focused `Elements` tab exposes `AXRadioButton` / `AXTabButton`, `AXTitle=Elements`, `AXValue=1`, but Canva does not expose the same tab in the searchable AX tree when it is not already focused.
  - Current menu/process check: Canva exposes no visible Inspect/Developer Tools menu item and is not running with a remote-debugging flag.
  - `ctrl+alt+e`: intentionally returns false until a WebView/DOM adapter exists. It does not type into Canva, use command palette fallback, or click saved coordinates.

Do not add a new app module until a real target proves what it needs. The first test for Mac apps is:

- selected item
- focused field
- button by Accessibility label/role
- context menu by `AXShowMenu`, then frame right-click fallback

Button labels are not universal. A `Delete`, `Share`, or `Log In` button may expose different Accessibility names per app or website. Save repeatable actions scoped to the app bundle ID or Chrome URL, and only promote a shared helper after two or more real targets prove the same shape.

For Web App Window apps like Canva and Notion, skip AX for saved controls once the app proves the target is webview-owned. The capture path should identify the front app, open or attach to that app's inspectable webview, capture selector/XPath/DOM identity, and save that instead.

✅ Requirements

- Requires the installation of Hammerspoon. Go to https://www.hammerspoon.org/ to download.
- With Hammerspoon installed, open your configuration file. By default Hammerspoon configuration file is located at `~/.hammerspoon/init.lua`. If you don't have this file, you can create it by running `touch ~/.hammerspoon/init.lua` in your terminal.
- Add this line at the top of your configuration file: `hs.allowAppleScript(true)`, save the file and reload Hammerspoon.
- All set! You can now control Hammerspoon from Raycast.

## List Scripts setup

The `List Scripts` command allows you to list and run custom Hammerspoon scripts directly from Raycast.

To set it up, you first need to define a lua global variable in your Hammerspoon configuration file, this variable should be a table that contains two functions, `list` and `execute`. These two functions are going to be called by this raycast extension when listing and running scripts:

- The `list` function should return a json array describing your scripts. each item in the array can have the following properties:
  - `id`: a unique identifier for the script (must be unique, it is used to run scripts) **(required)**.
  - `name`: the name of the script to be displayed in Raycast **(required)**.
  - `description`: a short description of the script to be displayed in Raycast.
  - `keywords`: an array of keywords to help with searching for the script in Raycast.
- The `execute` function expects to receive a script id as an argument, and execute the corresponding script.

Finally, you need to put the name of the global variable you created in your Hammerspoon configuration file in the `List Scripts` command preferences.

Example of a Hammerspoon configuration file with the `List Scripts` setup:

```lua
-- <<rest of your configuration file>>

local scriptDefs = {
  { id = 'test', name = 'Test', description = 'This is a test script' },
  { id = 'test2', name = 'Test 2', description = 'This is another test script' }
}

local scriptActions = {
  test = function ()
    hs.alert.show('Test script executed')
  end,
  test2 = function ()
    hs.alert.show('Test 2 script executed')
  end
}

__SCRIPTS__ = {
  list = function ()
    return hs.json.encode(scriptDefs)
  end,
  execute = function (id)
    local scriptAction = scriptActions[id]

    if not scriptAction then
      error('User Script with id "' .. id .. '" not found')
    end

    scriptAction()
  end
}
```
