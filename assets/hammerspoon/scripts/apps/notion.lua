local M = {}

M.id = "notion"

local NOTION_BUNDLE_ID = "notion.id"
local lastToggleAt = {}

function M.matches(context)
  return context.bundleID == NOTION_BUNDLE_ID
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
    tostring(element:attributeValue("AXTitle") or ""),
    tostring(element:attributeValue("AXValue") or ""),
    tostring(element:attributeValue("AXDescription") or ""),
  }, "\n")
end

local function frameFor(element)
  local frame = element:attributeValue("AXFrame")
  if frame then
    return frame
  end

  local position = element:attributeValue("AXPosition")
  local size = element:attributeValue("AXSize")
  if position and size then
    return {
      x = position.x,
      y = position.y,
      w = size.w,
      h = size.h,
    }
  end

  return nil
end

local function focusedWindowElement()
  local app = hs.application.frontmostApplication()
  local win = app and app:focusedWindow()
  return win and hs.axuielement.windowElement(win)
end

local function clickToggleByLabel(label)
  local now = hs.timer.secondsSinceEpoch()
  if lastToggleAt[label] and now - lastToggleAt[label] < 0.7 then
    return true
  end

  local axwin = focusedWindowElement()
  if not axwin then
    return false
  end

  local buttons = {}
  local function collectToggleButtons(element)
    if not element then
      return
    end

    local description = tostring(element:attributeValue("AXDescription") or "")
    if element:attributeValue("AXRole") == "AXButton"
      and (description == "Open" or description == "Close") then
      table.insert(buttons, element)
    end

    for _, child in ipairs(element:attributeValue("AXChildren") or {}) do
      collectToggleButtons(child)
    end
  end

  local labelElement = nil
  local bestArea = nil

  walk(axwin, function(element)
    local role = element:attributeValue("AXRole")
    if role ~= "AXTextArea" and role ~= "AXStaticText" then
      return false
    end

    local text = textFor(element):gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= label then
      return false
    end

    local frame = frameFor(element)
    if not frame then
      return false
    end

    local area = frame.w * frame.h
    if not bestArea or area < bestArea then
      labelElement = element
      bestArea = area
    end

    return false
  end)

  if not labelElement then
    return false
  end

  local frame = frameFor(labelElement)
  if not frame then
    return false
  end

  collectToggleButtons(axwin)

  local labelMidY = frame.y + (frame.h / 2)
  local toggleButton = nil
  local bestDistance = nil

  for _, button in ipairs(buttons) do
    local buttonFrame = frameFor(button)
    if buttonFrame and buttonFrame.x < frame.x then
      local buttonMidY = buttonFrame.y + (buttonFrame.h / 2)
      local distance = math.abs(buttonMidY - labelMidY)
      if distance <= 18 and (not bestDistance or distance < bestDistance) then
        toggleButton = button
        bestDistance = distance
      end
    end
  end

  if not toggleButton then
    return false
  end

  local toggleFrame = frameFor(toggleButton)
  local point = {
    x = toggleFrame.x + (toggleFrame.w / 2),
    y = toggleFrame.y + (toggleFrame.h / 2),
  }

  hs.eventtap.leftClick(point)
  lastToggleAt[label] = now
  return true
end

M.actions = {
  voicemail = function()
    return clickToggleByLabel("Voice Mail")
  end,

  shortcutS = function()
    return clickToggleByLabel("Script")
  end,
}

return M
