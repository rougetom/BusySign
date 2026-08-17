import AppKit
import CoreAudio
import Foundation

func env(_ key: String) -> String? {
    let value = ProcessInfo.processInfo.environment[key]
    if let value, !value.isEmpty { return value }
    return nil
}

func loadDotEnv() {
    let path = NSHomeDirectory() + "/.busysign.env"
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    for rawLine in contents.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        var value = parts[1].trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        if ProcessInfo.processInfo.environment[key] == nil {
            setenv(key, value, 0)
        }
    }
}

func audioDeviceName(_ deviceID: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var cfName: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfName)
    guard status == noErr, let cfName else { return "device-\(deviceID)" }
    return cfName.takeUnretainedValue() as String
}

func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
        return 0
    }
    let raw = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else {
        return 0
    }
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    var channels = 0
    for buffer in buffers {
        channels += Int(buffer.mNumberChannels)
    }
    return channels
}

func isDeviceRunningSomewhere(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
    return status == noErr && running != 0
}

func allAudioDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size
    ) == noErr else {
        return []
    }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &devices
    ) == noErr else {
        return []
    }
    return devices
}

struct MicProbe {
    let busy: Bool
    let activeNames: [String]
}

func probeMicrophone() -> MicProbe {
    var active: [String] = []
    for deviceID in allAudioDeviceIDs() {
        guard inputChannelCount(deviceID) > 0 else { continue }
        if isDeviceRunningSomewhere(deviceID) {
            active.append(audioDeviceName(deviceID))
        }
    }
    return MicProbe(busy: !active.isEmpty, activeNames: active)
}

func statusDotImage(busy: Bool) -> NSImage {
    let size: CGFloat = 16
    return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let inset = rect.insetBy(dx: 3, dy: 3)
        (busy ? NSColor.systemRed : NSColor.systemGreen).setFill()
        NSBezierPath(ovalIn: inset).fill()
        NSColor.black.withAlphaComponent(0.45).setStroke()
        let ring = NSBezierPath(ovalIn: inset)
        ring.lineWidth = 1
        ring.stroke()
        return true
    }
}

enum SignMode: Equatable {
    case automatic
    case manual(busy: Bool)
}

final class BusySignApp: NSObject, NSApplicationDelegate {
    private let url: URL
    private let token: String
    private let debug: Bool
    private let heartbeat: TimeInterval = 10

    private var mode: SignMode = .automatic
    private var micBusy = false
    private var lastPosted: Bool?
    private var lastPostAt = Date.distantPast
    private var lastPostOK = true

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var autoItem: NSMenuItem!
    private var busyItem: NSMenuItem!
    private var freeItem: NSMenuItem!
    private var timer: Timer?

    var reportedBusy: Bool {
        switch mode {
        case .automatic: return micBusy
        case .manual(let busy): return busy
        }
    }

    init(url: URL, token: String, debug: Bool) {
        self.url = url
        self.token = token
        self.debug = debug
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = statusDotImage(busy: false)
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Busy Sign"
        }

        autoItem = NSMenuItem(title: "Follow microphone", action: #selector(useAutomatic), keyEquivalent: "")
        busyItem = NSMenuItem(title: "Busy", action: #selector(useManualBusy), keyEquivalent: "")
        freeItem = NSMenuItem(title: "Free", action: #selector(useManualFree), keyEquivalent: "")
        for item in [autoItem, busyItem, freeItem] {
            item?.target = self
        }
        menu.addItem(autoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(busyItem)
        menu.addItem(freeItem)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit Busy Sign", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
            return
        }
        toggleManual()
    }

    private func showMenu() {
        refreshMenuChecks()
        guard let button = statusItem.button else { return }
        let point = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    @objc private func toggleManual() {
        mode = .manual(busy: !reportedBusy)
        publish(force: true)
        refreshChrome()
    }

    @objc private func useAutomatic() {
        mode = .automatic
        publish(force: true)
        refreshChrome()
    }

    @objc private func useManualBusy() {
        mode = .manual(busy: true)
        publish(force: true)
        refreshChrome()
    }

    @objc private func useManualFree() {
        mode = .manual(busy: false)
        publish(force: true)
        refreshChrome()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func tick() {
        let probe = probeMicrophone()
        micBusy = probe.busy
        if debug {
            let names = probe.activeNames.isEmpty ? "none" : probe.activeNames.joined(separator: ", ")
            fputs("busysign: report=\(reportedBusy) mic=\(micBusy) mode=\(mode) devices=[\(names)]\n", stderr)
        }
        let dueHeartbeat = Date().timeIntervalSince(lastPostAt) >= heartbeat
        let changed = lastPosted != reportedBusy
        if changed || dueHeartbeat {
            publish(force: false)
        }
        refreshChrome()
    }

    private func publish(force: Bool) {
        let busy = reportedBusy
        if !force, lastPosted == busy, Date().timeIntervalSince(lastPostAt) < heartbeat {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let body: [String: Any] = [
            "busy": busy,
            "timezone": TimeZone.current.identifier,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let http = response as? HTTPURLResponse
            let ok = error == nil && http.map { (200...299).contains($0.statusCode) } == true
            if !ok {
                let code = http.map { String($0.statusCode) } ?? "network"
                fputs("busysign: POST failed (\(code))\n", stderr)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastPostOK = ok
                if ok {
                    self.lastPosted = busy
                    self.lastPostAt = Date()
                } else {
                    self.lastPostAt = Date().addingTimeInterval(-self.heartbeat + 2)
                }
                self.refreshChrome()
            }
        }.resume()
    }

    private func refreshChrome() {
        statusItem.button?.image = statusDotImage(busy: reportedBusy)
        let state = reportedBusy ? "Busy" : "Free"
        let source: String
        switch mode {
        case .automatic:
            source = "microphone"
        case .manual:
            source = micBusy ? "manual · mic on" : "manual · mic off"
        }
        let reach = lastPostOK ? "" : " · sign unreachable"
        statusItem.button?.toolTip = "\(state) · \(source)\(reach)\nClick to toggle · Right-click for automatic"
        refreshMenuChecks()
    }

    private func refreshMenuChecks() {
        autoItem.state = mode == .automatic ? .on : .off
        switch mode {
        case .automatic:
            busyItem.state = .off
            freeItem.state = .off
        case .manual(let busy):
            busyItem.state = busy ? .on : .off
            freeItem.state = busy ? .off : .on
        }
    }
}

loadDotEnv()

guard let urlString = env("BUSYSIGN_URL"), let url = URL(string: urlString) else {
    fputs("busysign: set BUSYSIGN_URL to https://<worker>/status\n", stderr)
    exit(1)
}
guard let token = env("BUSYSIGN_TOKEN") else {
    fputs("busysign: set BUSYSIGN_TOKEN\n", stderr)
    exit(1)
}

fputs("busysign: menu bar reporter → \(urlString) tz=\(TimeZone.current.identifier)\n", stderr)

let app = NSApplication.shared
let controller = BusySignApp(url: url, token: token, debug: env("BUSYSIGN_DEBUG") == "1")
app.setActivationPolicy(.accessory)
app.delegate = controller
withExtendedLifetime(controller) {
    app.run()
}
