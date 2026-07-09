local M = {}

local active = rawget(_G, "__automationNotifierCanvas")

local function deleteActive()
  if active then
    pcall(function()
      active:delete()
    end)
  end

  active = nil
  _G.__automationNotifierCanvas = nil
end

deleteActive()

local function screenFrame()
  local screen = hs.screen.mainScreen()
  return screen and screen:frame() or { x = 0, y = 0, w = 1440, h = 900 }
end

function M.show(message, seconds)
  local frame = screenFrame()
  local width = 350
  local height = 66
  local rect = {
    x = frame.x + frame.w - width - 24,
    y = frame.y + 24,
    w = width,
    h = height,
  }

  deleteActive()

  local canvas = hs.canvas.new(rect)
  canvas:level(hs.canvas.windowLevels.floating)
  canvas:behavior({ hs.canvas.windowBehaviors.canJoinAllSpaces, hs.canvas.windowBehaviors.stationary })
  canvas:appendElements({
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 18, yRadius = 18 },
    fillColor = { red = 0, green = 0, blue = 0, alpha = 1 },
    strokeColor = { white = 1, alpha = 1 },
    strokeWidth = 2,
  }, {
    type = "text",
    text = tostring(message or ""),
    textColor = { white = 1, alpha = 1 },
    textSize = 22,
    textAlignment = "center",
    frame = { x = 18, y = 20, w = width - 36, h = 28 },
  })

  active = canvas
  _G.__automationNotifierCanvas = canvas
  canvas:show()

  hs.timer.doAfter(seconds or 1.2, function()
    if active == canvas then
      active = nil
      _G.__automationNotifierCanvas = nil
    end
    pcall(function()
      canvas:delete()
    end)
  end)
end

function M.clear()
  deleteActive()
end

return M
