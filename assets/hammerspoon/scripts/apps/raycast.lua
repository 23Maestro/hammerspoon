local M = {}

M.id = "raycast"

local BUNDLE_IDS = {
  ["com.raycast.macos"] = true,
  ["com.raycast-x.macos"] = true,
}

local watcher = nil
local pending = nil
local LOG_PATH = "/tmp/hammerspoon-raycast.log"

local function log(message)
  local file = io.open(LOG_PATH, "a")
  if not file then
    return
  end

  file:write(os.date("%H:%M:%S") .. " " .. tostring(message) .. "\n")
  file:close()
end

local function attr(element, name)
  local ok, value = pcall(function()
    return element and element:attributeValue(name)
  end)

  if ok then
    return value
  end

  return nil
end

local function raycastHasFocus()
  local front = hs.application.frontmostApplication()
  if front and BUNDLE_IDS[front:bundleID() or ""] then
    return true
  end

  for bundleID in pairs(BUNDLE_IDS) do
    local app = hs.application.get(bundleID)
    local axapp = app and hs.axuielement.applicationElement(app)
    if attr(axapp, "AXFocusedUIElement") then
      return true
    end
  end

  return false
end

local function focusedText()
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  return table.concat({
    tostring(attr(focused, "AXTitle") or ""),
    tostring(attr(focused, "AXValue") or ""),
    tostring(attr(focused, "AXDescription") or ""),
    tostring(attr(focused, "AXPlaceholderValue") or ""),
  }, "\n")
end

local function waitForFocusedText(pattern, timeout)
  local deadline = hs.timer.secondsSinceEpoch() + timeout
  repeat
    if focusedText():lower():find(pattern, 1, true) then
      return true
    end
    hs.timer.usleep(50000)
  until hs.timer.secondsSinceEpoch() >= deadline

  return false
end

local function commandMenuSearch(value)
  log("commandMenuSearch:start")
  hs.eventtap.keyStroke({ "cmd" }, "k", 0)
  log("commandMenuSearch:sent-cmd-k")
  if not waitForFocusedText("search for actions", 1.5) then
    log("commandMenuSearch:action-field-timeout")
    return
  end
  log("commandMenuSearch:action-field-focused")
  hs.eventtap.keyStrokes(value)
  log("commandMenuSearch:typed-" .. tostring(value))
end

local function configureSelected(downCount)
  hs.eventtap.keyStroke({ "cmd", "shift" }, ",", 0)
  hs.timer.usleep(450000)
  for _ = 1, downCount do
    hs.eventtap.keyStroke({}, "down", 0)
    hs.timer.usleep(150000)
  end
  hs.eventtap.keyStroke({}, "return", 0)
end

local function handle(event)
  if not raycastHasFocus() then
    return false
  end

  local flags = event:getFlags()
  local keyCode = event:getKeyCode()
  local eventType = event:getType()

  if keyCode == hs.keycodes.map.b and flags.cmd and not flags.alt and not flags.ctrl and not flags.shift then
    if eventType == hs.eventtap.event.types.keyDown then
      log("cmd-b:keydown")
      pending = function()
        commandMenuSearch("st")
      end
    elseif pending then
      log("cmd-b:keyup-run-pending")
      hs.timer.doAfter(0.05, pending)
      pending = nil
    end

    return true
  end

  if keyCode == hs.keycodes.map.a and flags.cmd and flags.alt and not flags.ctrl and not flags.shift then
    if eventType == hs.eventtap.event.types.keyDown then
      pending = function()
        configureSelected(2)
      end
    elseif pending then
      hs.timer.doAfter(0.05, pending)
      pending = nil
    end

    return true
  end

  if keyCode == hs.keycodes.map.c and flags.cmd and flags.alt and not flags.ctrl and not flags.shift then
    if eventType == hs.eventtap.event.types.keyDown then
      pending = function()
        configureSelected(1)
      end
    elseif pending then
      hs.timer.doAfter(0.05, pending)
      pending = nil
    end

    return true
  end

  return false
end

function M.matches(context)
  return BUNDLE_IDS[context.bundleID] == true
end

function M.start()
  if watcher then
    watcher:stop()
  end

  watcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, handle)
  watcher:start()
end

return M
