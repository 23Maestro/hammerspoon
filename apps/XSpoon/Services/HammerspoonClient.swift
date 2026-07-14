import Foundation

struct HammerspoonClient {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func latestSnapshot(source: CaptureSource) -> ElementSnapshot? {
        let filename = source == .accessibility ? "local_element_latest.json" : "browser_element_latest.json"
        return snapshot(filename: filename)
    }

    func liveSnapshot() -> ElementSnapshot? {
        snapshot(filename: "live_element_latest.json")
    }

    @discardableResult
    func toggleLiveInspector() -> Result<String, Error> {
        executeHammerspoon("return __SCRIPTS__.toggleLiveInspector()")
    }

    private func snapshot(filename: String) -> ElementSnapshot? {
        let url = home.appendingPathComponent(".hammerspoon").appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ElementSnapshot.self, from: data)
    }

    func captureCurrentTarget() -> Result<String, Error> {
        executeHammerspoon("return __SCRIPTS__.captureCurrentTarget()")
    }

    private func executeHammerspoon(_ lua: String) -> Result<String, Error> {
        let script = """
        tell application "Hammerspoon"
          execute lua code "\(lua)"
        end tell
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                return .failure(NSError(domain: "Hammerspoon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: result]))
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
}
