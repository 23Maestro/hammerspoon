# XSpoon Capture & Menu Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the per-app inspect/capture/store cycle by fixing JSON write targets, refining left-click-to-capture behavior, implementing right-click-to-read for menu items, and wiring captured menu options into the dispatcher.

**Architecture:** XSpoon (SwiftUI) captures UI element snapshots and writes them to `~/.hammerspoon/browser_element_actions.json`. Hammerspoon (Lua) reads that JSON and dispatches saved actions through `automation_core.lua`'s per-app module contract. The live inspector eventtap captures on left-click and stops on Escape. Menu options require a two-step capture (opener → menu item) stored as a paired action in the JSON.

**Tech Stack:** Swift/SwiftUI (XSpoon app), Lua (Hammerspoon runtime), JSON (element action storage), macOS Accessibility API

## Global Constraints

- Hammerspoon IPC calls must be serialized — never parallel `hs -c` calls.
- Element actions JSON lives at `~/.hammerspoon/browser_element_actions.json` — XSpoon writes, Hammerspoon reads.
- Per-app modules in `scripts/apps/<app>.lua` own action dispatch — saved actions route through `automationCore.dispatch()`, not competing global hotkeys.
- Deletion is a two-store operation: remove from `XSpoon.myApps` (UserDefaults) AND `browser_element_actions.json`, plus mark deleted IDs so built-in catalog merge can't restore them.
- All Hammerspoon reloads use `hs.timer.doAfter(0.1, hs.reload)` — never direct `hs.reload()` from CLI.

---

### Task 1: Fix JSON Write Target — ElementAction windowFrame

The `ElementAction` struct writes `frame` from the snapshot but does not persist the window frame at capture time. The Lua `findLocalActionElement` uses `action.windowFrame` to compute relative coordinates for Electron/WebView apps. Without it, the coordinate fallback path always fails.

**Files:**
- Modify: `apps/XSpoon/Services/HammerspoonClient.swift:141-189` (ElementAction init)
- Modify: `assets/hammerspoon/scripts/browser_automations.lua:1074-1092` (verify Lua reads windowFrame)

**Interfaces:**
- Consumes: `ElementSnapshot.frame` (SnapshotRect), `AppContext.windowTitle`
- Produces: `ElementAction.windowFrame` field in JSON — `{ x, y, w, h }` matching the Lua contract

- [ ] **Step 1: Add windowFrame to ElementAction**

In `HammerspoonClient.swift`, add a `windowFrame` property to `ElementAction`:

```swift
struct ElementAction: Codable, Equatable {
    // ... existing fields ...
    var windowFrame: SnapshotRect?
    // ...
}
```

In the `init(app:shortcut:snapshot:)` initializer, after setting `frame`:

```swift
windowFrame = snapshot.windowFrame
```

- [ ] **Step 2: Add windowFrame to ElementSnapshot**

`ElementSnapshot` currently has `frame: SnapshotRect?` but no `windowFrame`. The Hammerspoon Lua payload from `localElementPayload` already writes `windowFrame` to the JSON file. Verify the Swift decoder picks it up:

In `InspectorModels.swift`, add to `ElementSnapshot`:

```swift
var windowFrame: SnapshotRect?
```

- [ ] **Step 3: Verify the Lua payload shape**

Read `browser_automations.lua` around `localElementPayload` to confirm the live/captured JSON includes `windowFrame`. The function already writes:

```lua
windowFrame = {
  x = winFrame.x, y = winFrame.y,
  w = winFrame.w, h = winFrame.h,
},
```

No Lua change needed — just verification.

- [ ] **Step 4: Test round-trip**

1. Build XSpoon in Xcode.
2. Open any native app (e.g., Finder).
3. Inspect → Capture a button.
4. Save the shortcut.
5. Check `~/.hammerspoon/browser_element_actions.json` — the new entry should have both `frame` and `windowFrame` with real coordinates.

- [ ] **Step 5: Commit**

```bash
git add apps/XSpoon/Services/HammerspoonClient.swift apps/XSpoon/Models/InspectorModels.swift
git commit -m "feat: persist windowFrame in ElementAction for coordinate replay"
```

---

### Task 2: Refine Left-Click Capture — Swallow Click, Show Feedback

The live inspector eventtap captures on `leftMouseDown` and returns `true` to swallow the click. But the current flow immediately stops the inspector and posts `captureCurrentElement`. This means the user's click never reaches the target app — correct for capture, but needs visual feedback in XSpoon's overlay.

**Files:**
- Modify: `assets/hammerspoon/scripts/browser_automations.lua:831-848` (eventtap handler)
- Modify: `apps/XSpoon/Services/StatusItemController.swift:181-192` (handleLiveElementUpdated)

**Interfaces:**
- Consumes: `com.singleton23.XSpoon.captureCurrentElement` distributed notification
- Produces: Updated overlay showing "Captured [element]" before dismissing

- [ ] **Step 1: Add capture flash notification**

In `browser_automations.lua`, after `updateLiveInspector()` in the leftMouseDown branch, post a notification with the captured element's title before stopping:

```lua
if event:getType() == hs.eventtap.event.types.leftMouseDown then
  updateLiveInspector()
  local file = io.open(LIVE_LATEST_ELEMENT_PATH, "r")
  local title = "element"
  if file then
    local ok, data = pcall(hs.json.decode, file:read("*a"))
    file:close()
    if ok and data then
      title = data.axTitle or data.title or data.axDescription or "element"
    end
  end
  notify("Captured " .. tostring(title):sub(1, 30))
  stopLiveInspector()
  hs.distributednotifications.post("com.singleton23.XSpoon.captureCurrentElement")
  return true
end
```

- [ ] **Step 2: Verify overlay updates on capture**

In `StatusItemController.swift`, `handleCaptureUpdated()` already calls `store.refresh()` and `stopInspecting()`. Verify the overlay shows the captured element title briefly (the existing `autoDismiss: true` with 2.2s delay handles this).

No code change needed — just verify the existing flow shows the right snapshot.

- [ ] **Step 3: Test the capture flow**

1. Build XSpoon, click "Inspect" in the menu bar.
2. Hover over a button in any app — overlay should show its name.
3. Left-click on the button — click should NOT reach the app; overlay should flash "Captured [name]"; the Create Element sheet should appear.
4. Press Escape during inspect — should stop without capturing.

- [ ] **Step 4: Commit**

```bash
git add assets/hammerspoon/scripts/browser_automations.lua
git commit -m "feat: show capture flash notification on left-click inspect"
```

---

### Task 3: Right-Click to Read Menu Items

When the live inspector is active and the user right-clicks (or the element has `AXShowMenu`), XSpoon should read the resulting menu items and present them for individual capture. This enables the two-step menu option flow: first capture what opens the menu, then capture which option to click.

**Files:**
- Modify: `assets/hammerspoon/scripts/browser_automations.lua:831-848` (add rightMouseDown to eventtap)
- Modify: `assets/hammerspoon/scripts/browser_automations.lua` (new `readMenuItems` function)
- Modify: `apps/XSpoon/Models/InspectorModels.swift` (add MenuItemSnapshot)
- Modify: `apps/XSpoon/Stores/InspectorStore.swift` (handle menu item list)

**Interfaces:**
- Consumes: `rightMouseDown` event during live inspector
- Produces: `com.singleton23.XSpoon.menuItemsRead` notification; `~/.hammerspoon/menu_items_latest.json` file

- [ ] **Step 1: Add rightMouseDown to the eventtap**

In `browser_automations.lua`, add `hs.eventtap.event.types.rightMouseDown` to the eventtap event list:

```lua
liveInspectorCaptureTap = hs.eventtap.new({
  hs.eventtap.event.types.leftMouseDown,
  hs.eventtap.event.types.rightMouseDown,
  hs.eventtap.event.types.keyDown,
}, function(event)
```

- [ ] **Step 2: Handle rightMouseDown — read menu items from the hovered element**

Add a `rightMouseDown` branch that performs `AXShowMenu` on the current target, reads the resulting `AXChildren` menu items, writes them to JSON, and posts a notification:

```lua
if event:getType() == hs.eventtap.event.types.rightMouseDown then
  local target = localContextTarget()
  if not target then
    return false
  end

  local items = {}
  local showOk = pcall(function() target:performAction("AXShowMenu") end)
  if showOk then
    hs.timer.usleep(200000)
    local menu = target:attributeValue("AXChildren")
    if type(menu) == "table" then
      for _, child in ipairs(menu) do
        local role = axAttribute(child, "AXRole")
        if role == "AXMenu" then
          local menuChildren = child:attributeValue("AXChildren") or {}
          for _, item in ipairs(menuChildren) do
            local itemRole = axAttribute(item, "AXRole")
            if itemRole == "AXMenuItem" then
              table.insert(items, {
                role = itemRole,
                title = axAttribute(item, "AXTitle"),
                value = axAttribute(item, "AXValue"),
                description = axAttribute(item, "AXDescription"),
                enabled = item:attributeValue("AXEnabled") ~= false,
              })
            end
          end
          break
        end
      end
    end
    pcall(function() target:performAction("AXCancel") end)
  end

  if #items > 0 then
    local encoded = hs.json.encode(items, true)
    local file = io.open(os.getenv("HOME") .. "/.hammerspoon/menu_items_latest.json", "w")
    if file then
      file:write(encoded)
      file:close()
    end
    notify(tostring(#items) .. " menu items")
    hs.distributednotifications.post("com.singleton23.XSpoon.menuItemsRead")
  else
    notify("No menu items found")
  end

  return true
end
```

- [ ] **Step 3: Add MenuItemSnapshot to InspectorModels.swift**

```swift
struct MenuItemSnapshot: Codable, Identifiable {
    var id: String { title }
    let role: String
    let title: String
    let value: String?
    let description: String?
    let enabled: Bool
}
```

- [ ] **Step 4: Read menu items in InspectorStore**

Add a `@Published var menuItems: [MenuItemSnapshot] = []` property and a method to load the JSON:

```swift
func loadMenuItems() {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hammerspoon/menu_items_latest.json")
    guard let data = try? Data(contentsOf: url),
          let items = try? JSONDecoder().decode([MenuItemSnapshot].self, from: data) else {
        menuItems = []
        return
    }
    menuItems = items
}
```

- [ ] **Step 5: Observe the menuItemsRead notification in StatusItemController**

Add to the notification observers array:

```swift
observeDistributed(.init("com.singleton23.XSpoon.menuItemsRead")) { [weak self] in
    self?.store.loadMenuItems()
}
```

- [ ] **Step 6: Test right-click menu read**

1. Build XSpoon, start inspecting.
2. Hover over a UI element that has a context menu (e.g., a Finder sidebar item).
3. Right-click — the menu should briefly appear, items should be read, and a notification should show "N menu items".
4. Check `~/.hammerspoon/menu_items_latest.json` for the item list.

- [ ] **Step 7: Commit**

```bash
git add assets/hammerspoon/scripts/browser_automations.lua \
  apps/XSpoon/Models/InspectorModels.swift \
  apps/XSpoon/Stores/InspectorStore.swift \
  apps/XSpoon/Services/StatusItemController.swift
git commit -m "feat: right-click during inspect reads menu items for two-step capture"
```

---

### Task 4: Two-Step Menu Option Capture UI

When a `menuOption` capture is pending and menu items have been read, present a picker so the user can select which menu option to save. The saved `ElementAction` stores both the opener element and the target menu item title, so replay can open the menu and then click the right item.

**Files:**
- Modify: `apps/XSpoon/Views/ContentView.swift` (CreateElementSheet — add menu item picker)
- Modify: `apps/XSpoon/Models/InspectorModels.swift` (PendingElementCapture — add selectedMenuItem)
- Modify: `apps/XSpoon/Services/HammerspoonClient.swift` (ElementAction — add menuItemTitle)
- Modify: `assets/hammerspoon/scripts/browser_automations.lua` (pressLocalAction — handle menu replay)

**Interfaces:**
- Consumes: `store.menuItems: [MenuItemSnapshot]`, `PendingElementCapture`
- Produces: `ElementAction` with `menuItemTitle` field; Lua `pressLocalAction` opens menu then clicks item

- [ ] **Step 1: Add menuItemTitle to ElementAction**

In `HammerspoonClient.swift`:

```swift
struct ElementAction: Codable, Equatable {
    // ... existing fields ...
    var menuItemTitle: String?
    // ...
}
```

- [ ] **Step 2: Add selectedMenuItem to PendingElementCapture**

In `InspectorModels.swift`:

```swift
struct PendingElementCapture: Identifiable, Equatable {
    let id = UUID()
    var snapshot: ElementSnapshot
    var appID: String
    var kind: AdapterKind
    var selectedMenuItem: String?
}
```

- [ ] **Step 3: Add menu item picker to CreateElementSheet**

In `ContentView.swift`, inside `CreateElementSheet`, after the element summary section and before the key picker, add a conditional menu item picker:

```swift
if pending.kind == .menuOption && !store.menuItems.isEmpty {
    VStack(alignment: .leading, spacing: 6) {
        Text("Choose a menu option").font(.headline)
        ForEach(store.menuItems.filter(\.enabled)) { item in
            Button {
                selectedMenuItem = item.title
                if action.hasPrefix("Choose ") {
                    action = "Choose \(item.title)"
                }
            } label: {
                HStack {
                    Text(item.title)
                    Spacer()
                    if selectedMenuItem == item.title {
                        Image(systemName: "checkmark")
                    }
                }
                .padding(8)
                .background(selectedMenuItem == item.title ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }
}
```

Add `@State private var selectedMenuItem: String?` to the sheet.

- [ ] **Step 4: Pass menuItemTitle into ElementAction on save**

When saving the shortcut in `InspectorStore.saveElement`, pass the selected menu item to `HammerspoonClient.saveElementAction`. Add `menuItemTitle` to the `ElementAction` init or set it after construction:

```swift
func saveElement(pending: PendingElementCapture, shortcut: AppShortcut) {
    // ... existing code ...
    do {
        try hammerspoon.saveElementAction(app: app, shortcut: shortcut, snapshot: pending.snapshot, menuItemTitle: pending.selectedMenuItem)
        // ...
    }
}
```

Update `HammerspoonClient.saveElementAction` signature:

```swift
func saveElementAction(app: MyAppDefinition, shortcut: AppShortcut, snapshot: ElementSnapshot, menuItemTitle: String? = nil) throws {
    var action = ElementAction(app: app, shortcut: shortcut, snapshot: snapshot)
    action.menuItemTitle = menuItemTitle
    // ... rest unchanged ...
}
```

- [ ] **Step 5: Implement menu replay in Lua**

In `browser_automations.lua`, update `pressLocalAction` to handle actions with `menuItemTitle`:

```lua
if action.menuItemTitle and action.menuItemTitle ~= "" then
  local showOk = pcall(function() element:performAction("AXShowMenu") end)
  if not showOk then
    return hs.json.encode({ status = "menu-open-failed" })
  end
  hs.timer.usleep(200000)

  local menuItem = walkAx(element, function(child)
    return axAttribute(child, "AXRole") == "AXMenuItem"
      and axAttribute(child, "AXTitle") == action.menuItemTitle
  end, 4)

  if not menuItem then
    pcall(function() element:performAction("AXCancel") end)
    return hs.json.encode({ status = "menu-item-not-found", menuItemTitle = action.menuItemTitle })
  end

  local pressOk = pcall(function() menuItem:performAction("AXPress") end)
  if not pressOk then
    return hs.json.encode({ status = "menu-item-press-failed" })
  end

  return hs.json.encode({
    status = "performed-menu-action",
    menuItemTitle = action.menuItemTitle,
    role = axAttribute(element, "AXRole"),
    title = axAttribute(element, "AXTitle"),
  })
end
```

Insert this block at the top of `pressLocalAction`, before the existing `localReplayAction` call.

- [ ] **Step 6: Update canSave for menu options**

In `CreateElementSheet`, update `canSave`:

```swift
private var canSave: Bool {
    if pending.kind == .menuOption {
        return selectedMenuItem != nil && !key.isEmpty
    }
    return !key.isEmpty
}
```

- [ ] **Step 7: Test two-step menu capture**

1. Build XSpoon, inspect a Finder sidebar item.
2. Right-click to read its menu items — items should appear in the Create Element sheet.
3. Select a menu option from the picker.
4. Assign a key, save.
5. Check `browser_element_actions.json` — should have `menuItemTitle`.
6. Press the assigned shortcut while the app is frontmost — should open the menu and click the saved option.

- [ ] **Step 8: Commit**

```bash
git add apps/XSpoon/Views/ContentView.swift \
  apps/XSpoon/Models/InspectorModels.swift \
  apps/XSpoon/Services/HammerspoonClient.swift \
  apps/XSpoon/Stores/InspectorStore.swift \
  assets/hammerspoon/scripts/browser_automations.lua
git commit -m "feat: two-step menu option capture with right-click read and menu replay"
```

---

### Task 5: Generate Per-App Module From XSpoon Capture

The old `saved_actions.lua` fallback is dead. The proven contract is: capture → generate or patch an app module in `scripts/apps/<app>.lua` → register in `init.lua` → reload → physical proof. XSpoon must produce a real module, not just JSON data.

**Rules:**
- Built-in/proven modules (`chrome.lua`, `codex.lua`, `finder.lua`, etc.) are never overwritten or deleted from source. XSpoon can add actions to them but must not clobber tested code.
- New apps that have no module get a generated one. The template follows the proven module shape: `M.id`, `M.matches(context)`, `M.actions = { semanticAction = function(context) ... end }`.
- The generated module reads its action data from `browser_element_actions.json` — it is a thin wrapper that calls `browser.runElementAction(action)` for each saved action, not a copy of the JSON inlined into Lua.
- Delete shortcut = remove capture data + remove generated handler from module. If the module becomes empty (no actions left), remove the module file and its `init.lua` registration.
- Delete app = remove all capture data for that app + remove generated module + unregister.

**Files:**
- Create: `apps/XSpoon/Services/ModuleGenerator.swift` (generates `scripts/apps/<slug>.lua` from capture data)
- Modify: `apps/XSpoon/Services/HammerspoonClient.swift` (add `generateAppModule` / `removeAppModule` methods)
- Modify: `apps/XSpoon/Stores/InspectorStore.swift` (call module generation after save, module removal after delete)
- Modify: `assets/hammerspoon/scripts/browser_automations.lua` (add `actionsForApp(bundleID)` helper that filters `readElementActions()` by bundle ID)

**Interfaces:**
- Consumes: `browser_element_actions.json`, `MyAppDefinition` (app metadata)
- Produces: `~/.hammerspoon/scripts/apps/<slug>.lua` module file; updated `init.lua` registration; Hammerspoon reload receipt

- [ ] **Step 1: Add actionsForApp helper to browser_automations.lua**

```lua
function M.actionsForApp(bundleID)
  local matched = {}
  for _, action in ipairs(readElementActions()) do
    if tostring(action.appBundleID or "") == bundleID then
      table.insert(matched, action)
    end
  end
  return matched
end
```

- [ ] **Step 2: Create the module template**

In `ModuleGenerator.swift`, define a function that writes a Lua module file:

```swift
struct ModuleGenerator {
    static func generate(app: MyAppDefinition, to url: URL) throws {
        let slug = app.id
        let bundleID = app.bundleIdentifier
        let lua = """
        local browser = require("scripts.browser_automations")

        local M = {}
        M.id = "\(slug)"

        function M.matches(context)
          return context.bundleID == "\(bundleID)"
        end

        local function savedAction(semanticAction)
          return function(context)
            for _, action in ipairs(browser.actionsForApp("\(bundleID)")) do
              if tostring(action.semanticAction or "") == semanticAction then
                return browser.runElementAction(action)
              end
            end
            return false
          end
        end

        M.actions = {}
        for _, action in ipairs(browser.actionsForApp("\(bundleID)")) do
          local semantic = tostring(action.semanticAction or "")
          if semantic ~= "" then
            M.actions[semantic] = savedAction(semantic)
          end
        end

        return M
        """
        try lua.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 3: Add generateAppModule and removeAppModule to HammerspoonClient**

```swift
func generateAppModule(for app: MyAppDefinition) throws {
    let modulesDir = home.appendingPathComponent(".hammerspoon/scripts/apps")
    try FileManager.default.createDirectory(at: modulesDir, withIntermediateDirectories: true)
    let moduleURL = modulesDir.appendingPathComponent("\(app.id).lua")

    // Never overwrite built-in modules
    let builtIns: Set<String> = ["chrome", "codex", "finder", "keyboard_maestro"]
    guard !builtIns.contains(app.id) else { return }

    try ModuleGenerator.generate(app: app, to: moduleURL)
}

func removeAppModule(for app: MyAppDefinition) throws {
    let builtIns: Set<String> = ["chrome", "codex", "finder", "keyboard_maestro"]
    guard !builtIns.contains(app.id) else { return }

    let moduleURL = home.appendingPathComponent(".hammerspoon/scripts/apps/\(app.id).lua")
    try? FileManager.default.removeItem(at: moduleURL)
}
```

- [ ] **Step 4: Call module generation after save in InspectorStore**

In `saveElement`, after `hammerspoon.saveElementAction(...)`:

```swift
try hammerspoon.generateAppModule(for: app)
```

- [ ] **Step 5: Call module removal after delete in InspectorStore**

In `deleteApp`, after removing capture data:

```swift
try hammerspoon.removeAppModule(for: app)
```

In `deleteShortcut`, check if the app has any remaining shortcuts — if not, remove the module:

```swift
if myApps[index].shortcuts.isEmpty {
    try? hammerspoon.removeAppModule(for: app)
}
```

- [ ] **Step 6: Update status messages**

After successful module generation and Hammerspoon reload:

```swift
case .success(let receipt):
    status = "Saved \(app.name) shortcut and generated module"
```

- [ ] **Step 7: Test end-to-end**

1. Build XSpoon. Capture a button in an app that has no built-in module (e.g., Preview).
2. Save the shortcut with a key assignment.
3. Verify `~/.hammerspoon/scripts/apps/preview.lua` was created with correct bundle ID and semantic action.
4. Reload Hammerspoon. Press the assigned key with Preview frontmost.
5. Verify the action fires through `automationCore.dispatch` → generated module → `browser.runElementAction`.
6. Delete the shortcut in XSpoon. Verify the module file is removed.

- [ ] **Step 8: Commit**

```bash
git add apps/XSpoon/Services/ModuleGenerator.swift \
  apps/XSpoon/Services/HammerspoonClient.swift \
  apps/XSpoon/Stores/InspectorStore.swift \
  assets/hammerspoon/scripts/browser_automations.lua
git commit -m "feat: generate per-app Lua modules from XSpoon captures"
```

---

### Task 6: Merge Branch to Master

Once all tasks pass, merge the feature branch.

**Files:**
- No file changes — git operations only.

- [ ] **Step 1: Verify clean state**

```bash
git status
git log --oneline master..HEAD
```

- [ ] **Step 2: Merge to master**

```bash
git checkout master
git merge agent/xspoon-live-inspector-handoff --no-ff -m "Merge per-app inspect, capture, and store"
git push origin master
```

- [ ] **Step 3: Clean up**

```bash
git branch -d agent/xspoon-live-inspector-handoff
git push origin --delete agent/xspoon-live-inspector-handoff
```
