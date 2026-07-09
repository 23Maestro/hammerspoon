local M = {}

M.id = "finder"

local FINDER_BUNDLE_ID = "com.apple.finder"

function M.matches(context)
  return context.bundleID == FINDER_BUNDLE_ID
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

local function selectedItem()
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  local selectedChildren = attr(focused, "AXSelectedChildren")
  if type(selectedChildren) == "table" and selectedChildren[1] then
    return selectedChildren[1]
  end

  local selectedRows = attr(focused, "AXSelectedRows")
  if type(selectedRows) == "table" and selectedRows[1] then
    return selectedRows[1]
  end

  return nil
end

local function rightClickElement(element)
  local frame = attr(element, "AXFrame")
  if not frame then
    return false
  end

  hs.eventtap.rightClick({
    x = frame.x + (frame.w / 2),
    y = frame.y + (frame.h / 2),
  })

  return true
end

function M.openSelectedContextMenu(method)
  local item = selectedItem()
  if not item then
    return false
  end

  if method ~= "rightclick" then
    local ok = pcall(function()
      item:performAction("AXShowMenu")
    end)
    if ok then
      return true
    end
  end

  return rightClickElement(item)
end

M.actions = {
  secondary = function()
    return M.openSelectedContextMenu("rightclick")
  end,
}

return M
