local browser = require("scripts.browser_automations")

local M = {}

M.id = "saved-actions"

local KEY_ACTIONS = {
  c = "copy",
  m = "secondary",
  o = "secondary",
  p = "primary",
  r = "search",
  s = "shortcutS",
  v = "voicemail",
}

local function actionSemantic(action)
  if action.semanticAction and action.semanticAction ~= "" then
    return action.semanticAction
  end

  local hotkey = action.hotkey or {}
  local key = tostring(hotkey.key or ""):lower()
  return KEY_ACTIONS[key]
end

local function matchesContext(action, context)
  local bundleID = tostring(action.appBundleID or "")
  if bundleID ~= "" and bundleID == context.bundleID then
    return true
  end

  local appName = tostring(action.appName or "")
  return appName ~= "" and appName == context.name
end

local function actionFor(context, semanticAction)
  for _, action in ipairs(browser.readElementActions()) do
    if matchesContext(action, context) and actionSemantic(action) == semanticAction then
      return action
    end
  end

  return nil
end

function M.matches(context)
  return actionFor(context, "primary")
    or actionFor(context, "secondary")
    or actionFor(context, "search")
    or actionFor(context, "copy")
    or actionFor(context, "shortcutS")
    or actionFor(context, "voicemail")
end

local function dispatchSaved(semanticAction)
  return function(context)
    local action = actionFor(context, semanticAction)
    if not action then
      return false
    end

    return browser.runElementAction(action)
  end
end

M.actions = {
  primary = dispatchSaved("primary"),
  secondary = dispatchSaved("secondary"),
  search = dispatchSaved("search"),
  copy = dispatchSaved("copy"),
  shortcutS = dispatchSaved("shortcutS"),
  voicemail = dispatchSaved("voicemail"),
}

return M
