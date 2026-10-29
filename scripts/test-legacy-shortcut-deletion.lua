-- Real public registry guards and key dispatch with isolated data and OS adapters.
local registry = { schemaVersion = 1, apps = {}, disabledLegacyShortcuts = {} }
local front, calls = "test.chat", { search = 0, context = 0 }
local callbacks = {}
local notifier = { show = function() end }
local hsAdapter = {
  configdir = "/fixture",
  json = { decode = function() return registry end },
  printf = function() end,
  application = { frontmostApplication = function()
    return { bundleID = function() return front end, name = function() return "Fixture" end, focusedWindow = function() return nil end }
  end },
  hotkey = { bind = function(_, key, callback) callbacks[key] = callback end },
}
local environment = setmetatable({ hs = hsAdapter, io = { open = function(path)
  assert(path == "/fixture/xspoon_registry.json")
  return { read = function() return "fixture-json" end, close = function() end }
end }, require = function(name) assert(name == "scripts.notify"); return notifier end }, { __index = _G })
local browser = assert(loadfile("assets/hammerspoon/scripts/browser_automations.lua", "t", environment))()
environment.require = function(name)
  if name == "scripts.notify" then return notifier end
  assert(name == "scripts.browser_automations")
  return browser
end
local core = assert(loadfile("assets/hammerspoon/scripts/automation_core.lua", "t", environment))()
core.registerApp({ id = "fixture", matches = function() return true end,
  actions = { shortcutS = function() calls.search = calls.search + 1; return true end } })
core.bind({ { modifiers = { "ctrl", "alt" }, key = "s", action = "shortcutS" } })
browser.openFocusedLocalContextMenu = function() calls.context = calls.context + 1 end
browser.bindContextMenuHotkey()
callbacks.s(); callbacks.m()
assert(calls.search == 1 and calls.context == 1, "Existing routes must remain active before deletion")
registry.disabledLegacyShortcuts = {
  { id = "search", appBundleID = "test.chat", modifiers = { "alt", "ctrl" }, key = "s" },
  { id = "context", appBundleID = "test.chat", modifiers = { "alt", "ctrl" }, key = "m" },
}
callbacks.s(); callbacks.m()
assert(calls.search == 1 and calls.context == 1, "Deleted legacy routes must stop executing, not just lose their rows")
front = "test.other"
callbacks.s(); callbacks.m()
assert(calls.search == 2 and calls.context == 2, "Deleting in one app must not disable another app")
registry.schemaVersion = 999
callbacks.s(); callbacks.m()
assert(calls.search == 2 and calls.context == 2, "Unreadable deletion policy must fail closed")
print("PASS: real Search/context dispatch honors deleted legacy routes per app and fails closed on invalid policy")
