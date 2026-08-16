import CoreAudio
import Foundation

func env(_ key: String) -> String? {
    let value = ProcessInfo.processInfo.environment[key]
    if let value, !value.isEmpty { return value }
    return nil
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

func postStatus(url: URL, token: String, busy: Bool) -> Bool {
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

    let semaphore = DispatchSemaphore(value: 0)
    var ok = false
    let task = URLSession.shared.dataTask(with: request) { _, response, error in
        defer { semaphore.signal() }
        if error != nil { return }
        guard let http = response as? HTTPURLResponse else { return }
        ok = (200...299).contains(http.statusCode)
        if !ok {
            FileHandle.standardError.write(
                Data("busysign: HTTP \(http.statusCode)\n".utf8)
            )
        }
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 15)
    return ok
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

loadDotEnv()

guard let urlString = env("BUSYSIGN_URL"), let url = URL(string: urlString) else {
    fputs("busysign: set BUSYSIGN_URL to https://<worker>/status\n", stderr)
    exit(1)
}
guard let token = env("BUSYSIGN_TOKEN") else {
    fputs("busysign: set BUSYSIGN_TOKEN\n", stderr)
    exit(1)
}

let debug = env("BUSYSIGN_DEBUG") == "1"
var lastBusy: Bool?
var lastPost = Date.distantPast
let heartbeat: TimeInterval = 10

fputs("busysign: reporting to \(urlString) tz=\(TimeZone.current.identifier)\n", stderr)

while true {
    let probe = probeMicrophone()
    let now = Date()
    let changed = lastBusy != probe.busy
    let dueHeartbeat = now.timeIntervalSince(lastPost) >= heartbeat
    if debug, changed || dueHeartbeat {
        let names = probe.activeNames.isEmpty ? "none" : probe.activeNames.joined(separator: ", ")
        fputs("busysign: busy=\(probe.busy) devices=[\(names)]\n", stderr)
    }
    if changed || dueHeartbeat {
        if postStatus(url: url, token: token, busy: probe.busy) {
            lastBusy = probe.busy
            lastPost = now
        } else {
            lastPost = now.addingTimeInterval(-heartbeat + 2)
        }
    }
    Thread.sleep(forTimeInterval: 1)
}
