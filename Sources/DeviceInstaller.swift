import AppKit
import Foundation

struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct Target {
    let id: String
    let label: String
    let kind: String
    let booted: Bool
}
let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser.path

func run(_ executable: String, _ arguments: [String], timeout: Double = 45) throws -> String {
    let log = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    fm.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log)
    defer {
        try? handle.close()
        try? fm.removeItem(at: log)
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    var env = ProcessInfo.processInfo.environment
    if fm.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer") {
        env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    }
    p.environment = env
    p.standardOutput = handle
    p.standardError = handle
    try p.run()
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if p.isRunning {
        p.terminate()
        Thread.sleep(forTimeInterval: 0.3)
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        p.waitUntilExit()
        throw Failure(message: "The operation timed out. Check the device connection and retry.")
    }
    p.waitUntilExit()
    let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    guard p.terminationStatus == 0 else {
        throw Failure(message: output.isEmpty ? "Command failed (\(p.terminationStatus))." : output)
    }
    return output
}

func json(_ args: [String], coreDevice: Bool = false) throws -> [String: Any] {
    if coreDevice {
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? fm.removeItem(at: url) }
        _ = try run("/usr/bin/xcrun", args + ["--json-output", url.path, "--timeout", "25"])
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            ?? [:]
    }
    let output = try run("/usr/bin/xcrun", args)
    // simctl may prepend diagnostics; the JSON object begins at the first brace.
    guard let start = output.firstIndex(of: "{") else { throw Failure(message: output) }
    return try JSONSerialization.jsonObject(with: Data(output[start...].utf8)) as? [String: Any]
        ?? [:]
}

func adbPath() throws -> String {
    var paths = [
        home + "/Library/Android/sdk/platform-tools/adb", "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
    ]
    if let r = Bundle.main.resourcePath { paths.insert(r + "/platform-tools/adb", at: 0) }
    for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
        if let root = ProcessInfo.processInfo.environment[key] {
            paths.append(root + "/platform-tools/adb")
        }
    }
    let unity = "/Applications/Unity/Hub/Editor"
    for version in (try? fm.contentsOfDirectory(atPath: unity)) ?? [] {
        paths.append(
            unity + "/" + version + "/PlaybackEngines/AndroidPlayer/SDK/platform-tools/adb")
        paths.append(
            unity + "/" + version
                + "/Unity.app/Contents/PlaybackEngines/AndroidPlayer/SDK/platform-tools/adb")
    }
    guard let path = paths.first(where: { fm.isExecutableFile(atPath: $0) }) else {
        throw Failure(
            message:
                "Android platform-tools (adb) was not found. Install it using Android Studio’s SDK Manager, then retry."
        )
    }
    return path
}

func androidTargets(_ text: String) -> [Target] {
    text.split(separator: "\n").compactMap { line in
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 2, fields[1] == "device" else { return nil }
        let model =
            fields.first(where: { $0.hasPrefix("model:") })?.dropFirst(6).replacingOccurrences(
                of: "_", with: " ") ?? fields[0]
        let type = fields[0].hasPrefix("emulator-") ? "Android emulator" : "Android phone"
        return Target(
            id: fields[0], label: "\(model) · \(type) · \(fields[0])", kind: "android", booted: true
        )
    }
}

func targets(_ kind: String) throws -> [Target] {
    if kind == "android" { return androidTargets(try run(adbPath(), ["devices", "-l"])) }
    if kind == "simulator" {
        let data = try json(["simctl", "list", "devices", "available", "--json"])
        let groups = data["devices"] as? [String: [[String: Any]]] ?? [:]
        return groups.filter { $0.key.contains("iOS") }.flatMap { runtime, devices in
            devices.compactMap { d -> Target? in
                guard d["isAvailable"] as? Bool == true, let id = d["udid"] as? String else {
                    return nil
                }
                let booted = d["state"] as? String == "Booted"
                let os =
                    runtime.components(separatedBy: ".").last?.replacingOccurrences(
                        of: "-", with: " ") ?? runtime
                return Target(
                    id: id,
                    label:
                        "\(d["name"] as? String ?? "Simulator") · \(os) · \(booted ? "Running" : "Start & install") · \(id.prefix(8))",
                    kind: kind, booted: booted)
            }
        }.sorted { ($0.booted ? "0" : "1") + $0.label < ($1.booted ? "0" : "1") + $1.label }
    }
    let data = try json(["devicectl", "list", "devices"], coreDevice: true)
    let result = data["result"] as? [String: Any] ?? [:]
    return (result["devices"] as? [[String: Any]] ?? []).compactMap { d in
        let props = d["deviceProperties"] as? [String: Any] ?? [:]
        let hardware = d["hardwareProperties"] as? [String: Any] ?? [:]
        let connection = d["connectionProperties"] as? [String: Any] ?? [:]
        guard let id = d["identifier"] as? String,
            ["iOS", "iPadOS"].contains(hardware["platform"] as? String ?? ""),
            connection["pairingState"] as? String == "paired",
            connection["tunnelState"] as? String == "connected"
        else { return nil }
        return Target(
            id: id,
            label:
                "\(props["name"] as? String ?? "iPhone") · \(props["osVersionNumber"] as? String ?? "iOS") · \(id.prefix(8))",
            kind: "ios", booted: true)
    }.sorted { $0.label < $1.label }
}

func appKind(_ path: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Info.plist"))
    let info =
        try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    let platforms = info["CFBundleSupportedPlatforms"] as? [String] ?? []
    if platforms.contains("iPhoneSimulator") { return "simulator" }
    if platforms.contains("iPhoneOS") { return "ios" }
    throw Failure(message: "This .app is not an iOS device or iOS Simulator build.")
}

class Controller: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var status: NSTextField!
    var scratch: URL?
    var appPath = ""
    var kind = ""
    var filename = ""
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 130), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.title = "Install on Device"
        window.center()
        status = NSTextField(wrappingLabelWithString: "Preparing app…")
        status.frame = NSRect(x: 24, y: 55, width: 442, height: 50)
        let spinner = NSProgressIndicator(frame: NSRect(x: 24, y: 25, width: 440, height: 15))
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        window.contentView?.addSubview(status)
        window.contentView?.addSubview(spinner)
        window.makeKeyAndOrderFront(nil)
        background {
            let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
            guard args.count == 1, let file = args.first else {
                throw Failure(
                    message:
                        "Select one .ipa, .apk, or iOS .app in Finder, then choose Quick Actions → Install on Device."
                )
            }
            let url = URL(fileURLWithPath: file)
            self.filename = url.lastPathComponent
            guard fm.fileExists(atPath: url.path) else {
                throw Failure(message: "The selected file no longer exists.")
            }
            self.appPath = url.path
            switch url.pathExtension.lowercased() {
            case "apk": self.kind = "android"
            case "app": self.kind = try appKind(url.path)
            case "ipa":
                let temp = fm.temporaryDirectory.appendingPathComponent(
                    "InstallOnDevice-" + UUID().uuidString, isDirectory: true)
                try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                self.scratch = temp
                _ = try run("/usr/bin/ditto", ["-x", "-k", url.path, temp.path], timeout: 120)
                let payload = temp.appendingPathComponent("Payload")
                let apps = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "app" }
                guard apps.count == 1 else {
                    throw Failure(message: "Expected one application in the IPA’s Payload folder.")
                }
                self.appPath = apps[0].path
                self.kind = try appKind(self.appPath)
            default: throw Failure(message: "Choose an .ipa, .apk, or iOS .app file.")
            }
            DispatchQueue.main.async { self.discover() }
        }
    }

    func background(_ work: @escaping () throws -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do { try work() } catch {
                DispatchQueue.main.async {
                    self.finish("Couldn’t install app", error.localizedDescription)
                }
            }
        }
    }

    func discover() {
        status.stringValue = "Looking for devices for \(filename)…"
        background {
            let devices = try targets(self.kind)
            DispatchQueue.main.async { self.choose(devices) }
        }
    }

    func choose(_ devices: [Target]) {
        let alert = NSAlert()
        alert.messageText = devices.isEmpty ? "No devices available" : "Install \(filename)"
        alert.informativeText =
            devices.isEmpty
            ? "Connect and unlock your phone, or start an Android emulator. For Android, enable USB debugging and accept the connection prompt. For iOS, make sure the device is connected in Xcode."
            : "Choose a destination. Stopped iOS simulators will start automatically."
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 550, height: 28))
        if !devices.isEmpty {
            picker.addItems(withTitles: devices.map(\.label))
            alert.accessoryView = picker
            alert.addButton(withTitle: "Install")
        }
        alert.addButton(withTitle: "Refresh")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if !devices.isEmpty && response == .alertFirstButtonReturn {
            install(devices[picker.indexOfSelectedItem])
        } else if response.rawValue == (devices.isEmpty ? 1000 : 1001) {
            discover()
        } else {
            quit()
        }
    }

    func install(_ target: Target) {
        status.stringValue = "Installing \(filename) on \(target.label)…"
        background {
            if target.kind == "android" {
                _ = try run(
                    adbPath(), ["-s", target.id, "install", "-r", self.appPath], timeout: 300)
            } else if target.kind == "simulator" {
                if !target.booted {
                    _ = try run("/usr/bin/xcrun", ["simctl", "boot", target.id])
                    _ = try run(
                        "/usr/bin/xcrun", ["simctl", "bootstatus", target.id, "-b"], timeout: 180)
                }
                _ = try run("/usr/bin/open", ["-a", "Simulator"])
                _ = try run(
                    "/usr/bin/xcrun", ["simctl", "install", target.id, self.appPath], timeout: 300)
            } else {
                _ = try run(
                    "/usr/bin/xcrun",
                    [
                        "devicectl", "device", "install", "app", "--device", target.id,
                        self.appPath, "--timeout", "300",
                    ], timeout: 315)
            }
            DispatchQueue.main.async {
                self.finish("App installed", "\(self.filename) was installed on \(target.label).")
            }
        }
    }

    func finish(_ title: String, _ message: String) {
        window.orderOut(nil)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(message.suffix(5000))
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        quit()
    }

    func quit() {
        if let temp = scratch { try? fm.removeItem(at: temp) }
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--self-test") {
    let parsed = androidTargets(
        "List of devices attached\nphone123 device product:foo model:Pixel_9 transport_id:1\nbad unauthorized\nemulator-5554 device model:sdk_gphone64_arm64\noffline offline\n"
    )
    precondition(
        parsed.count == 2 && parsed[0].id == "phone123" && parsed[1].label.contains("emulator"))
    let tricky = "hello ' \" ; $(touch SHOULD_NOT_EXIST)\nworld"
    let echoed = try run("/usr/bin/printf", ["%s", tricky])
    precondition(echoed == tricky)
    print("PASS: authorized Android filtering, emulator labels, literal filename arguments")
} else {
    let app = NSApplication.shared
    let controller = Controller()
    app.delegate = controller
    app.run()
}
