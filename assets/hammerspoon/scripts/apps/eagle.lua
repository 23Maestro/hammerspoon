local M = {}

M.id = "eagle"

local EAGLE_BUNDLE_IDS = {
  ["tw.ogdesign.eagle"] = true,
  ["com.eagle.cool"] = true,
}

function M.matches(context)
  return EAGLE_BUNDLE_IDS[context.bundleID] == true
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

local function contextTarget()
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  local selectedChildren = attr(focused, "AXSelectedChildren")
  if type(selectedChildren) == "table" and selectedChildren[1] then
    return selectedChildren[1]
  end

  local selectedRows = attr(focused, "AXSelectedRows")
  if type(selectedRows) == "table" and selectedRows[1] then
    return selectedRows[1]
  end

  if focused and attr(focused, "AXFrame") then
    return focused
  end

  return nil
end

function M.openContextMenu()
  local target = contextTarget()
  local frame = attr(target, "AXFrame")
  if not frame then
    return false
  end

  hs.eventtap.rightClick({
    x = frame.x + (frame.w / 2),
    y = frame.y + (frame.h / 2),
  })

  return true
end

M.actions = {
  secondary = M.openContextMenu,
}

return M
