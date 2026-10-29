local tapped, notices, focused = nil, 0, false
local bundleID = "com.openai.codex"
local field = {}
function field:attributeValue(name)
  return ({ AXRole = "AXTextField", AXDescription = "Search keyboard shortcuts", AXFocused = focused })[name]
end
function field:setAttributeValue(name, value) if name == "AXFocused" then focused = value end end
function field:performAction() return true end
local root = { attributeValue = function(_, name) if name == "AXChildren" then return { field } end end }
local app = { bundleID = function() return bundleID end, allWindows = function() return { {} } end }
local hsAdapter = {
  application = { frontmostApplication = function() return app end },
  axuielement = { windowElement = function() return root end },
  keycodes = { map = { s = 1, ["'"] = 39 } },
  eventtap = { event = { types = { keyDown = 10 } } },
}
function hsAdapter.eventtap.new(_, callback)
  tapped = callback
  return { start = function() end, stop = function() tapped = nil end }
end
local environment = setmetatable({ hs = hsAdapter, require = function(name)
  assert(name == "scripts.notify")
  return { show = function() notices = notices + 1 end }
end }, { __index = _G })
local module = assert(loadfile("assets/hammerspoon/scripts/apps/codex.lua", "t", environment))()
module.start()
local function plain(key)
  return tapped and tapped({ getFlags = function() return {} end, getKeyCode = function() return key end }) or false
end
assert(not plain(1), "Plain S must type normally, not focus Search")
assert(not plain(39), "Plain apostrophe must type normally")
assert(notices == 0, "Normal typing must not display automation notices")
assert(module.actions.shortcutS(), "The modifier-key dispatcher must still focus Search")
assert(focused and notices == 1)
assert(not plain(1), "Plain S must remain normal after Search is focused")
assert(notices == 1, "Typing after Search must not repeatedly notify")
bundleID = "test.other"
assert(module.actions.shortcutS() == false, "Search must not run in another app")
print("PASS: plain S/apostrophe pass through before and after Search; app-scoped Search action remains available")
