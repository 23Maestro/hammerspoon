-- Exercise the public inspection lifecycle with OS input/notification adapters.
local directory = assert(arg[1], "temporary config directory required")
package.path = "assets/hammerspoon/?.lua;" .. package.path
local tap, bindings = nil, {}
local captures, failures = 0, 0
hs = {
  configdir = directory,
  json = { encode = function() return "{}" end, decode = function(value) return value end },
  application = { frontmostApplication = function() return { bundleID = function() return "test.target" end } end },
  mouse = { absolutePosition = function() return { x = 10, y = 20 } end },
  axuielement = { systemElementAtPosition = function() return nil end },
  timer = { doEvery = function() return { stop = function() end } end },
  distributednotifications = { post = function(name)
    if name == "com.singleton23.XSpoon.captureFailed" then failures = failures + 1 end
  end },
  keycodes = { map = { escape = 53, ["return"] = 36, padenter = 76 } },
  eventtap = { event = { types = { keyDown = 10, keyUp = 11 } } },
  hotkey = { bind = function(_, key, callback) bindings[key] = callback end },
}
function hs.eventtap.new(_, callback)
  tap = { callback = callback, enabled = false }
  function tap:start() self.enabled = true end
  function tap:stop() self.enabled = false end
  return tap
end
local scripts = dofile("assets/hammerspoon/scripts/browser_automations.lua")
local failCapture = false
scripts.captureHoveredElement = function()
  captures = captures + 1
  if failCapture then return { status = "error", message = "No target" } end
  scripts.stopLiveInspector()
  return { status = "captured-local-element" }
end
local function key(code, kind, flags)
  if not tap or not tap.enabled then return false end
  return tap.callback({
    getKeyCode = function() return code end,
    getType = function() return kind or 10 end,
    getFlags = function() return flags or {} end,
  })
end
scripts.bindHotkeys()
bindings.i()
assert(scripts.liveInspectorActive(), "I must start inspection")
assert(captures == 0, "Starting inspection must not capture")
assert(key(36), "Enter down must be consumed during inspection")
assert(key(36), "Repeated Enter down must be consumed")
assert(captures == 0, "Capture waits for release so the sheet cannot receive this Enter")
assert(key(36, 11), "Enter release must be consumed")
assert(captures == 1 and not scripts.liveInspectorActive(), "Enter must capture once and stop inspection")
assert(not key(36), "Enter outside inspection must pass through")
bindings.i()
assert(not key(36, 10, { cmd = true }), "Modified Enter must pass through")
assert(not key(36, 11, { cmd = true }), "Modified Enter release must pass through")
assert(key(53), "Escape must cancel inspection")
assert(not scripts.liveInspectorActive() and captures == 1, "Cancel must not capture")
bindings.i()
bindings.i()
assert(not scripts.liveInspectorActive(), "I must toggle inspection off")
bindings.i()
failCapture = true
assert(key(76) and key(76, 11), "Keypad Enter must use the same capture path")
assert(failures == 1 and scripts.liveInspectorActive(), "Failed capture must report error and allow retry")
scripts.stopLiveInspector()
assert(bindings.e == nil, "E must not be a global capture binding")
print("PASS: inspection input lifecycle, release capture, repeat guard, modifiers, cancel, retry, and no global E")
