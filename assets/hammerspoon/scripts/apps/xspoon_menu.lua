local M = {}

M.id = "xspoon-menu"

local XSPOON_MENU_BUNDLE_ID = "com.singleton23.XSpoon"

function M.matches(context)
  return context.bundleID == XSPOON_MENU_BUNDLE_ID
end

M.actions = {
  inspect = function()
    return true
  end,
}

return M
