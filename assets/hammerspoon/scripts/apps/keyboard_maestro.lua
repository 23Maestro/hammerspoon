local M = {}
local notifier = require("scripts.notify")

M.id = "keyboard_maestro"

local EDITOR_BUNDLE_ID = "com.stairways.keyboardmaestro.editor"
local ENGINE_BUNDLE_ID = "com.stairways.keyboardmaestro.engine"
local SCRIPT_POPUP_LABEL = "Or by script"
local SHELL_SCRIPT_LABEL = "Or by Shell script:"

local clipboardArrowScrollState = {
  direction = nil,
  count = 0,
  lastAt = 0,
}

function M.matches(context)
  return context.bundleID == EDITOR_BUNDLE_ID or context.bundleID == ENGINE_BUNDLE_ID
end

local function walk(element, predicate)
  if not element then
    return nil
  end

  if predicate(element) then
    return element
  end

  for _, child in ipairs(element:attributeValue("AXChildren") or {}) do
    local found = walk(child, predicate)
    if found then
      return found
    end
  end

  return nil
end

local function focusedWindowElement()
  local app = hs.application.frontmostApplication()
  local win = app and app:focusedWindow()
  return win and hs.axuielement.windowElement(win)
end

local function elementText(element)
  return table.concat({
    tostring(element:attributeValue("AXTitle") or ""),
    tostring(element:attributeValue("AXValue") or ""),
    tostring(element:attributeValue("AXDescription") or ""),
  }, "\n")
end

local function trim(value)
  local trimmed = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return trimmed
end

local function firstShellLine(value)
  local text = tostring(value or ""):gsub("\r", "\n")
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local candidate = trim(line)
    if candidate:find("osascript %-e") and not candidate:find("^#%s*or:") then
      return candidate
    end
  end

  return trim(text:match("([^\n]+)") or "")
end

local function waitForPasteboardChange(priorChangeCount)
  local deadline = hs.timer.secondsSinceEpoch() + 1.5

  repeat
    if hs.pasteboard.changeCount() ~= priorChangeCount then
      hs.timer.usleep(250000)
      return hs.pasteboard.getContents()
    end

    hs.timer.usleep(50000)
  until hs.timer.secondsSinceEpoch() >= deadline

  return hs.pasteboard.getContents()
end

local function shellScriptTextBox()
  local axwin = focusedWindowElement()
  if not axwin then
    return nil
  end

  return walk(axwin, function(element)
    local value = tostring(element:attributeValue("AXValue") or "")
    return value:find("Keyboard Maestro Engine", 1, true)
      and value:find("do script", 1, true)
      and value:find("osascript", 1, true)
  end)
end

local function waitForShellScriptTextBox()
  local deadline = hs.timer.secondsSinceEpoch() + 2.5

  repeat
    local shellBox = shellScriptTextBox()
    if shellBox then
      return shellBox
    end

    hs.timer.usleep(150000)
  until hs.timer.secondsSinceEpoch() >= deadline

  return nil
end

local function pressMenuItem(label)
  local app = hs.application.frontmostApplication()
  local axapp = app and hs.axuielement.applicationElement(app)
  if not axapp then
    return false
  end

  local item = walk(axapp, function(element)
    return element:attributeValue("AXRole") == "AXMenuItem"
      and tostring(element:attributeValue("AXTitle") or "") == label
  end)

  if not item then
    return false
  end

  item:performAction("AXPress")
  hs.timer.usleep(900000)
  return true
end

local function selectShellScriptMode()
  if pressMenuItem(SHELL_SCRIPT_LABEL) then
    return true
  end

  local axwin = focusedWindowElement()
  if not axwin then
    return false
  end

  local popup = walk(axwin, function(element)
    return element:attributeValue("AXRole") == "AXPopUpButton"
      and elementText(element):find(SCRIPT_POPUP_LABEL, 1, true)
  end)

  if not popup then
    return false
  end

  popup:performAction("AXPress")
  hs.timer.usleep(500000)
  return pressMenuItem(SHELL_SCRIPT_LABEL)
end

local function copyShellScriptFirstLine()
  local axwin = focusedWindowElement()
  if not axwin then
    return false
  end

  if not selectShellScriptMode() then
    notifier.show("KM Shell script menu not found")
    return false
  end

  local shellBox = waitForShellScriptTextBox()
  if shellBox then
    hs.pasteboard.setContents(firstShellLine(shellBox:attributeValue("AXValue")))
    notifier.show("Copied KM shell line")
    return true
  end

  local priorClipboard = hs.pasteboard.getContents()
  local priorChangeCount = hs.pasteboard.changeCount()
  hs.eventtap.keyStroke({ "cmd" }, "a", 0)
  hs.timer.usleep(80000)
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)

  local copied = waitForPasteboardChange(priorChangeCount)
  local line = firstShellLine(copied)
  if line:find("Keyboard Maestro Engine", 1, true) and line:find("do script", 1, true) then
    hs.pasteboard.setContents(line)
    notifier.show("Copied KM shell line")
    return true
  end

  if priorClipboard then
    hs.pasteboard.setContents(priorClipboard)
  else
    hs.pasteboard.clearContents()
  end

  notifier.show("KM shell script not found")
  return false
end

local function clipboardScrollBar()
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= ENGINE_BUNDLE_ID then
    return nil
  end

  local win = app:focusedWindow()
  if not win or win:title() ~= "Clipboard History Switcher" then
    return nil
  end

  local axwin = hs.axuielement.windowElement(win)
  local scrollArea = walk(axwin, function(element)
    return element:attributeValue("AXRole") == "AXScrollArea"
  end)

  return walk(scrollArea, function(element)
    return element:attributeValue("AXRole") == "AXScrollBar"
  end)
end

local function nudgeClipboardScroll(delta)
  local scrollBar = clipboardScrollBar()
  if not scrollBar then
    return
  end

  local value = scrollBar:attributeValue("AXValue")
  if type(value) ~= "number" then
    return
  end

  scrollBar:setAttributeValue("AXValue", math.max(0, math.min(1, value + delta)))
end

function M.start()
  keyboardMaestroClipboardArrowScrollWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    local keyCode = event:getKeyCode()
    local direction = nil

    if keyCode == hs.keycodes.map.down then
      direction = "down"
    elseif keyCode == hs.keycodes.map.up then
      direction = "up"
    else
      return false
    end

    if not clipboardScrollBar() then
      return false
    end

    local now = hs.timer.secondsSinceEpoch()
    if clipboardArrowScrollState.direction ~= direction or now - clipboardArrowScrollState.lastAt > 0.8 then
      clipboardArrowScrollState.direction = direction
      clipboardArrowScrollState.count = 0
    end

    clipboardArrowScrollState.count = clipboardArrowScrollState.count + 1
    clipboardArrowScrollState.lastAt = now

    if clipboardArrowScrollState.count % 4 == 0 then
      local delta = direction == "down" and 0.006 or -0.006
      hs.timer.doAfter(0.02, function()
        nudgeClipboardScroll(delta)
      end)
    end

    return false
  end)

  keyboardMaestroClipboardArrowScrollWatcher:start()
end

M.actions = {
  copy = copyShellScriptFirstLine,
  shortcutS = copyShellScriptFirstLine,
}

return M
