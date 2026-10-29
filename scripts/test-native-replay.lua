-- Real public replay with AX adapters that return fresh wrappers for equal controls.
package.path = "assets/hammerspoon/?.lua;" .. package.path
local serial, childReads, clicks = 0, 0, {}
local nodes = {
  root = { role = "AXWindow", children = { "loop", "dictate" } },
  loop = { role = "AXGroup", children = { "loop" } },
  dictate = { role = "AXButton", title = "Dictate", children = {} },
}
local methods, meta = {}, {}
meta.__index = methods
meta.__eq = function(a, b) return a.id == b.id end
meta.__tostring = function(e) return "AX wrapper " .. e.serial end
local function wrap(id)
  serial = serial + 1
  return setmetatable({ id = id, serial = serial }, meta)
end
function methods:attributeValue(attribute)
  local node = nodes[self.id]
  if attribute == "AXRole" then return node.role end
  if attribute == "AXTitle" or attribute == "AXDescription" then return node.title or "" end
  if attribute == "AXFrame" then return { x = 100, y = 100, w = 34, h = 34 } end
  if attribute == "AXChildren" or attribute == "AXVisibleChildren" or attribute == "AXChildrenInNavigationOrder" then
    childReads = childReads + 1
    -- Bound the old broken implementation so the regression itself cannot hang.
    if childReads > 500 then return {} end
    local children = {}
    for _, id in ipairs(node.children) do table.insert(children, wrap(id)) end
    return children
  end
end
function methods:isValid() return true end
function methods:pid() return 123 end
local window = { title = function() return "Fixture" end }
local app = { bundleID = function() return "test.chat" end, pid = function() return 123 end,
  focusedWindow = function() return window end }
hs = {
  configdir = "/unused-xspoon-fixture",
  json = { encode = function(value) return value end },
  application = { frontmostApplication = function() return app end },
  axuielement = {
    windowElement = function() return wrap("root") end,
    systemWideElement = function() return { attributeValue = function() return nil end } end,
    systemElementAtPosition = function() return wrap("dictate") end,
  },
  timer = { absoluteTime = function() return os.clock() * 1000000000 end },
  eventtap = { leftClick = function(point) table.insert(clicks, point) end },
}
local browser = dofile("assets/hammerspoon/scripts/browser_automations.lua")
local result = browser.runElementAction({ id = "dictate-fixture", variant = "local", appBundleID = "test.chat",
  axRole = "AXButton", axTitle = "Dictate", axDescription = "Dictate", replayIntent = "physicalClick" })
assert(result.status == "clicked-local-element", "Cold replay must resolve the target after a repeated/cyclic branch")
assert(#clicks == 1, "Replay must click once")
assert(childReads <= 6, "Equal AX wrappers must not cause repeated traversal; reads=" .. childReads)
print("PASS: cold native replay deduplicates equal AX wrappers and clicks Dictate exactly once")

nodes.root.children = { "branch-1" }
for depth = 1, 30 do
  nodes["branch-" .. depth] = { role = "AXGroup", children = { depth == 30 and "deep-dictate" or "branch-" .. (depth + 1) } }
end
nodes["deep-dictate"] = { role = "AXButton", title = "Deep Dictate", children = {} }
childReads = 0
local deep = browser.runElementAction({ id = "deep-dictate-fixture", variant = "local", appBundleID = "test.chat",
  axRole = "AXButton", axTitle = "Deep Dictate", axDescription = "Deep Dictate", replayIntent = "physicalClick" })
assert(deep.status == "clicked-local-element", "Cold replay must reach the observed ChatGPT control depth of 31")
assert(#clicks == 2, "Deep replay must click exactly once")
print("PASS: cold native replay resolves a control at AX depth 31")

nodes["deep-dictate"].title = "Stop dictation"
childReads = 0
local changed = browser.runElementAction({ id = "deep-dictate-fixture", variant = "local", appBundleID = "test.chat",
  axRole = "AXButton", axTitle = "Deep Dictate", axDescription = "Deep Dictate", replayIntent = "physicalClick" })
assert(changed.status == "missing-local-element" and #clicks == 2, "Changed button state must not cause a blind click")
assert(childReads < 100, "A missing label must not restart repeated traversal")

nodes.root.children = {}
for index = 1, 1100 do
  local id = "wide-" .. index
  nodes[id] = { role = "AXGroup", children = {} }
  table.insert(nodes.root.children, id)
end
childReads = 0
hs.timer.absoluteTime = function() return 0 end
local bounded = browser.runElementAction({ variant = "local", appBundleID = "test.chat",
  axRole = "AXButton", axTitle = "Missing target", replayIntent = "physicalClick" })
assert(bounded.status == "missing-local-element" and bounded.message == "ax-search-budget-exceeded")
assert(#clicks == 2, "An exhausted lookup budget must never click")
print("PASS: changed-state lookup fails safely and oversized search stops at its node budget")
