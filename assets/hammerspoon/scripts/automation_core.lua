local M = {}

local apps = {}
local notifier = require("scripts.notify")

local function notify(message)
  notifier.show(message)
end

local function currentContext()
  local app = hs.application.frontmostApplication()
  local win = app and app:focusedWindow()

  return {
    app = app,
    window = win,
    bundleID = app and app:bundleID() or "",
    name = app and app:name() or "",
    windowTitle = win and win:title() or "",
  }
end

function M.registerApp(appModule)
  if type(appModule) ~= "table" then
    return false
  end

  table.insert(apps, appModule)
  return true
end

function M.registeredApps()
  local ids = {}

  for _, app in ipairs(apps) do
    table.insert(ids, app.id or "unknown")
  end

  return ids
end

function M.dispatch(action)
  local context = currentContext()

  for _, app in ipairs(apps) do
    local matches = type(app.matches) == "function" and app.matches(context)
    local handler = app.actions and app.actions[action]

    if matches and type(handler) == "function" then
      local ok, result = pcall(handler, context)
      if not ok then
        notify((app.id or "Automation") .. " failed")
        hs.printf("Automation %s.%s failed: %s", tostring(app.id), tostring(action), tostring(result))
        return false
      end

      if result ~= false then
        return result == nil and true or result
      end
    end
  end

  return false
end

function M.bind(bindings)
  for _, binding in ipairs(bindings or {}) do
    hs.hotkey.bind(binding.modifiers, binding.key, function()
      M.dispatch(binding.action)
    end)
  end
end

function M.eventtap(action)
  return function()
    return M.dispatch(action) == true
  end
end

function M.loadGeneratedModules()
  local registered = {}
  for _, app in ipairs(apps) do
    registered[app.id or ""] = true
  end

  local appsDir = hs.configdir .. "/scripts/apps"
  local iter, dir = pcall(require("hs.fs").dir, appsDir)
  if not iter or not dir then
    return 0
  end

  local count = 0
  for file in dir do
    if file:match("%.lua$") then
      local modName = "scripts.apps." .. file:gsub("%.lua$", "")
      local ok, mod = pcall(require, modName)
      if ok and type(mod) == "table" and mod.id and not registered[mod.id] then
        table.insert(apps, mod)
        registered[mod.id] = true
        count = count + 1
      end
    end
  end

  return count
end

return M
