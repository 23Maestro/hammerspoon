-- Public Spoon lifecycle with isolated application, keyboard, JSON and action adapters.
local front = "test.chat"
local modals, watcher, calls = {}, nil, {}
local response = "clicked-local-element"
local actions = {
  { id = "dictate-fixture", appBundleID = "test.chat", hotkey = { modifiers = { "ctrl", "alt" }, key = "d" } },
  { id = "other-app", appBundleID = "test.other", hotkey = { modifiers = { "ctrl", "alt" }, key = "d" } },
  { id = "reserved", appBundleID = "test.chat", hotkey = { modifiers = { "ctrl", "alt" }, key = "i" } },
}
local browser = {
  readElementActions = function() return actions end,
  actionsForApp = function(bundle)
    local found = {}
    for _, action in ipairs(actions) do if action.appBundleID == bundle then table.insert(found, action) end end
    return found
  end,
  runElementAction = function(action) table.insert(calls, action.id); return response end,
}
local adapter = {
  json = { decode = function(status) return { status = status } end },
  printf = function() end,
  timer = { absoluteTime = function() return os.clock() * 1000000000 end },
  application = {
    frontmostApplication = function() return { bundleID = function() return front end } end,
    watcher = { activated = 1, deactivated = 2 },
  },
  hotkey = { modal = {} },
}
function adapter.application.watcher.new(callback)
  watcher = { callback = callback }
  function watcher:start() self.enabled = true end
  function watcher:stop() self.enabled = false end
  return watcher
end
function adapter.hotkey.modal.new()
  local modal = { keys = {} }
  function modal:bind(_, key, callback) self.keys[key] = callback end
  function modal:enter() self.enabled = true end
  function modal:exit() self.enabled = false end
  function modal:delete() self.deleted = true end
  table.insert(modals, modal)
  return modal
end
local environment = setmetatable({ hs = adapter, require = function(name)
  assert(name == "scripts.browser_automations")
  return browser
end }, { __index = _G })
local runtime = assert(loadfile("assets/hammerspoon/Spoons/XSpoon.spoon/init.lua", "t", environment))()
local function press(key)
  local count = 0
  for _, modal in ipairs(modals) do
    if modal.enabled and not modal.deleted and modal.keys[key] then
      modal.keys[key](); count = count + 1
    end
  end
  return count
end
local function focus(bundle)
  front = bundle
  watcher.callback(nil, adapter.application.watcher.activated, { bundleID = function() return bundle end })
end
runtime:start()
assert(runtime:status().bindingCount == 2, "Only eligible per-app bindings are registered")
assert(press("i") == 0, "Saved records cannot shadow inspection")
assert(press("d") == 1 and calls[1] == "dictate-fixture", "The frontmost app owns its D binding")
assert(runtime:status().lastResult.ok, "A successful replay receipt must be recognized")
focus("test.unrelated")
assert(press("d") == 0 and #calls == 1, "An unrelated app must not run Dictate")
focus("test.other")
assert(press("d") == 1 and calls[2] == "other-app", "Another app can reuse D without cross-dispatch")
focus("test.chat")
runtime:start()
assert(press("d") == 1 and #calls == 3, "Refreshing routes must not leave duplicate active bindings")
response = "missing-local-element"
assert(press("d") == 1)
assert(runtime:status().lastResult.ok == false, "A registered key or failed lookup is not successful replay")
assert(runtime:status().lastResult.receipt == "missing-local-element", "Preserve the failed replay receipt")
runtime:stop()
assert(press("d") == 0, "Stopped routes must not remain active")
print("PASS: saved-action routing, correct-app guard, chord reuse, reserved key, refresh, failure receipts and stop")
