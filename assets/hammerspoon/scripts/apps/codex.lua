local M = {}
local notifier = require("scripts.notify")

M.id = "codex"

local CODEX_BUNDLE_ID = "com.openai.codex"
local watcher = nil

function M.matches(context)
  return context.bundleID == CODEX_BUNDLE_ID
end

local function attr(element, name)
  if not element then
    return ""
  end

  local ok, value = pcall(function()
    return element:attributeValue(name)
  end)

  if not ok or value == nil then
    return ""
  end

  return tostring(value)
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

local function textFor(element)
  return table.concat({
    attr(element, "AXTitle"),
    attr(element, "AXValue"),
    attr(element, "AXDescription"),
    attr(element, "AXPlaceholderValue"),
  }, "\n")
end

local function isShortcutSearch(element)
  local text = textFor(element):lower()
  return text:find("search keyboard shortcuts", 1, true) ~= nil
    or text:find("search shortcuts", 1, true) ~= nil
end

local function focusSearchField()
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= CODEX_BUNDLE_ID then
    return false
  end

  local search = nil
  for _, win in ipairs(app:allWindows()) do
    search = walk(hs.axuielement.windowElement(win), function(element)
      local role = attr(element, "AXRole")
      return role == "AXTextField" and isShortcutSearch(element)
    end)

    if search then
      break
    end
  end

  if not search then
    return false
  end

  pcall(function()
    search:setAttributeValue("AXFocused", true)
  end)
  pcall(function()
    search:performAction("AXPress")
  end)
  notifier.show("Codex Search")
  return true
end

local function pressKeystrokeSearchToggle()
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= CODEX_BUNDLE_ID then
    return false
  end

  local toggle = nil
  for _, win in ipairs(app:allWindows()) do
    toggle = walk(hs.axuielement.windowElement(win), function(element)
      return attr(element, "AXRole") == "AXCheckBox"
        and attr(element, "AXDescription") == "Search by keystrokes"
    end)

    if toggle then
      break
    end
  end

  if not toggle then
    return false
  end

  local frame = toggle:attributeValue("AXFrame")
  if not frame then
    return false
  end

  hs.eventtap.leftClick({
    x = frame.x + (frame.w / 2),
    y = frame.y + (frame.h / 2),
  })
  notifier.show("Codex Keystroke Search")
  return true
end

local function hasModifiers(event)
  local flags = event:getFlags()
  return flags.cmd or flags.alt or flags.ctrl or flags.shift or flags.fn
end

function M.start()
  if watcher then
    watcher:stop()
  end

  watcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    if hasModifiers(event) then
      return false
    end

    local keyCode = event:getKeyCode()
    if keyCode == hs.keycodes.map.s then
      return focusSearchField()
    end

    if keyCode == hs.keycodes.map["'"] then
      return pressKeystrokeSearchToggle()
    end

    return false
  end)

  watcher:start()
  codexShortcutSearchWatcher = watcher
end

M.actions = {
  shortcutS = focusSearchField,
  shortcutQuote = pressKeystrokeSearchToggle,
}

return M
