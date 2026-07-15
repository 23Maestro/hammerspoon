local M = {}

local CHROME_BUNDLE_ID = "com.google.Chrome"
local LATEST_ELEMENT_PATH = hs.configdir .. "/browser_element_latest.json"
local LOCAL_LATEST_ELEMENT_PATH = hs.configdir .. "/local_element_latest.json"
local LIVE_LATEST_ELEMENT_PATH = hs.configdir .. "/live_element_latest.json"
local ELEMENT_ACTIONS_PATH = hs.configdir .. "/browser_element_actions.json"
local clipboardText
local catalog = {}
local notifier = require("scripts.notify")
local liveInspectorTimer
local liveInspectorSignature = ""

local function appleScriptString(value)
  return '"' .. tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function chromeIsFrontmost()
  local app = hs.application.frontmostApplication()
  return app and app:bundleID() == CHROME_BUNDLE_ID
end

local function appleScriptErrorMessage(raw, fallback)
  if type(raw) == "table" then
    return raw.NSLocalizedFailureReason
      or raw.NSLocalizedDescription
      or raw.OSAScriptErrorMessageKey
      or raw.OSAScriptErrorBriefMessageKey
      or fallback
  end

  return fallback or tostring(raw)
end

local function chromeExecuteJavaScript(script, options)
  if type(options) ~= "table" then
    options = { activate = options == true }
  end

  if not chromeIsFrontmost() and not options.activate and not options.urlIncludes then
    return false, "not-chrome"
  end

  local urlIncludes = tostring(options.urlIncludes or "")
  local lines = {
    'tell application "Google Chrome"',
  }

  if options.activate then
    table.insert(lines, "activate")
  end

  table.insert(lines, 'if not (exists front window) then error "No Chrome window open"')
  table.insert(lines, "set targetTab to active tab of front window")

  if urlIncludes ~= "" then
    table.insert(lines, "set foundTargetTab to false")
    table.insert(lines, "repeat with chromeWindow in windows")
    table.insert(lines, "repeat with chromeTab in tabs of chromeWindow")
    table.insert(lines, "if (URL of chromeTab contains " .. appleScriptString(urlIncludes) .. ") then")
    table.insert(lines, "set targetTab to chromeTab")
    table.insert(lines, "set foundTargetTab to true")
    table.insert(lines, "exit repeat")
    table.insert(lines, "end if")
    table.insert(lines, "end repeat")
    table.insert(lines, "if foundTargetTab then exit repeat")
    table.insert(lines, "end repeat")
    table.insert(lines, "if not foundTargetTab then error \"No Chrome tab matching " .. urlIncludes:gsub('"', "'") .. "\"")
  end

  table.insert(lines, "tell targetTab to execute javascript " .. appleScriptString(script))
  table.insert(lines, "end tell")

  local ok, result, raw = hs.osascript.applescript(table.concat(lines, "\n"))
  if not ok then
    return false, appleScriptErrorMessage(raw, tostring(result))
  end

  return true, result
end

local function jsString(value)
  local encoded = hs.json.encode({ tostring(value or "") })
  return encoded:sub(2, -2)
end

local function systemPasteText(value)
  local previous = hs.pasteboard.getContents()
  hs.pasteboard.setContents(tostring(value or ""))
  hs.osascript.applescript('tell application "System Events" to keystroke "v" using command down')
  hs.timer.doAfter(0.3, function()
    hs.pasteboard.setContents(previous or "")
  end)
end

local function notify(message)
  notifier.show(message)
end

local function containsText(actual, expected)
  local expectedText = tostring(expected or "")
  if expectedText == "" then
    return true
  end

  return tostring(actual or ""):find(expectedText, 1, true) ~= nil
end

local function axAttribute(element, attribute)
  if not element then
    return ""
  end

  local ok, value = pcall(function()
    return element:attributeValue(attribute)
  end)

  if not ok or value == nil then
    return ""
  end

  return tostring(value)
end

local function axRawAttribute(element, attribute)
  if not element then
    return nil
  end

  local ok, value = pcall(function()
    return element:attributeValue(attribute)
  end)

  return ok and value or nil
end

local function plainRect(rect)
  if not rect then
    return nil
  end

  local x = tonumber(rect.x)
  local y = tonumber(rect.y)
  local w = tonumber(rect.w)
  local h = tonumber(rect.h)
  if not x or not y or not w or not h then
    return nil
  end

  return { x = x, y = y, w = w, h = h }
end

local function axFrame(element)
  if not element then
    return nil
  end

  local frame = element:attributeValue("AXFrame")
  if frame then
    local normalized = plainRect(frame)
    if normalized then
      return normalized
    end
  end

  local position = element:attributeValue("AXPosition")
  local size = element:attributeValue("AXSize")
  if position and size then
    return plainRect({
      x = position.x,
      y = position.y,
      w = size.w,
      h = size.h,
    })
  end

  return nil
end

local function firstAttributeElement(element, attributes)
  if not element then
    return nil
  end

  for _, attribute in ipairs(attributes) do
    local ok, value = pcall(function()
      return element:attributeValue(attribute)
    end)

    if ok and type(value) == "table" and value[1] then
      return value[1]
    end
  end

  return nil
end

local function walkAx(element, predicate, depth)
  if not element or depth < 0 then
    return nil
  end

  if predicate(element) then
    return element
  end

  local children = element:attributeValue("AXChildren") or {}
  for _, child in ipairs(children) do
    local found = walkAx(child, predicate, depth - 1)
    if found then
      return found
    end
  end

  return nil
end

local function firstSelectedDescendant(element)
  return walkAx(element, function(candidate)
    return axAttribute(candidate, "AXSelected") == "true" and axFrame(candidate) ~= nil
  end, 10)
end

local function firstSelectedChildInList(element, description)
  local list = walkAx(element, function(candidate)
    return axAttribute(candidate, "AXRole") == "AXList"
      and axAttribute(candidate, "AXDescription") == description
  end, 10)

  local selectedIcon = walkAx(list, function(candidate)
    return axAttribute(candidate, "AXSelected") == "true"
      and axAttribute(candidate, "AXRole") == "AXImage"
      and axFrame(candidate) ~= nil
  end, 10)

  return selectedIcon
    or firstAttributeElement(list, { "AXSelectedChildren", "AXSelectedRows", "AXSelectedCells" })
    or firstSelectedDescendant(list)
end

local allowedContextMenuApps = {
  ["com.apple.finder"] = true,
  ["com.raycast.macos"] = true,
  ["com.raycast-x.macos"] = true,
  ["com.eagle.cool"] = true,
  ["tw.ogdesign.eagle"] = true,
}

local allowedContextMenuAppNames = {
  ["Finder"] = true,
  ["Raycast"] = true,
  ["Raycast Beta"] = true,
  ["Eagle"] = true,
}

local function contextMenuAllowed(app)
  if not app then
    return false
  end

  return allowedContextMenuApps[app:bundleID() or ""] == true
    or allowedContextMenuAppNames[app:name() or ""] == true
end

local function localContextTarget()
  local app = hs.application.frontmostApplication()
  if not contextMenuAllowed(app) then
    return nil, "unsupported-app", app
  end

  local win = app:focusedWindow()
  local axwin = win and hs.axuielement.windowElement(win)
  local system = hs.axuielement.systemWideElement()
  local focused = system and system:attributeValue("AXFocusedUIElement")
  local selectionAttributes = { "AXSelectedRows", "AXSelectedChildren", "AXSelectedCells" }
  local finderTarget = app:bundleID() == "com.apple.finder" and firstSelectedChildInList(axwin, "icon view") or nil
  local target = finderTarget
    or firstAttributeElement(focused, selectionAttributes)
    or firstAttributeElement(axwin, selectionAttributes)
    or firstSelectedDescendant(axwin)
    or (focused and axFrame(focused) and focused)

  if not target then
    return nil, "missing-target", app
  end

  return target, nil, app
end

local function appleScript(script)
  local ok, result, raw = hs.osascript.applescript(script)
  if ok then
    return true, result
  end

  return false, appleScriptErrorMessage(raw, tostring(result))
end

local function activeChromeUrlAndTitle()
  local ok, result = appleScript([[
    tell application "Google Chrome"
      if not (exists front window) then return ""
      return URL of active tab of front window & linefeed & title of active tab of front window
    end tell
  ]])

  if not ok then
    return false, "", "", result
  end

  local text = tostring(result or "")
  local url, title = text:match("([^\n]*)\n?(.*)")
  return true, url or "", title or "", nil
end

local function chromeJavaScriptHealth()
  local ok, result = appleScript([[
    tell application "Google Chrome"
      if not (exists front window) then return ""
      tell active tab of front window to execute javascript "JSON.stringify({ href: location.href, title: document.title })"
    end tell
  ]])

  if not ok then
    return {
      ok = false,
      error = result,
    }
  end

  return {
    ok = true,
    result = result,
  }
end

local function hotkeySummary()
  local ok, hotkeys = pcall(function()
    return hs.hotkey.getHotkeys()
  end)

  if not ok then
    return {}
  end

  local summaries = {}
  for _, hotkey in ipairs(hotkeys) do
    table.insert(summaries, hotkey.idx or hotkey.msg or "unknown")
  end

  return summaries
end

local function truncate(value, maxLength)
  local text = tostring(value or "")
  if #text <= maxLength then
    return text
  end

  return text:sub(1, maxLength) .. "...[truncated " .. tostring(#text - maxLength) .. " chars]"
end

function M.health()
  local front = hs.application.frontmostApplication()
  local win = front and front:focusedWindow()
  local chromeOk, chromeUrl, chromeTitle, chromeError = activeChromeUrlAndTitle()
  local scriptIds = {}

  for _, script in ipairs(catalog or {}) do
    table.insert(scriptIds, script.id)
  end

  return hs.json.encode({
    status = "ok",
    generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    frontApp = {
      name = front and front:name() or "",
      bundleID = front and front:bundleID() or "",
      windowTitle = win and win:title() or "",
    },
    hammerspoon = {
      automationCore = type(automationCore),
      chromeBrowserAutomations = type(chromeBrowserAutomations),
      scriptsGlobal = type(__SCRIPTS__),
      closeWatcher = type(chromeCloseOnEscapeWatcher),
      keyboardMaestroWatcher = type(keyboardMaestroClipboardArrowScrollWatcher),
      registeredApps = automationCore and automationCore.registeredApps and automationCore.registeredApps() or {},
      hotkeys = hotkeySummary(),
    },
    chrome = {
      urlReadable = chromeOk,
      url = truncate(chromeUrl, 500),
      urlLength = #tostring(chromeUrl or ""),
      title = truncate(chromeTitle, 200),
      urlError = chromeError,
      javascript = {
        status = "not-run",
        note = "Use chrome.javascript-health for the explicit JavaScript from Apple Events probe.",
      },
    },
    scripts = {
      count = #scriptIds,
      ids = scriptIds,
    },
    filesystem = {
      status = "not-run",
      note = "Use shell readlink/shasum for symlink receipt; avoid hs.execute inside IPC health.",
    },
  })
end

local function clickScript(config)
  local selector = jsString(config.selector)
  local xpath = jsString(config.xpath)
  local label = jsString(config.label)
  local urlIncludes = jsString(config.urlIncludes)
  local titleIncludes = jsString(config.titleIncludes)
  local requiredSelector = jsString(config.requiredSelector)

  return table.concat({
    "(() => {",
    "const selector = " .. selector .. ";",
    "const xpath = " .. xpath .. ";",
    "const label = " .. label .. ";",
    "const urlIncludes = " .. urlIncludes .. ";",
    "const titleIncludes = " .. titleIncludes .. ";",
    "const requiredSelector = " .. requiredSelector .. ";",
    "if (urlIncludes && !location.href.includes(urlIncludes)) return JSON.stringify({ status: 'wrong-url', url: location.href });",
    "if (titleIncludes && !document.title.includes(titleIncludes)) return JSON.stringify({ status: 'wrong-title', title: document.title, url: location.href });",
    "if (requiredSelector && !document.querySelector(requiredSelector)) return JSON.stringify({ status: 'missing-required', requiredSelector, url: location.href });",
    "const visible = (el) => {",
    "const rect = el.getBoundingClientRect();",
    "const style = getComputedStyle(el);",
    "return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden' && style.pointerEvents !== 'none';",
    "};",
    "const textFor = (el) => (el.value || el.innerText || el.getAttribute('aria-label') || el.title || '').trim();",
    "const addCss = () => selector ? [...document.querySelectorAll(selector)] : [];",
    "const addXpath = () => {",
    "if (!xpath) return [];",
    "const result = document.evaluate(xpath, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);",
    "const nodes = [];",
    "for (let i = 0; i < result.snapshotLength; i++) nodes.push(result.snapshotItem(i));",
    "return nodes;",
    "};",
    "const addLabel = () => {",
    "if (!label) return [];",
    "const controls = 'button,input[type=button],input[type=submit],a,[role=button]';",
    "return [...document.querySelectorAll(controls)].filter((el) => textFor(el) === label);",
    "};",
    "const seen = new Set();",
    "const candidates = [...addCss(), ...addXpath(), ...addLabel()].filter((el) => el && !seen.has(el) && seen.add(el));",
    "const target = candidates.find(visible);",
    "if (!target) return JSON.stringify({ status: 'missing', selector, xpath, label, url: location.href });",
    "const clickable = target.closest('button,a,[role=\"button\"]') || target;",
    "clickable.scrollIntoView({ block: 'center', inline: 'center' });",
    "clickable.click();",
    "return JSON.stringify({ status: 'clicked', text: textFor(clickable), selector, xpath, label, url: location.href });",
    "})()",
  }, " ")
end

function M.click(config)
  local ok, result = chromeExecuteJavaScript(clickScript(config or {}), {
    activate = config and config.activate,
    urlIncludes = config and config.urlIncludes,
  })
  if not ok then
    return hs.json.encode({ status = "error", message = tostring(result) })
  end
  return result
end

function M.clickVisibleLabel(label)
  return M.click({ label = label })
end

function M.clickXPath(xpath)
  return M.click({ xpath = xpath })
end

function M.clickSelector(selector)
  return M.click({ selector = selector })
end

function M.copyVisibleControls()
  local script = table.concat({
    "(() => {",
    "const visible = (el) => {",
    "const rect = el.getBoundingClientRect();",
    "const style = getComputedStyle(el);",
    "return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden';",
    "};",
    "const textFor = (el) => (el.value || el.innerText || el.getAttribute('aria-label') || el.title || '').trim();",
    "const itemFor = (el) => ({ tag: el.tagName.toLowerCase(), id: el.id || '', className: String(el.className || ''), text: textFor(el), ariaLabel: el.getAttribute('aria-label') || '', title: el.title || '' });",
    "const selector = 'button,input[type=button],input[type=submit],a,[role=button]';",
    "return JSON.stringify([...document.querySelectorAll(selector)].filter(visible).map(itemFor), null, 2);",
    "})()",
  }, " ")

  local ok, result = chromeExecuteJavaScript(script, false)
  if not ok then
    return hs.json.encode({ status = "error", message = tostring(result) })
  end

  hs.pasteboard.setContents(result)
  notify("Copied visible Chrome controls")
  return hs.json.encode({ status = "copied-visible-controls" })
end

clipboardText = function()
  local value = hs.pasteboard.getContents()
  if type(value) ~= "string" then
    return ""
  end
  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function selectorFromText(value)
  if value == "" then
    return ""
  end

  local ok, decoded = pcall(function()
    return hs.json.decode(value)
  end)

  if ok and type(decoded) == "table" and type(decoded.selector) == "string" then
    return decoded.selector
  end

  return value
end

local function persistLatestElement()
  local value = clipboardText()
  if value == "" then
    return false
  end

  local ok, decoded = pcall(function()
    return hs.json.decode(value)
  end)

  if not ok or type(decoded) ~= "table" or decoded.kind ~= "hammerspoon-browser-element" then
    return false
  end

  local file = io.open(LATEST_ELEMENT_PATH, "w")
  if not file then
    return false
  end

  file:write(value)
  file:close()
  return true
end

function M.clickClipboardSelector()
  local selector = selectorFromText(clipboardText())
  if selector == "" then
    return hs.json.encode({ status = "missing-clipboard-selector" })
  end
  return M.click({ selector = selector })
end

function M.clickClipboardXPath()
  local xpath = clipboardText()
  if xpath == "" then
    return hs.json.encode({ status = "missing-clipboard-xpath" })
  end
  return M.click({ xpath = xpath })
end

function M.pickSelector(options)
  options = options or {}

  local script = table.concat({
    "(() => {",
    "if (typeof window.__raycastHammerspoonSelectorPickerCleanup === 'function') { try { window.__raycastHammerspoonSelectorPickerCleanup(); } catch (_) {} }",
    "window.__raycastHammerspoonSelectorPickerActive = true;",
    "const cssEscape = (value) => window.CSS && CSS.escape ? CSS.escape(value) : String(value).replace(/[^a-zA-Z0-9_-]/g, '\\\\$&');",
    "const selectorFor = (el) => {",
    "if (!el || el.nodeType !== 1) return '';",
    "if (el.id) return `#${cssEscape(el.id)}`;",
    "const parts = [];",
    "let node = el;",
    "while (node && node.nodeType === 1 && node !== document.body && parts.length < 5) {",
    "let part = node.tagName.toLowerCase();",
    "const stableClass = [...node.classList].find((name) => !/^ng-|^css-|^x[0-9a-f-]+$/.test(name));",
    "if (stableClass) part += `.${cssEscape(stableClass)}`;",
    "const parent = node.parentElement;",
    "if (parent) {",
    "const siblings = [...parent.children].filter((child) => child.tagName === node.tagName);",
    "if (siblings.length > 1) part += `:nth-of-type(${siblings.indexOf(node) + 1})`;",
    "}",
    "parts.unshift(part);",
    "node = parent;",
    "if (document.querySelectorAll(parts.join(' > ')).length === 1) break;",
    "}",
    "return parts.join(' > ');",
    "};",
    "const cleanup = () => {",
    "window.__raycastHammerspoonSelectorPickerActive = false;",
    "window.__raycastHammerspoonSelectorPickerCleanup = null;",
    "document.removeEventListener('click', onClick, true);",
    "document.removeEventListener('keydown', onKeyDown, true);",
    "if (label && label.parentNode) label.parentNode.removeChild(label);",
    "};",
    "const textFor = (el) => (el.value || el.innerText || el.getAttribute('aria-label') || el.title || '').trim();",
    "const payloadFor = (el, selector) => JSON.stringify({",
    "kind: 'hammerspoon-browser-element',",
    "selector,",
    "url: location.href,",
    "title: document.title,",
    "text: textFor(el),",
    "tag: el.tagName.toLowerCase(),",
    "id: el.id || '',",
    "className: String(el.className || ''),",
    "capturedAt: new Date().toISOString()",
    "}, null, 2);",
    "const copy = async (payload) => {",
    "window.__raycastHammerspoonLastElement = JSON.parse(payload);",
    "try { await navigator.clipboard.writeText(payload); } catch (_) { window.prompt('Copy element payload', payload); }",
    "};",
    "const onClick = (event) => {",
    "event.preventDefault();",
    "event.stopPropagation();",
    "const selector = selectorFor(event.target);",
    "copy(payloadFor(event.target, selector));",
    "cleanup();",
    "};",
    "const onKeyDown = (event) => { if (event.key === 'Escape') cleanup(); };",
    "const label = document.createElement('div');",
    "label.textContent = 'Click an element to copy selector. Esc cancels.';",
    "Object.assign(label.style, { position: 'fixed', zIndex: 2147483647, top: '10px', right: '10px', padding: '6px 8px', background: '#111', color: '#fff', font: '12px system-ui, sans-serif', borderRadius: '6px' });",
    "document.documentElement.appendChild(label);",
    "window.__raycastHammerspoonSelectorPickerCleanup = cleanup;",
    "document.addEventListener('click', onClick, true);",
    "document.addEventListener('keydown', onKeyDown, true);",
    "return JSON.stringify({ status: 'selector-picker-active', url: location.href });",
    "})()",
  }, " ")

  local ok, result = chromeExecuteJavaScript(script, options.activate ~= false)
  if not ok then
    notify("Selector Picker Failed")
    return hs.json.encode({ status = "error", message = tostring(result) })
  end

  if options.autoClick then
    local delay = options.delay or 0.6
    hs.timer.doAfter(delay, function()
      hs.eventtap.keyStroke({ "ctrl", "alt" }, "return", 0)
      hs.timer.doAfter(0.8, function()
        if persistLatestElement() then
          hs.distributednotifications.post("com.singleton23.XSpoon.captureUpdated")
          notify("Element Captured")
        else
          notify("Element Copy Pending")
        end
      end)
    end)
  end

  return result
end

function M.copyLatestElement()
  local file = io.open(LATEST_ELEMENT_PATH, "r")
  if not file then
    return hs.json.encode({ status = "missing-latest-element", path = LATEST_ELEMENT_PATH })
  end

  local value = file:read("*a")
  file:close()

  hs.pasteboard.setContents(value)
  notify("Latest Element Copied")
  return hs.json.encode({ status = "copied-latest-element", path = LATEST_ELEMENT_PATH })
end

local function localElementPayload(element, captureMethod)
  local app = hs.application.frontmostApplication()
  local win = app and app:focusedWindow()
  local frame = axFrame(element)
  local windowFrame = plainRect(win and win:frame())

  return {
    kind = "hammerspoon-local-element",
    captureMethod = captureMethod or "focused",
    appName = app and app:name() or "",
    bundleID = app and app:bundleID() or "",
    appPath = app and app:path() or "",
    windowTitle = win and win:title() or "",
    role = axAttribute(element, "AXRole"),
    subrole = axAttribute(element, "AXSubrole"),
    axTitle = axAttribute(element, "AXTitle"),
    axValue = axAttribute(element, "AXValue"),
    axDescription = axAttribute(element, "AXDescription"),
    frame = frame,
    windowFrame = windowFrame,
    capturedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
end

local function liveElementPayload(element, point)
  local pid = element and element:pid()
  local app = pid and hs.application.applicationForPID(pid) or nil
  local bundleID = app and app:bundleID() or ""
  if bundleID == "com.singleton23.XSpoon" then
    return nil
  end

  local window = axRawAttribute(element, "AXWindow")
  local actions = {}
  local actionsOk, actionNames = pcall(function()
    return element:actionNames()
  end)
  if actionsOk and type(actionNames) == "table" then
    actions = actionNames
  end

  return {
    kind = "hammerspoon-live-element",
    captureMethod = "live-hover",
    appName = app and app:name() or "Unknown App",
    bundleID = bundleID,
    appPath = app and app:path() or "",
    windowTitle = axAttribute(window, "AXTitle"),
    role = axAttribute(element, "AXRole"),
    subrole = axAttribute(element, "AXSubrole"),
    axTitle = axAttribute(element, "AXTitle"),
    axValue = axAttribute(element, "AXValue"),
    axDescription = axAttribute(element, "AXDescription"),
    axPlaceholder = axAttribute(element, "AXPlaceholderValue"),
    axHelp = axAttribute(element, "AXHelp"),
    actions = actions,
    frame = axFrame(element) or { x = point.x, y = point.y, w = 1, h = 1 },
    windowFrame = axFrame(window),
    capturedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
end

local function writeLiveElement(payload)
  local encoded, encodeError = hs.json.encode(payload, true)
  if not encoded then
    hs.printf("XSpoon live payload encode failed: %s", tostring(encodeError))
    return false
  end

  local temporaryPath = LIVE_LATEST_ELEMENT_PATH .. ".tmp"
  local file = io.open(temporaryPath, "w")
  if not file then
    hs.printf("XSpoon live payload write failed: %s", temporaryPath)
    return false
  end

  file:write(encoded)
  file:close()
  return os.rename(temporaryPath, LIVE_LATEST_ELEMENT_PATH) ~= nil
end

local function updateLiveInspector()
  local point = hs.mouse.absolutePosition()
  local element = hs.axuielement.systemElementAtPosition(point)
  if not element then
    return
  end

  local payload = liveElementPayload(element, point)
  if not payload then
    return
  end

  local frame = payload.frame or {}
  local signature = table.concat({
    payload.bundleID or "",
    payload.role or "",
    payload.subrole or "",
    payload.axTitle or "",
    payload.axValue or "",
    payload.axDescription or "",
    tostring(frame.x or 0),
    tostring(frame.y or 0),
    tostring(frame.w or 0),
    tostring(frame.h or 0),
  }, "\0")

  if signature == liveInspectorSignature then
    return
  end

  if writeLiveElement(payload) then
    liveInspectorSignature = signature
    hs.distributednotifications.post("com.singleton23.XSpoon.liveElementUpdated")
  end
end

function M.toggleLiveInspector()
  if liveInspectorTimer then
    liveInspectorTimer:stop()
    liveInspectorTimer = nil
    liveInspectorSignature = ""
    return hs.json.encode({ status = "live-inspector-stopped" })
  end

  liveInspectorSignature = ""
  liveInspectorTimer = hs.timer.doEvery(0.12, updateLiveInspector)
  updateLiveInspector()
  return hs.json.encode({ status = "live-inspector-started", path = LIVE_LATEST_ELEMENT_PATH })
end

function M.liveInspectorActive()
  return liveInspectorTimer ~= nil
end

function M.copyLiveElementToClipboard()
  local file = io.open(LIVE_LATEST_ELEMENT_PATH, "r")
  if not file then
    return false
  end

  local value = file:read("*a")
  file:close()

  if not value or value == "" then
    return false
  end

  hs.pasteboard.setContents(value)
  return true
end

function M.captureFocusedLocalElement()
  local system = hs.axuielement.systemWideElement()
  local focused = system and system:attributeValue("AXFocusedUIElement")
  local app = hs.application.frontmostApplication()
  local win = app and app:focusedWindow()
  local target = localContextTarget()
  local element = target or focused or (win and hs.axuielement.windowElement(win))

  if not element then
    return hs.json.encode({ error = "No focused local element" })
  end

  local payload = localElementPayload(element, target and "context-target" or "focused")
  local encoded, encodeError = hs.json.encode(payload, true)
  if not encoded then
    return hs.json.encode({
      error = "Could not encode local element JSON",
      message = tostring(encodeError or "Unsupported Accessibility value"),
    })
  end

  local file = io.open(LOCAL_LATEST_ELEMENT_PATH, "w")

  if not file then
    return hs.json.encode({ error = "Could not write local element JSON", path = LOCAL_LATEST_ELEMENT_PATH })
  end

  file:write(encoded)
  file:close()
  hs.pasteboard.setContents(encoded)
  hs.distributednotifications.post("com.singleton23.XSpoon.captureUpdated")
  notify("Local Element Captured")
  return hs.json.encode({ status = "captured-local-element", path = LOCAL_LATEST_ELEMENT_PATH })
end

function M.captureCurrentTarget()
  local app = hs.application.frontmostApplication()
  if app and app:bundleID() == "com.google.Chrome" then
    notify("Selector Picker")
    return M.pickSelector({ autoClick = true, delay = 0.6 })
  end

  return M.captureFocusedLocalElement()
end

function M.openFocusedLocalContextMenu()
  local target, errorMessage, app = localContextTarget()
  if not target then
    notify("Context Menu Skipped")
    return hs.json.encode({
      status = "skipped-context-menu",
      message = errorMessage,
      appName = app and app:name() or "",
      bundleID = app and app:bundleID() or "",
    })
  end

  local showMenuOk = pcall(function()
    target:performAction("AXShowMenu")
  end)

  if showMenuOk then
    notify("Context Menu")
    return hs.json.encode({
      status = "opened-context-menu",
      method = "AXShowMenu",
      appName = app and app:name() or "",
      bundleID = app and app:bundleID() or "",
      role = axAttribute(target, "AXRole"),
      title = axAttribute(target, "AXTitle"),
      value = axAttribute(target, "AXValue"),
      description = axAttribute(target, "AXDescription"),
    })
  end

  notify("AX Menu Unavailable")
  return hs.json.encode({
    status = "ax-show-menu-unavailable",
    appName = app and app:name() or "",
    bundleID = app and app:bundleID() or "",
    role = axAttribute(target, "AXRole"),
    title = axAttribute(target, "AXTitle"),
    value = axAttribute(target, "AXValue"),
    description = axAttribute(target, "AXDescription"),
  })
end

function M.rightClickFocusedLocalTarget()
  local target, errorMessage, app = localContextTarget()
  if not target then
    notify("Right Click Skipped")
    return hs.json.encode({
      status = "skipped-right-click",
      message = errorMessage,
      appName = app and app:name() or "",
      bundleID = app and app:bundleID() or "",
    })
  end

  local frame = axFrame(target)
  if not frame then
    notify("No Element Frame")
    return hs.json.encode({
      status = "missing-context-frame",
      appName = app and app:name() or "",
      bundleID = app and app:bundleID() or "",
      role = axAttribute(target, "AXRole"),
    })
  end

  hs.eventtap.rightClick({
    x = frame.x + (frame.w / 2),
    y = frame.y + (frame.h / 2),
  })

  notify("Context Menu")
  return hs.json.encode({
    status = "right-clicked-local-target",
    method = "right-click",
    appName = app and app:name() or "",
    bundleID = app and app:bundleID() or "",
    role = axAttribute(target, "AXRole"),
    title = axAttribute(target, "AXTitle"),
    value = axAttribute(target, "AXValue"),
    description = axAttribute(target, "AXDescription"),
  })
end

local function rootForLocalAction(action)
  local app
  if action.appBundleID and action.appBundleID ~= "" then
    app = hs.application.get(action.appBundleID)
    if not app then
      hs.application.launchOrFocusByBundleID(action.appBundleID)
      hs.timer.usleep(300000)
      app = hs.application.get(action.appBundleID)
    end
  end

  if not app and action.appPath and action.appPath ~= "" then
    hs.application.open(action.appPath)
    hs.timer.usleep(300000)
    app = hs.application.get(action.appBundleID or "") or hs.application.find(action.appName or "")
  end

  if not app and action.appName and action.appName ~= "" then
    app = hs.application.find(action.appName)
  end

  if app then
    app:activate()
  else
    app = hs.application.frontmostApplication()
  end

  if not app then
    return nil, "missing-app"
  end

  local win = app:focusedWindow()
  if not win then
    return nil, "missing-window"
  end

  if action.windowTitleIncludes and action.windowTitleIncludes ~= "" and not containsText(win:title(), action.windowTitleIncludes) then
    return nil, "wrong-window"
  end

  return hs.axuielement.windowElement(win), nil
end

local function findLocalActionElement(action)
  local root, errorMessage = rootForLocalAction(action)
  if not root then
    return nil, errorMessage
  end

  local hasMatchers = (action.axRole and action.axRole ~= "")
    or (action.axTitle and action.axTitle ~= "")
    or (action.axValue and action.axValue ~= "")
    or (action.axDescription and action.axDescription ~= "")

  if not hasMatchers then
    return nil, "missing-local-matchers"
  end

  local function matches(element)
    if action.axRole and action.axRole ~= "" and axAttribute(element, "AXRole") ~= action.axRole then
      return false
    end

    if not containsText(axAttribute(element, "AXTitle"), action.axTitle) then
      return false
    end

    if not containsText(axAttribute(element, "AXValue"), action.axValue) then
      return false
    end

    if not containsText(axAttribute(element, "AXDescription"), action.axDescription) then
      return false
    end

    return true
  end

  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if focused and matches(focused) then
    return focused, nil
  end

  return walkAx(root, matches, 8), nil
end

local function clickLocalActionFrame(action)
  local frame = action.frame
  if type(frame) ~= "table" or not frame.x or not frame.y then
    return nil
  end

  hs.eventtap.leftClick({
    x = frame.x + ((frame.w or 1) / 2),
    y = frame.y + ((frame.h or 1) / 2),
  })

  return hs.json.encode({
    status = "clicked-local-frame",
    appName = action.appName or "",
    bundleID = action.appBundleID or "",
    x = frame.x,
    y = frame.y,
    w = frame.w,
    h = frame.h,
  })
end

local function pressLocalAction(action)
  local element, errorMessage = findLocalActionElement(action)
  if not element then
    local hasMatcher = (action.axRole and action.axRole ~= "")
      or (action.axTitle and action.axTitle ~= "")
      or (action.axValue and action.axValue ~= "")
      or (action.axDescription and action.axDescription ~= "")
    local frameResult = not hasMatcher and clickLocalActionFrame(action)
    if frameResult then
      return frameResult
    end

    return hs.json.encode({ status = "missing-local-element", message = errorMessage or "No matching AX element" })
  end

  local ok = pcall(function()
    element:performAction("AXPress")
  end)

  if not ok then
    return hs.json.encode({ status = "local-press-failed" })
  end

  return hs.json.encode({
    status = "pressed-local-element",
    role = axAttribute(element, "AXRole"),
    title = axAttribute(element, "AXTitle"),
    value = axAttribute(element, "AXValue"),
    description = axAttribute(element, "AXDescription"),
  })
end

local function readElementActions()
  local file = io.open(ELEMENT_ACTIONS_PATH, "r")
  if not file then
    return {}
  end

  local value = file:read("*a")
  file:close()

  local ok, decoded = pcall(function()
    return hs.json.decode(value)
  end)

  if not ok or type(decoded) ~= "table" then
    return {}
  end

  return decoded
end

function M.readElementActions()
  return readElementActions()
end

local function runElementAction(action)
  if action.variant == "local" then
    local result = pressLocalAction(action)

    if action.template == "two-click" then
      hs.timer.doAfter(0.25, function()
        pressLocalAction(action)
      end)
    end

    return result
  end

  local result = M.click({
    selector = action.selector,
    urlIncludes = action.urlIncludes,
    titleIncludes = action.titleIncludes,
    requiredSelector = action.requiredSelector,
    activate = true,
  })

  if action.template == "two-click" then
    hs.timer.doAfter(0.25, function()
      M.click({
        selector = action.selector,
        urlIncludes = action.urlIncludes,
        titleIncludes = action.titleIncludes,
        requiredSelector = action.requiredSelector,
        activate = true,
      })
    end)
  end

  return result
end

function M.runElementAction(action)
  if type(action) ~= "table" then
    return false
  end

  return runElementAction(action)
end

local jobHistoryEntries = {
  prospectId = {
    companyName = "National Prospect ID",
    position = "Video Editor",
    companyPhone = "844-500-0622",
    country = "United States of America",
    responsibilities = "Produced 1,000+ multi-sport athlete highlight reels for recruiting distribution; scaled output to 70 videos per month during peak enrollment growth; built structured post-production systems with templates, naming conventions, and QC workflows; implemented a FastAPI translator layer to stabilize legacy platform workflows; and maintained consistent weekly delivery under enrollment spikes.",
    address1 = "18291 N Pima Rd",
    city = "Scottsdale",
    county = "Maricopa",
    state = "AZ",
    zip = "85255",
    startDate = "02/2024",
    endDate = "06/2026",
    reason = "Contract ended",
    referenceName = "James Holcomb",
    referenceEmail = "jholcomb@prospectid.com",
    referencePhone = "480-340-4559",
    referencePosition = "Reference",
  },
  nursehub = {
    companyName = "NurseHub",
    position = "Video Editor",
    companyPhone = "",
    country = "United States of America",
    responsibilities = "Managed over 50 hours of curriculum; processed 180-200 lesson assets; led most of the migration through deterministic FFmpeg workflows; increased course assembly throughput 2-3x; eliminated export errors; standardized naming schemas; consolidated transcripts; replaced manual timelines with automated batch export pipelines; and established scalable folder architecture and encoding standards.",
    address1 = "6 Liberty Square",
    city = "Boston",
    county = "Suffolk",
    state = "MA",
    zip = "02109",
    startDate = "07/2024",
    endDate = "12/2025",
    reason = "Contract backlog work ended",
    referenceName = "Caroline Dobrez",
    referenceEmail = "caroline.dobrez@nursehub.com",
    referencePosition = "Reference",
  },
  hsn = {
    companyName = "Home Shopping Network",
    position = "Production Technician",
    companyPhone = "727-872-1000",
    country = "United States of America",
    responsibilities = "Supported high-volume retail television content creation through on-set production, camera operation, lighting, and asset capture; worked directly with models, products, and creative teams to produce demo, application, and before/after footage for broadcast and digital use; and ensured visual consistency, brand standards, and technical quality across large-scale product shoots.",
    address1 = "1 HSN Drive",
    city = "St. Petersburg",
    county = "Pinellas",
    state = "FL",
    zip = "33729",
    startDate = "12/2020",
    endDate = "02/2023",
    reason = "Role ended",
  },
  wfla = {
    companyName = "WFLA News Channel 8",
    position = "Production Technician",
    companyPhone = "813-228-7777",
    country = "United States of America",
    responsibilities = "Assisted in live news broadcasts, coordinated studio floor activity with producers and directors under live production constraints, operated graphics systems and robotic cameras, and supported reliable on-air production.",
    address1 = "200 S Parker St",
    city = "Tampa",
    county = "Hillsborough",
    state = "FL",
    zip = "33606",
    startDate = "01/2018",
    endDate = "04/2019",
    reason = "Role ended",
  },
  freelanceBroadcast = {
    companyName = "Freelance",
    position = "Broadcast Production Assistant",
    companyPhone = "",
    country = "United States of America",
    responsibilities = "Supported camera, graphics, and technical operations for live sports broadcasts across collegiate and professional events; assisted with setup, operation, and breakdown of broadcast equipment; and supported live production workflows.",
    address1 = "",
    city = "",
    county = "",
    state = "FL",
    zip = "",
    startDate = "08/2014",
    endDate = "01/2018",
    reason = "Role ended",
  },
  amazonFlex = {
    companyName = "Amazon Flex",
    position = "Delivery Driver",
    companyPhone = "",
    country = "United States of America",
    responsibilities = "Picked up Amazon Flex delivery blocks, delivered packages across assigned routes, followed customer delivery instructions, managed timing and navigation, handled packages carefully, and completed early-morning route work consistently.",
    address1 = "6337 County Road 579",
    city = "Seffner",
    county = "Hillsborough",
    state = "FL",
    zip = "33584",
    startDate = "08/2023",
    endDate = "08/2024",
    reason = "Started NurseHub contract work",
  },
  pepsi = {
    companyName = "Pepsi Warehouse",
    position = "Warehouse Associate",
    companyPhone = "813-971-2550",
    country = "United States of America",
    responsibilities = "Supported product movement in a fast-paced beverage distribution warehouse, used pallet jacks, moved and organized product for daily work, followed warehouse safety expectations, handled repetitive heavy work, and worked with teammates to keep product moving accurately and on schedule.",
    address1 = "11315 N 30th St",
    city = "Tampa",
    county = "Hillsborough",
    state = "FL",
    zip = "33612",
    startDate = "04/2023",
    endDate = "06/2023",
    reason = "Temporary/short-term warehouse role ended",
  },
  optimal = {
    companyName = "Optimal U.S. Logistics",
    position = "Amazon Delivery Driver",
    companyPhone = "727-325-2909",
    country = "United States of America",
    responsibilities = "Delivered Amazon packages on assigned routes for a logistics delivery partner, loaded and organized packages, operated a delivery vehicle, followed customer delivery notes, completed route stops, handled packages with care, and managed daily route timing and navigation.",
    address1 = "8824 E Adamo Dr",
    city = "Tampa",
    county = "Hillsborough",
    state = "FL",
    zip = "33619",
    startDate = "03/2020",
    endDate = "12/2020",
    reason = "Role ended",
    referenceName = "David Ford",
    referencePhone = "813-534-9836",
    referencePosition = "Reference",
  },
  gat = {
    companyName = "GAT Airline Ground Support",
    position = "Passenger Assistant",
    companyPhone = "941-359-2770",
    country = "United States of America",
    responsibilities = "Assisted airline passengers with bags, boarding, deplaning, and mobility needs; provided wheelchair assistance; communicated with passengers and teammates in a safety-sensitive airport environment; and helped keep passenger movement organized during active travel periods.",
    address1 = "6000 Airport Cir",
    city = "Sarasota",
    county = "Sarasota",
    state = "FL",
    zip = "34243",
    startDate = "11/2019",
    endDate = "03/2020",
    reason = "Role ended",
  },
  smh = {
    companyName = "Sarasota Memorial Hospital",
    position = "Valet",
    companyPhone = "941-917-9000",
    country = "United States of America",
    responsibilities = "Provided valet service for hospital patients, visitors, and staff; greeted guests; handled vehicles carefully; supported a smooth arrival flow; delivered direct customer service in a busy medical setting; and assisted people who needed quick, respectful help at the hospital entrance.",
    address1 = "1700 S Tamiami Trail",
    city = "Sarasota",
    county = "Sarasota",
    state = "FL",
    zip = "34239",
    startDate = "05/2019",
    endDate = "10/2019",
    reason = "Role ended",
  },
}

local educationEntries = {
  stetson = {
    schoolName = "Stetson University",
    areaOfStudy = "Communications",
    schoolType = "University",
    graduated = "Yes",
    country = "United States",
    city = "DeLand",
    state = "FL",
    startYear = "2012",
    graduationDate = "05/07/2016",
    graduationYear = "2016",
    referenceName = "Jeff Taylor",
    referenceEmail = "jefft7@gmail.com",
    referencePhone = "407-766-9381",
  },
}

local function fillWorkHistory(jobKey)
  local job = jobHistoryEntries[jobKey]
  if not job then
    return hs.json.encode({ error = "Unknown work-history job: " .. tostring(jobKey) })
  end

  local script = ([[
(() => {
  const job = %s;
  const norm = (value) => String(value || "")
    .toLowerCase()
    .replace(/[*:]/g, " ")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.display !== "none" && s.visibility !== "hidden";
  };
  const labelFor = (el) => {
    const direct = el.id && document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
    if (direct) return direct.innerText;
    const ariaLabel = el.getAttribute("aria-label");
    if (ariaLabel) return ariaLabel;
    const labelledBy = el.getAttribute("aria-labelledby");
    if (labelledBy) {
      const labelledText = labelledBy
        .split(/\s+/)
        .map((id) => document.getElementById(id))
        .filter(Boolean)
        .map((node) => node.innerText || node.textContent || "")
        .join(" ");
      if (labelledText.trim()) return labelledText;
    }
    let p = el;
    for (let i = 0; p && i < 4; i++, p = p.parentElement) {
      const label = p.querySelector && p.querySelector("label");
      if (label && label.innerText.trim()) return label.innerText;
    }
    return "";
  };
  const nearbyTextFor = (el) => {
    const chunks = [];
    let prev = el.previousElementSibling;
    for (let i = 0; prev && i < 3; i++, prev = prev.previousElementSibling) {
      const text = (prev.innerText || prev.textContent || "").trim();
      if (text) chunks.push(text);
    }
    let p = el.parentElement;
    for (let i = 0; p && i < 4; i++, p = p.parentElement) {
      const text = (p.innerText || p.textContent || "").replace(el.value || "", " ").trim();
      if (text) chunks.push(text);
    }
    return chunks.join(" ");
  };
  const controls = [...document.querySelectorAll("input:not([type=hidden]), textarea, select")]
    .filter(visible)
    .map((el) => {
      const fieldMeta = norm([
        el.id,
        el.name,
        el.getAttribute("autocomplete"),
        el.getAttribute("data-testid"),
        el.getAttribute("role"),
        labelFor(el),
        el.placeholder,
      ].join(" "));
      const contextMeta = norm(nearbyTextFor(el));
      return {
        el,
        fieldMeta,
        contextMeta,
        meta: norm([fieldMeta, contextMeta].join(" "))
      };
    });
  const set = (item, value) => {
    if (value == null || value === "") return false;
    if (!item || !item.el) return false;
    const el = item.el;
    if (el.tagName === "SELECT") {
      const wanted = norm(value);
      const option = [...el.options].find((opt) => norm(opt.value) === wanted || norm(opt.text) === wanted || norm(opt.text).includes(wanted));
      if (!option) return false;
      el.value = option.value;
    } else {
      if (el.tagName === "TEXTAREA") {
        el.focus();
        if (el.select) el.select();
        document.execCommand("insertText", false, value || "");
      }
      const setter = Object.getOwnPropertyDescriptor(el.constructor.prototype, "value")?.set
        || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set
        || Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set;
      if (!el.value && setter) setter.call(el, value || "");
      else if (!el.value) el.value = value || "";
    }
    el.focus();
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur", { bubbles: true }));
    return true;
  };
  const indexedCompanyFields = controls
    .map((item) => ({ item, match: item.el.id.match(/^workHistory\.(?:companyName|employer)\.(\d+)$/) }))
    .filter((entry) => entry.match);
  if (indexedCompanyFields.length) {
    const activeId = document.activeElement && document.activeElement.id || "";
    const activeMatch = activeId.match(/(?:workHistory\.[^.]+|work-history-address)-(\d+)|workHistory\.[^.]+\.(\d+)/);
    const activeRow = activeMatch && (activeMatch[1] || activeMatch[2]);
    const chosen = indexedCompanyFields.find((entry) => entry.match[1] === activeRow)
      || indexedCompanyFields.find((entry) => !entry.item.el.value.trim())
      || indexedCompanyFields[0];
    const i = chosen.match[1];
    const byId = (...ids) => ({ el: ids.map((id) => document.getElementById(id)).find(Boolean) });
    const filled = {
      companyName: set(chosen.item, job.companyName),
      position: set(byId(`workHistory.position.${i}`), job.position),
      companyPhone: set(byId(`workHistory.companyPhone.${i}`), job.companyPhone),
      country: set(byId(
        `workHistory.country.${i}`,
        `public-candidate-work-history-address-${i}-country`
      ), job.country),
      responsibilities: set(byId(
        `workHistory.responsibilities.${i}`,
        `workHistory.majorDuties.${i}`,
        `workHistory.describeMajorDuties.${i}`,
        `workHistory.jobDescription.${i}`
      ), job.responsibilities),
      city: set(byId(`public-candidate-work-history-address-${i}-city`), job.city),
      county: set(byId(`public-candidate-work-history-address-${i}-county`), job.county),
      state: set(byId(`public-candidate-work-history-address-${i}-us-state`), job.state),
      zip: set(byId(`public-candidate-work-history-address-${i}-zip`), job.zip),
      reason: set(byId(
        `workHistory.reasonForLeaving.${i}`,
        `workHistory.reason.${i}`,
        `workHistory.separationReason.${i}`,
        `workHistory.whyDidYouLeave.${i}`
      ), job.reason),
      referenceName: set(byId(
        `workHistory.supervisorName.${i}`,
        `workHistory.referenceName.${i}`,
        `workHistory.reference.name.${i}`
      ), job.referenceName),
      referenceEmail: set(byId(
        `workHistory.supervisorEmail.${i}`,
        `workHistory.referenceEmail.${i}`,
        `workHistory.reference.email.${i}`
      ), job.referenceEmail),
      referencePhone: set(byId(
        `workHistory.supervisorPhone.${i}`,
        `workHistory.referencePhone.${i}`,
        `workHistory.reference.phone.${i}`
      ), job.referencePhone),
      referencePosition: set(byId(
        `workHistory.supervisorPosition.${i}`,
        `workHistory.referencePosition.${i}`,
        `workHistory.reference.position.${i}`
      ), job.referencePosition),
    };
    const address = document.getElementById(`public-candidate-work-history-address-${i}-address-1`);
    if (address) {
      address.scrollIntoView({ block: "center" });
      address.focus();
      if (address.select) address.select();
    }
    return JSON.stringify({
      title: document.title,
      row: i,
      addressFocused: !!address,
      addressIds: {
        city: `public-candidate-work-history-address-${i}-city`,
        county: `public-candidate-work-history-address-${i}-county`,
        state: `public-candidate-work-history-address-${i}-us-state`,
        zip: `public-candidate-work-history-address-${i}-zip`,
      },
      filled
    });
  }
  const hasTerm = (value, term) => term.includes(" ")
    ? value.includes(term)
    : value.split(" ").includes(term);
  const hasAny = (value, words) => words.some((word) => hasTerm(value, word));
  const hasAll = (value, words) => words.every((word) => hasTerm(value, word));
  const companyTerms = [
    "company name",
    "companyname",
    "company",
    "employer name",
    "employername",
    "employer",
    "organization name",
    "organization",
    "organisation",
    "business name",
  ];
  const genericAutocomplete = (item) => item.fieldMeta === ""
    || hasAny(item.fieldMeta, ["type to search", "select", "combobox"]);
  const isCompany = (item) => (hasAny(item.fieldMeta, companyTerms)
    || (genericAutocomplete(item) && hasAny(item.contextMeta, companyTerms)))
    && !hasAny(item.fieldMeta, ["company url", "company website", "website", "url", "phone", "email", "reference", "supervisor"]);
  const activeIndex = controls.findIndex((item) => item.el === document.activeElement);
  let start = activeIndex >= 0 ? controls.slice(0, activeIndex + 1).map(isCompany).lastIndexOf(true) : -1;
  if (start < 0) start = controls.findIndex((item) => isCompany(item) && !item.el.value.trim());
  if (start < 0) start = controls.findIndex(isCompany);
  if (start < 0) return JSON.stringify({
    error: "No Employer or Company field found",
    visibleFields: controls.slice(0, 30).map((item) => item.meta)
  });
  let end = controls.findIndex((item, index) => index > start && isCompany(item));
  if (end < 0) end = controls.length;
  const row = controls.slice(start, end);
  const matches = (item, needles) => hasAll(item.fieldMeta, needles) || (item.fieldMeta === "" && hasAll(item.meta, needles));
  const find = (...needles) => row.find((item) => matches(item, needles));
  const findAny = (...groups) => groups.map((needles) => find(...needles)).find(Boolean);
  const findSmart = (positiveGroups, negativeWords) => {
    const blocked = negativeWords || [];
    return positiveGroups
      .map((needles) => row.find((item) => matches(item, needles)
        && !blocked.some((word) => item.fieldMeta.includes(word))))
      .find(Boolean);
  };
  const address = find("address", "line 1") || find("address-1") || find("address 1");
  const responsibilities = findAny(["responsibilities"], ["major", "duties"], ["describe", "duties"], ["duties"], ["job", "description"], ["work", "description"], ["description"]);
  const city = find("city");
  const county = find("county");
  const state = find("state");
  const zip = find("zip");
  const filled = {
    companyName: set(row[start >= 0 ? 0 : 0], job.companyName),
    position: set(findSmart([
      ["position held"],
      ["position"],
      ["job title"],
      ["title"],
      ["role"],
    ], ["company", "supervisor", "reference"]), job.position),
    companyPhone: set(findAny(["company", "phone"], ["employer", "phone"], ["work", "phone"], ["phone"]), job.companyPhone),
    country: set(findAny(["country"], ["location", "country"]), job.country),
    responsibilities: set(responsibilities, job.responsibilities),
    city: set(city, job.city),
    county: set(county, job.county),
    state: set(state, job.state),
    zip: set(zip, job.zip),
    reason: set(findAny(["reason", "leaving"], ["reason"], ["leaving"], ["separation", "reason"], ["why", "left"]), job.reason),
    referenceName: set(findAny(["supervisor", "name"], ["reference", "name"], ["manager", "name"]), job.referenceName),
    referenceEmail: set(findAny(["supervisor", "email"], ["reference", "email"], ["manager", "email"]), job.referenceEmail),
    referencePhone: set(findAny(["supervisor", "phone"], ["reference", "phone"], ["manager", "phone"]), job.referencePhone),
    referencePosition: set(findAny(["supervisor", "position"], ["reference", "position"], ["manager", "position"], ["reference", "title"]), job.referencePosition),
  };
  if (address) {
    address.el.scrollIntoView({ block: "center" });
    address.el.focus();
    if (address.el.select) address.el.select();
  }
  return JSON.stringify({
    title: document.title,
    addressFocused: !!address,
    addressIds: {
      city: city && city.el.id,
      county: county && county.el.id,
      state: state && state.el.id,
      zip: zip && zip.el.id,
    },
    descriptionId: responsibilities && responsibilities.el.id,
    descriptionFocused: !!responsibilities,
    filled
  });
})()
]]):format(hs.json.encode(job))

  local ok, result = chromeExecuteJavaScript(script, { activate = true })
  if not ok then
    return hs.json.encode({ error = result })
  end

  local decodedOk, decoded = pcall(function()
    return hs.json.decode(result)
  end)
  if decodedOk and decoded and decoded.addressFocused and job.address1 ~= "" then
    local ids = decoded.addressIds or {}
    hs.timer.doAfter(0.2, function()
      -- ponytail: some job forms roll back Address Line 1 unless it comes through the keyboard path.
      hs.osascript.applescript('tell application "System Events" to keystroke "a" using command down')
      hs.osascript.applescript('tell application "System Events" to keystroke ' .. appleScriptString(job.address1))
      hs.timer.doAfter(0.3, function()
        chromeExecuteJavaScript(([[(() => {
          const values = %s;
          const set = (id, value) => {
            const el = id && document.getElementById(id);
            if (!el) return false;
            el.value = value || "";
            el.dispatchEvent(new Event("input", { bubbles: true }));
            el.dispatchEvent(new Event("change", { bubbles: true }));
            el.dispatchEvent(new Event("blur", { bubbles: true }));
            return true;
          };
          return JSON.stringify({
            city: set(values.cityId, values.city),
            county: set(values.countyId, values.county),
            state: set(values.stateId, values.state),
            zip: set(values.zipId, values.zip),
          });
        })()]]):format(hs.json.encode({
          cityId = ids.city,
          countyId = ids.county,
          stateId = ids.state,
          zipId = ids.zip,
          city = job.city,
          county = job.county,
          state = job.state,
          zip = job.zip,
        })), { activate = true })
      end)
    end)
  end
  if decodedOk and decoded and decoded.descriptionFocused and not decoded.addressFocused and job.responsibilities ~= "" then
    hs.timer.doAfter(0.2, function()
      local descriptionId = tostring(decoded.descriptionId or "")
      chromeExecuteJavaScript(([[(() => {
        const id = %s;
        const el = id ? document.getElementById(id) : document.querySelector("textarea[name='description'], textarea[placeholder='Description']");
        if (!el) return "missing-description";
        el.scrollIntoView({ block: "center" });
        el.focus();
        if (el.select) el.select();
        return "focused-description";
      })()]]):format(jsString(descriptionId)), { activate = true })
      hs.timer.doAfter(0.2, function()
        systemPasteText(job.responsibilities)
      end)
    end)
  end
  notify("Dates: " .. tostring(job.startDate or "") .. "-" .. tostring(job.endDate or ""))
  return result
end

local function fillEducation(entryKey)
  local entry = educationEntries[entryKey]
  if not entry then
    return hs.json.encode({ error = "Unknown education entry: " .. tostring(entryKey) })
  end

  local script = ([[
(() => {
  const entry = %s;
  const norm = (value) => String(value || "").toLowerCase().replace(/\s+/g, " ").trim();
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.display !== "none" && s.visibility !== "hidden";
  };
  const labelFor = (el) => {
    const direct = el.id && document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
    if (direct) return direct.innerText;
    let p = el;
    for (let i = 0; p && i < 5; i++, p = p.parentElement) {
      const label = p.querySelector && p.querySelector("label");
      if (label && label.innerText.trim()) return label.innerText;
      const text = [...p.childNodes].filter((node) => node.nodeType === Node.TEXT_NODE).map((node) => node.textContent).join(" ").trim();
      if (text) return text;
    }
    return "";
  };
  const controls = [...document.querySelectorAll("input:not([type=hidden]), textarea, select")]
    .filter(visible)
    .map((el) => ({ el, meta: norm([el.id, el.name, labelFor(el), el.placeholder].join(" ")) }));
  const set = (item, value) => {
    if (value == null || value === "" || !item || !item.el) return false;
    const el = item.el;
    if (el.tagName === "SELECT") {
      const wanted = norm(value);
      const option = [...el.options].find((opt) => norm(opt.value) === wanted || norm(opt.text) === wanted || norm(opt.text).includes(wanted));
      if (!option) return false;
      el.value = option.value;
    } else {
      el.value = value;
    }
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur", { bubbles: true }));
    return true;
  };
  const find = (...needles) => controls.find((item) => needles.every((needle) => item.meta.includes(needle)));
  const filled = {
    schoolName: set(find("school", "name") || find("school") || find("university"), entry.schoolName),
    areaOfStudy: set(find("area", "study") || find("field", "study") || find("major"), entry.areaOfStudy),
    schoolType: set(find("school", "type"), entry.schoolType),
    graduated: set(find("graduate") || find("graduated"), entry.graduated),
    country: set(find("country"), entry.country),
    city: set(find("city"), entry.city),
    state: set(find("state"), entry.state),
    startYear: set(find("start", "year"), entry.startYear),
    graduationDate: set(find("graduation", "date") || find("grad", "date"), entry.graduationDate),
    graduationYear: set(find("graduation", "year") || find("grad", "year") || find("end", "year"), entry.graduationYear),
    referenceName: set(find("reference", "name"), entry.referenceName),
    referenceEmail: set(find("reference", "email"), entry.referenceEmail),
    referencePhone: set(find("reference", "phone"), entry.referencePhone),
  };
  return JSON.stringify({ title: document.title, filled });
})()
]]):format(hs.json.encode(entry))

  local ok, result = chromeExecuteJavaScript(script, { activate = true })
  if not ok then
    return hs.json.encode({ error = result })
  end
  notify("Filled education: " .. entry.schoolName)
  return result
end

catalog = {
  {
    id = "automation.health",
    name = "Automation Health Check",
    description = "Copies fast Hammerspoon, hotkey, module, and Chrome URL health as JSON.",
    keywords = { "automation", "health", "debug", "hammerspoon", "chrome" },
    run = function()
      local result = M.health()
      hs.pasteboard.setContents(result)
      notify("Automation Health Copied")
      return result
    end,
  },
  {
    id = "chrome.javascript-health",
    name = "Chrome JavaScript Health",
    description = "Explicitly tests Chrome JavaScript from Apple Events and copies the result as JSON.",
    keywords = { "chrome", "javascript", "apple", "events", "debug" },
    run = function()
      local result = hs.json.encode(chromeJavaScriptHealth())
      hs.pasteboard.setContents(result)
      notify("Chrome JS Health Copied")
      return result
    end,
  },
  {
    id = "job-form.education.stetson",
    name = "Fill Education: Stetson",
    description = "Fills recognizable education fields in the active Chrome form.",
    keywords = { "education", "school", "stetson", "application" },
    run = function()
      return fillEducation("stetson")
    end,
  },
  {
    id = "job-form.work-history.prospect-id",
    name = "Fill Work History: Prospect ID",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "career", "prospect", "video" },
    run = function()
      return fillWorkHistory("prospectId")
    end,
  },
  {
    id = "job-form.work-history.nursehub",
    name = "Fill Work History: NurseHub",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "career", "nursehub", "video" },
    run = function()
      return fillWorkHistory("nursehub")
    end,
  },
  {
    id = "job-form.work-history.hsn",
    name = "Fill Work History: HSN",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "career", "hsn", "production" },
    run = function()
      return fillWorkHistory("hsn")
    end,
  },
  {
    id = "job-form.work-history.wfla",
    name = "Fill Work History: WFLA",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "career", "wfla", "production" },
    run = function()
      return fillWorkHistory("wfla")
    end,
  },
  {
    id = "job-form.work-history.freelance-broadcast",
    name = "Fill Work History: Freelance Broadcast",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "career", "freelance", "broadcast" },
    run = function()
      return fillWorkHistory("freelanceBroadcast")
    end,
  },
  {
    id = "job-form.work-history.amazon-flex",
    name = "Fill Work History: Amazon Flex",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "amazon", "flex" },
    run = function()
      return fillWorkHistory("amazonFlex")
    end,
  },
  {
    id = "job-form.work-history.pepsi",
    name = "Fill Work History: Pepsi Warehouse",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "pepsi", "warehouse" },
    run = function()
      return fillWorkHistory("pepsi")
    end,
  },
  {
    id = "job-form.work-history.optimal",
    name = "Fill Work History: Optimal U.S. Logistics",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "optimal", "amazon" },
    run = function()
      return fillWorkHistory("optimal")
    end,
  },
  {
    id = "job-form.work-history.gat",
    name = "Fill Work History: GAT Airline",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "gat", "airline" },
    run = function()
      return fillWorkHistory("gat")
    end,
  },
  {
    id = "job-form.work-history.smh",
    name = "Fill Work History: Sarasota Memorial",
    description = "Fills recognizable work-history fields in the active Chrome form.",
    keywords = { "work", "history", "application", "sarasota", "memorial" },
    run = function()
      return fillWorkHistory("smh")
    end,
  },
  {
    id = "chrome.save",
    name = "Chrome Click Save",
    description = "Clicks a visible Save control in the active Chrome tab.",
    keywords = { "chrome", "save", "button" },
    run = function()
      return M.clickVisibleLabel("Save")
    end,
  },
  {
    id = "chrome.close",
    name = "Chrome Click Close",
    description = "Clicks a visible Close control in the active Chrome tab.",
    keywords = { "chrome", "close", "escape" },
    run = function()
      return M.clickVisibleLabel("Close")
    end,
  },
  {
    id = "chrome.copy-visible-controls",
    name = "Copy Chrome Visible Controls",
    description = "Copies visible buttons and links from the active Chrome tab as JSON.",
    keywords = { "chrome", "inspect", "controls", "debug" },
    run = M.copyVisibleControls,
  },
  {
    id = "chrome.click-clipboard-selector",
    name = "Chrome Click Clipboard Selector",
    description = "Clicks the CSS selector currently copied to the clipboard.",
    keywords = { "chrome", "selector", "clipboard", "devtools" },
    run = M.clickClipboardSelector,
  },
  {
    id = "chrome.click-clipboard-xpath",
    name = "Chrome Click Clipboard XPath",
    description = "Clicks the XPath currently copied to the clipboard.",
    keywords = { "chrome", "xpath", "clipboard", "devtools" },
    run = M.clickClipboardXPath,
  },
  {
    id = "chrome.pick-selector",
    name = "Chrome Pick Selector",
    description = "Arms the active Chrome tab so the next clicked element copies a CSS selector.",
    keywords = { "chrome", "selector", "picker", "inspect" },
    run = M.pickSelector,
  },
  {
    id = "chrome.auto-pick-selector",
    name = "Chrome Auto Pick Selector",
    description = "Arms the active Chrome tab, waits briefly, then triggers the current-pointer click shortcut.",
    keywords = { "chrome", "selector", "picker", "inspect", "auto" },
    run = function()
      return M.pickSelector({ autoClick = true, delay = 0.6 })
    end,
  },
  {
    id = "chrome.copy-latest-element",
    name = "Chrome Copy Latest Element",
    description = "Copies the latest captured browser element payload back to the clipboard.",
    keywords = { "chrome", "element", "selector", "latest" },
    run = M.copyLatestElement,
  },
  {
    id = "local.capture-focused-element",
    name = "Capture Focused Local Element",
    description = "Captures the focused macOS Accessibility element as JSON for local app actions.",
    keywords = { "local", "app", "accessibility", "ax", "element", "capture" },
    run = M.captureFocusedLocalElement,
  },
  {
    id = "local.open-context-menu",
    name = "Open Focused Local Context Menu",
    description = "Uses AXShowMenu on the focused or selected item in Finder, Raycast, Raycast Beta, or Eagle.",
    keywords = { "local", "app", "ax", "context", "menu", "finder", "raycast", "eagle" },
    run = M.openFocusedLocalContextMenu,
  },
  {
    id = "local.right-click-focused-target",
    name = "Right Click Focused Local Target",
    description = "Fallback coordinate right-click for the focused or selected item in Finder, Raycast, Raycast Beta, or Eagle.",
    keywords = { "local", "app", "right", "click", "context", "menu", "finder", "raycast", "eagle", "fallback" },
    run = M.rightClickFocusedLocalTarget,
  },
}

local byId = {}
for _, script in ipairs(catalog) do
  byId[script.id] = script
end

local function elementActionById(id)
  for _, action in ipairs(readElementActions()) do
    if action.id == id then
      return action
    end
  end
  return nil
end

local function groupForScriptId(id)
  if id:match("^job%-form%.") then
    return "Job Filling"
  end
  if id:match("^chrome%.") then
    return "Chrome"
  end
  if id:match("^local%.") then
    return "Local Actions"
  end
  if id:match("^automation%.") then
    return "Diagnostics"
  end
  return "Other"
end

function M.list()
  local items = {}
  for _, script in ipairs(catalog) do
    table.insert(items, {
      id = script.id,
      name = script.name,
      description = script.description,
      keywords = script.keywords,
      group = script.group or groupForScriptId(script.id),
    })
  end

  for _, action in ipairs(readElementActions()) do
    local isLocal = action.variant == "local"
    table.insert(items, {
      id = action.id,
      name = action.name,
      description = action.template == "two-click" and (isLocal and "Saved local app action, two presses" or "Saved browser element action, two clicks")
        or (isLocal and "Saved local app action" or "Saved browser element action"),
      keywords = isLocal and { "local", "app", "element", "saved" } or { "chrome", "element", "saved" },
      group = isLocal and "Local Actions" or "Saved Browser Actions",
    })
  end

  return hs.json.encode(items)
end

function M.execute(id)
  local script = byId[id]

  if not script then
    local action = elementActionById(id)
    if action then
      return runElementAction(action)
    end

    return hs.json.encode({ error = "Unknown script id: " .. tostring(id) })
  end

  local ok, result = pcall(script.run)
  if not ok then
    return hs.json.encode({ error = tostring(result) })
  end

  if type(result) == "string" and result ~= "" then
    return result
  end

  return hs.json.encode({ status = "ok" })
end

function M.bindHotkeys()
  M.bindContextMenuHotkey()
  hs.hotkey.bind({ "ctrl", "alt" }, "0", function()
    hs.distributednotifications.post("com.singleton23.XSpoon.openInspector")
  end)
  hs.hotkey.bind({ "ctrl", "alt" }, "o", function()
    hs.distributednotifications.post("com.singleton23.XSpoon.toggleMenu")
  end)
  hs.hotkey.bind({ "ctrl", "alt" }, "i", function()
    M.toggleLiveInspector()
    hs.distributednotifications.post("com.singleton23.XSpoon.inspectCurrentApp")
  end)
  hs.hotkey.bind({ "ctrl", "alt" }, "e", function()
    M.copyLiveElementToClipboard()
    hs.distributednotifications.post("com.singleton23.XSpoon.captureCurrentElement")
  end)

end

function M.bindContextMenuHotkey()
  hs.hotkey.bind({ "ctrl", "alt" }, "m", M.openFocusedLocalContextMenu)
end

function M.bindElementActionHotkeys()
  for _, action in ipairs(readElementActions()) do
    if action.hotkey and action.hotkey.key and action.hotkey.modifiers then
      hs.hotkey.bind(action.hotkey.modifiers, action.hotkey.key, function()
        runElementAction(action)
      end)
    end
  end
end

return M
