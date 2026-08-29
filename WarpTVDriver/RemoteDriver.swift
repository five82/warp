import XCTest

/// Headless remote for the tvOS simulator, not a test of anything. simctl has
/// no remote input and idb's HID events are dropped (dtuhidd owns the boot's
/// keyboard service), so this "test" launches the app and forwards presses via
/// XCUIRemote, which injects through testmanagerd and needs no window focus.
/// Commands arrive over a file protocol driven by scripts/tv-driver.sh:
/// the script atomically moves a `cmd` file into the driver directory, the
/// driver executes its tokens and deletes it. Simulator processes run
/// unsandboxed, so the host and the runner share /tmp directly.
final class RemoteDriver: XCTestCase {
    func testDrive() throws {
        let env = ProcessInfo.processInfo.environment

        let app = XCUIApplication()
        if let args = env["DRIVER_APP_ARGS"], !args.isEmpty {
            app.launchArguments = args.split(separator: " ").map(String.init)
        }
        app.launch()

        let fm = FileManager.default
        let dir = URL(fileURLWithPath: env["DRIVER_DIR"] ?? "/tmp/warp-tv-driver")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let cmdFile = dir.appendingPathComponent("cmd")
        try? fm.removeItem(at: cmdFile)
        fm.createFile(atPath: dir.appendingPathComponent("ready").path, contents: nil)

        let buttons: [Substring: XCUIRemote.Button] = [
            "up": .up, "down": .down, "left": .left, "right": .right,
            "select": .select, "menu": .menu, "playpause": .playPause,
        ]
        // Backstop so an orphaned driver does not hold the simulator forever.
        let deadline = Date().addingTimeInterval(30 * 60)
        while Date() < deadline {
            guard let line = try? String(contentsOf: cmdFile, encoding: .utf8) else {
                Thread.sleep(forTimeInterval: 0.15)
                continue
            }
            try? fm.removeItem(at: cmdFile)
            for token in line.split(whereSeparator: { $0.isWhitespace }) {
                if token == "quit" { return }
                if let button = buttons[token] {
                    XCUIRemote.shared.press(button)
                    // Let the focus engine's motion settle between presses.
                    Thread.sleep(forTimeInterval: 0.35)
                }
            }
        }
    }
}
