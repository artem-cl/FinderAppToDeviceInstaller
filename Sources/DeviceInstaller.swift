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

struct OperationCancelled: Error {}

final class Cancellation {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
    func check() throws {
        if isCancelled { throw OperationCancelled() }
    }
}

func run(
    _ executable: String, _ arguments: [String], timeout: Double = 45,
    cancellation: Cancellation? = nil
) throws -> String {
    try cancellation?.check()
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
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while p.isRunning && ProcessInfo.processInfo.systemUptime < deadline
        && cancellation?.isCancelled != true
    { Thread.sleep(forTimeInterval: 0.1) }
    if p.isRunning {
        p.terminate()
        Thread.sleep(forTimeInterval: 0.3)
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        p.waitUntilExit()
        try cancellation?.check()
        throw Failure(message: "The operation timed out. Check the device connection and retry.")
    }
    p.waitUntilExit()
    try cancellation?.check()
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
    return try iosTargets(json(["devicectl", "list", "devices"], coreDevice: true))
}

func iosTargets(_ data: [String: Any]) throws -> [Target] {
    guard let result = data["result"] as? [String: Any],
        let devices = result["devices"] as? [[String: Any]]
    else {
        throw Failure(message: "Unexpected device discovery response. Refresh to try again.")
    }
    return devices.compactMap { d in
        let props = d["deviceProperties"] as? [String: Any] ?? [:]
        let hardware = d["hardwareProperties"] as? [String: Any] ?? [:]
        let connection = d["connectionProperties"] as? [String: Any] ?? [:]
        guard let id = d["identifier"] as? String,
            ["iOS", "iPadOS"].contains(hardware["platform"] as? String ?? ""),
            connection["pairingState"] as? String == "paired"
        else { return nil }
        let connected = connection["tunnelState"] as? String == "connected"
        return Target(
            id: id,
            label:
                "\(props["name"] as? String ?? "iPhone") · \(props["osVersionNumber"] as? String ?? "iOS") · \(connected ? "Connected" : "Not connected") · \(id.prefix(8))",
            kind: "ios", booted: true)
    }.sorted { $0.label < $1.label }
}

// A successful command can still contain cached, disconnected device information.
func iosReady(_ data: [String: Any], id: String) throws -> Bool {
    guard let result = data["result"] as? [String: Any],
        result["identifier"] as? String == id,
        let connection = result["connectionProperties"] as? [String: Any],
        let properties = result["deviceProperties"] as? [String: Any]
    else {
        throw Failure(message: "Unexpected device connection response.")
    }
    return connection["pairingState"] as? String == "paired"
        && connection["tunnelState"] as? String == "connected"
        && properties["ddiServicesAvailable"] as? Bool == true
}

func deviceDetails(_ id: String, timeout: Double, cancellation: Cancellation) throws -> [String:
    Any]
{
    let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? fm.removeItem(at: url) }
    _ = try run(
        "/usr/bin/xcrun",
        [
            "devicectl", "device", "info", "details", "--device", id,
            "--json-output", url.path, "--timeout", String(max(1, Int(timeout))),
        ],
        timeout: timeout, cancellation: cancellation)
    guard
        let result = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    else {
        throw Failure(message: "Invalid device connection JSON.")
    }
    return result
}

func waitForIOS(
    id: String, cancellation: Cancellation, timeout: Double = 45,
    now: () -> Double = { ProcessInfo.processInfo.systemUptime },
    sleep: (Double) -> Void = { Thread.sleep(forTimeInterval: $0) },
    probe: (Double) throws -> [String: Any]
) throws {
    let deadline = now() + timeout
    var lastError = "The device is not connected or its developer services are not ready."
    while now() < deadline {
        try cancellation.check()
        do {
            let ready = try iosReady(probe(min(8, deadline - now())), id: id)
            try cancellation.check()
            if ready && now() < deadline { return }
            lastError = "The device is not connected or its developer services are not ready."
        } catch is OperationCancelled {
            throw OperationCancelled()
        } catch {
            lastError = error.localizedDescription
        }
        let nextAttempt = min(deadline, now() + 1)
        while now() < nextAttempt {
            try cancellation.check()
            sleep(min(0.1, nextAttempt - now()))
        }
    }
    try cancellation.check()
    throw Failure(
        message:
            "Couldn’t connect within \(Int(timeout)) seconds. Unlock your iPhone, keep it nearby on the same Wi-Fi network, and check pairing and Developer Mode. You can also try USB.\n\nLast connection result: \(lastError)"
    )
}

// Installation is deliberately outside the retry loop: a failed install may have succeeded on-device.
func connectAndInstallIOS(connect: () throws -> Void, install: () throws -> Void) throws {
    try connect()
    try install()
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
    var connectionCancellation: Cancellation?
    var cancelButton: NSButton!
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
        let spinner = NSProgressIndicator(frame: NSRect(x: 24, y: 25, width: 330, height: 15))
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        window.contentView?.addSubview(status)
        window.contentView?.addSubview(spinner)
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelConnection))
        cancelButton.frame = NSRect(x: 370, y: 19, width: 96, height: 28)
        cancelButton.isHidden = true
        window.contentView?.addSubview(cancelButton)
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
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let devices = try targets(self.kind)
                DispatchQueue.main.async { self.choose(devices) }
            } catch {
                DispatchQueue.main.async { self.recover(error) }
            }
        }
    }

    func choose(_ devices: [Target]) {
        let alert = NSAlert()
        alert.messageText = devices.isEmpty ? "No devices available" : "Install \(filename)"
        alert.informativeText =
            devices.isEmpty
            ? "Connect and unlock your phone, or start an Android emulator. For Android, enable USB debugging and accept the connection prompt. For iOS, pair the device in Xcode once, enable Developer Mode, and use the same Wi-Fi network or USB."
            : "Choose a destination. Paired iPhones may be offline; we will try to connect for up to 45 seconds. Unlock your phone. Stopped iOS simulators will start automatically."
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

    @objc func cancelConnection() {
        connectionCancellation?.cancel()
        cancelButton.isEnabled = false
        status.stringValue = "Cancelling connection…"
    }

    func installIOS(_ target: Target) {
        let cancellation = Cancellation()
        connectionCancellation = cancellation
        cancelButton.isHidden = false
        cancelButton.isEnabled = true
        status.stringValue = "Connecting… Unlock your iPhone and keep it nearby."
        DispatchQueue.global(qos: .userInitiated).async {
            var installationStarted = false
            do {
                try connectAndInstallIOS(
                    connect: {
                        try waitForIOS(id: target.id, cancellation: cancellation) { timeout in
                            try deviceDetails(
                                target.id, timeout: timeout, cancellation: cancellation)
                        }
                    },
                    install: {
                        // Serialize the transition with the Cancel button on the main thread.
                        DispatchQueue.main.sync {
                            if !cancellation.isCancelled {
                                installationStarted = true
                                self.connectionCancellation = nil
                                self.cancelButton.isHidden = true
                                self.status.stringValue =
                                    "Installing \(self.filename) on \(target.label)…"
                            }
                        }
                        try cancellation.check()
                        _ = try run(
                            "/usr/bin/xcrun",
                            [
                                "devicectl", "device", "install", "app",
                                "--device", target.id, self.appPath, "--timeout", "300",
                            ], timeout: 315)
                    })
                DispatchQueue.main.async {
                    self.finish(
                        "App installed", "\(self.filename) was installed on \(target.label).")
                }
            } catch {
                let failedDuringInstall = installationStarted
                DispatchQueue.main.async {
                    self.connectionCancellation = nil
                    self.cancelButton.isHidden = true
                    if error is OperationCancelled {
                        self.discover()
                    } else {
                        self.recover(
                            error, target: failedDuringInstall ? nil : target,
                            installationStarted: failedDuringInstall)
                    }
                }
            }
        }
    }

    func recover(_ error: Error, target: Target? = nil, installationStarted: Bool = false) {
        let alert = NSAlert()
        alert.messageText =
            installationStarted
            ? "Installation did not complete normally" : "Couldn’t connect to device"
        alert.informativeText =
            String(error.localizedDescription.suffix(4000))
            + (installationStarted
                ? "\n\nCheck the app on your phone before installing again. The installation was not automatically retried."
                : "")
        if target != nil { alert.addButton(withTitle: "Retry") }
        alert.addButton(withTitle: "Refresh")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if let target, response == .alertFirstButtonReturn {
            installIOS(target)
        } else if response.rawValue == (target == nil ? 1000 : 1001) {
            discover()
        } else {
            quit()
        }
    }

    func install(_ target: Target) {
        if target.kind == "ios" {
            installIOS(target)
            return
        }
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

func testIOSConnection() throws {
    guard let index = CommandLine.arguments.firstIndex(of: "--fixtures"),
        index + 1 < CommandLine.arguments.count
    else {
        throw Failure(message: "Self-tests require --fixtures <directory>.")
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    func fixture(_ name: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent(name + ".json"))) as! [String: Any]
    }
    let discovery = try fixture("ios-discovery")
    let ready = try fixture("ios-connected")
    let devices = try iosTargets(discovery)
    precondition(devices.count == 1 && devices[0].label.contains("Not connected"))
    let result = discovery["result"] as! [String: Any]
    let device = (result["devices"] as! [[String: Any]])[0]
    var unpaired = device
    unpaired["connectionProperties"] = ["pairingState": "unpaired", "tunnelState": "connected"]
    var mac = device
    mac["hardwareProperties"] = ["platform": "macOS"]
    let filtered = try iosTargets(["result": ["devices": [device, unpaired, mac]]])
    precondition(filtered.count == 1)
    let connected = try iosTargets(["result": ["devices": [ready["result"]!]]])
    precondition(connected[0].label.contains("Connected"))
    do {
        _ = try iosTargets([:])
        preconditionFailure("Malformed discovery must throw")
    } catch is Failure {}
    let empty = try iosTargets(["result": ["devices": [[String: Any]]()]])
    precondition(empty.isEmpty)
    let cached: [String: Any] = ["result": device]
    var locked = ready["result"] as! [String: Any]
    locked["deviceProperties"] = ["ddiServicesAvailable": false]
    precondition(tryReady(cached) == false && tryReady(["result": locked]) == false)
    do {
        _ = try iosReady(ready, id: "different-phone")
        preconditionFailure("Do not accept another phone")
    } catch is Failure {}

    var clock = 0.0
    var probes = 0
    var installs = 0
    let token = Cancellation()
    try connectAndInstallIOS(
        connect: {
            try waitForIOS(
                id: "test-iphone", cancellation: token,
                now: { clock }, sleep: { clock += $0 },
                probe: { budget in
                    precondition(budget > 0 && budget <= 8)
                    probes += 1
                    switch probes {
                    case 1: throw Failure(message: "Device disappeared")
                    case 2: return [:]  // malformed response
                    case 3: return cached  // cached details are not readiness
                    case 4: return ["result": locked]
                    default: return ready
                    }
                })
        }, install: { installs += 1 })
    precondition(probes == 5 && installs == 1)

    clock = 0
    installs = 0
    do {
        try connectAndInstallIOS(
            connect: {
                try waitForIOS(
                    id: "test-iphone", cancellation: token, timeout: 3,
                    now: { clock }, sleep: { clock += $0 },
                    probe: { budget in
                        clock += budget
                        return cached
                    })
            }, install: { installs += 1 })
        preconditionFailure("Offline phone must time out")
    } catch let error as Failure { precondition(error.message.contains("3 seconds")) }
    precondition(clock == 3 && installs == 0)
    // A reply arriving at the deadline cannot start installation.
    clock = 0
    do {
        try waitForIOS(
            id: "test-iphone", cancellation: token, timeout: 1,
            now: { clock }, sleep: { clock += $0 },
            probe: { budget in
                clock += budget
                return ready
            })
        preconditionFailure("Late readiness must time out")
    } catch is Failure {}

    for cancelDuringProbe in [false, true] {
        let cancelled = Cancellation()
        if !cancelDuringProbe { cancelled.cancel() }
        var called = false
        do {
            try connectAndInstallIOS(
                connect: {
                    try waitForIOS(
                        id: "test-iphone", cancellation: cancelled,
                        probe: { _ in
                            called = true
                            cancelled.cancel()
                            return ready
                        })
                }, install: { preconditionFailure("Cancelled operation must not install") })
            preconditionFailure("Cancellation must propagate")
        } catch is OperationCancelled {}
        precondition(called == cancelDuringProbe)
    }
    // Cancellation interrupts the retry delay, too.
    clock = 0
    let cancelled = Cancellation()
    do {
        try waitForIOS(
            id: "test-iphone", cancellation: cancelled,
            now: { clock },
            sleep: {
                clock += $0
                cancelled.cancel()
            }, probe: { _ in cached })
        preconditionFailure("Cancellation during delay must propagate")
    } catch is OperationCancelled {}
    precondition(clock <= 0.1)

    // Explicit Retry gets a fresh deadline; installation errors are never retried.
    clock = 100
    installs = 0
    do {
        try connectAndInstallIOS(
            connect: {
                try waitForIOS(
                    id: "test-iphone", cancellation: Cancellation(),
                    now: { clock }, sleep: { clock += $0 }, probe: { _ in ready })
            },
            install: {
                installs += 1
                throw Failure(message: "Installation timed out; outcome unknown")
            })
        preconditionFailure("Installation errors must propagate")
    } catch let error as Failure { precondition(error.message.contains("outcome unknown")) }
    precondition(installs == 1)
    let processCancellation = Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { processCancellation.cancel() }
    let start = ProcessInfo.processInfo.systemUptime
    do {
        _ = try run("/bin/sleep", ["10"], cancellation: processCancellation)
        preconditionFailure("Running process must be cancelled")
    } catch is OperationCancelled {}
    precondition(ProcessInfo.processInfo.systemUptime - start < 5)
    print(
        "PASS: iOS discovery, delayed readiness, errors, deadline, cancellation, retry, single installation"
    )
}

func tryReady(_ data: [String: Any]) -> Bool {
    (try? iosReady(data, id: "test-iphone")) == true
}

if CommandLine.arguments.contains("--self-test") {
    try testIOSConnection()
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
