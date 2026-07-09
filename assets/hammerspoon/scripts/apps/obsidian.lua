local M = {}

M.id = "obsidian"

local OBSIDIAN_BUNDLE_ID = "md.obsidian"

function M.matches(context)
  return context.bundleID == OBSIDIAN_BUNDLE_ID
end

M.actions = {}

return M
