local obj = {}
obj.__index = obj
obj.name = "XSpoon"

local browser = require("scripts.browser_automations")

local function hotkeyID(hotkey)
  local modifiers = {}
  for _, modifier in ipairs(hotkey.modifiers or {}) do
    table.insert(modifiers, modifier)
  end
  table.sort(modifiers)
  return table.concat(modifiers, "+") .. "::" .. tostring(hotkey.key):lower(), modifiers
end

local function succeeded(result)
  if result == false or result == nil then
    return false
  end
  if type(result) ~= "string" then return result == true end
  local decoded = hs.json.decode(result)
  local status = decoded and decoded.status
  local success = {
    ["performed-local-action"] = true, ["focused-local-element"] = true,
    ["clicked-local-element"] = true, ["performed-menu-action"] = true, ["clicked"] = true,
  }
  return success[status] == true
end

function obj:_run(bundleID, id)
  local front = hs.application.frontmostApplication()
  if not front or front:bundleID() ~= bundleID then return false end
  for _, action in ipairs(browser.actionsForApp(bundleID)) do
    local hotkey = action.hotkey
    if type(hotkey) == "table" and hotkey.key and hotkeyID(hotkey) == id then
      local started = hs.timer.absoluteTime()
      local ok, result = pcall(browser.runElementAction, action)
      self.lastResult = { actionID = action.id, bundleID = bundleID, ok = ok and succeeded(result), receipt = tostring(result),
        elapsedMs = (hs.timer.absoluteTime() - started) / 1000000 }
      if not self.lastResult.ok then hs.printf("XSpoon replay failed: %s", tostring(result)) end
      return self.lastResult.ok
    end
  end
  return false
end

function obj:_activate(bundleID)
  if self.activeBundleID == bundleID then
    return
  end
  if self.activeBundleID and self.modals[self.activeBundleID] then
    self.modals[self.activeBundleID]:exit()
  end
  self.activeBundleID = bundleID
  if self.modals[bundleID] then
    self.modals[bundleID]:enter()
  end
end

function obj:start()
  self:stop()
  self.modals = {}
  self.activeBundleID = nil
  self.registeredActionIDs = {}
  self.bindingCount = 0

  local bindings = {}
  for _, action in ipairs(browser.readElementActions()) do
    local hotkey = action.hotkey
    local bundleID = tostring(action.appBundleID or "")
    if bundleID ~= "" and type(hotkey) == "table" and hotkey.key and hotkey.key ~= "" then
      local id, modifiers = hotkeyID(hotkey)
      local reserved = { i=true, o=true, ["0"]=true, m=true, p=true, r=true, c=true, s=true, v=true }
      if not (table.concat(modifiers, "+") == "alt+ctrl" and reserved[tostring(hotkey.key):lower()]) then
        bindings[bundleID] = bindings[bundleID] or {}
        if not bindings[bundleID][id] then
          bindings[bundleID][id] = { key = hotkey.key, modifiers = modifiers }
          table.insert(self.registeredActionIDs, action.id)
          self.bindingCount = self.bindingCount + 1
        end
      end
    end
  end

  for bundleID, appBindings in pairs(bindings) do
    local modal = hs.hotkey.modal.new()
    for id, binding in pairs(appBindings) do
      modal:bind(binding.modifiers, binding.key, function()
        return self:_run(bundleID, id)
      end)
    end
    self.modals[bundleID] = modal
  end

  self.watcher = hs.application.watcher.new(function(_, event, app)
    local bundleID = app and app:bundleID() or ""
    if event == hs.application.watcher.activated then
      self:_activate(bundleID)
    elseif event == hs.application.watcher.deactivated and self.activeBundleID == bundleID then
      self:_activate("")
    end
  end)
  self.watcher:start()

  local frontmost = hs.application.frontmostApplication()
  self:_activate(frontmost and frontmost:bundleID() or "")
  return self
end

function obj:stop()
  if self.watcher then
    self.watcher:stop()
    self.watcher = nil
  end
  for _, modal in pairs(self.modals or {}) do
    modal:exit()
    modal:delete()
  end
  self.modals = {}
  self.activeBundleID = nil
  return self
end

function obj:status()
  local count = 0
  for _ in pairs(self.modals or {}) do
    count = count + 1
  end
  return { status = "saved-shortcuts-ready", activeBundleID = self.activeBundleID or "", modalCount = count,
    registeredActionIDs = self.registeredActionIDs or {}, bindingCount = self.bindingCount or 0, lastResult = self.lastResult }
end

return obj
