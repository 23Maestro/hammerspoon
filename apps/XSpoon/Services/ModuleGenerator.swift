import Foundation

struct ModuleGenerator {
    private static let builtInModuleIDs: Set<String> = [
        "chrome", "codex", "finder", "keyboard_maestro",
        "keyboard-maestro", "prospect_id", "prospect-id"
    ]

    static func isBuiltIn(_ appID: String) -> Bool {
        builtInModuleIDs.contains(appID)
    }

    static func generate(app: MyAppDefinition, to url: URL) throws {
        guard !isBuiltIn(app.id) else { return }

        let slug = app.id
        let bundleID = app.bundleIdentifier
        let lua = """
        local browser = require("scripts.browser_automations")

        local M = {}
        M.id = "\(slug)"

        function M.matches(context)
          return context.bundleID == "\(bundleID)"
        end

        local function savedAction(semanticAction)
          return function()
            for _, action in ipairs(browser.actionsForApp("\(bundleID)")) do
              if tostring(action.semanticAction or "") == semanticAction then
                return browser.runElementAction(action)
              end
            end
            return false
          end
        end

        M.actions = {}
        for _, action in ipairs(browser.actionsForApp("\(bundleID)")) do
          local semantic = tostring(action.semanticAction or "")
          if semantic ~= "" then
            M.actions[semantic] = savedAction(semantic)
          end
        end

        return M
        """
        try lua.write(to: url, atomically: true, encoding: .utf8)
    }
}
