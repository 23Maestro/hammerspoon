local browser = require("scripts.browser_automations")

local M = {}

M.id = "chrome"

function M.matches(context)
  return context.bundleID == "com.google.Chrome"
end

local function clicked(result)
  if result == true then
    return true
  end

  if type(result) ~= "string" then
    return false
  end

  local ok, decoded = pcall(function()
    return hs.json.decode(result)
  end)

  return ok and type(decoded) == "table" and decoded.status == "clicked"
end

M.actions = {
  save = function()
    return clicked(browser.clickVisibleLabel("Save"))
  end,

  shortcutS = function()
    return clicked(browser.clickVisibleLabel("Save"))
  end,

  close = function()
    return clicked(browser.clickVisibleLabel("Close"))
  end,
}

return M
