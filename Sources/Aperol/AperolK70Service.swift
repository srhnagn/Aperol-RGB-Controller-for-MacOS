// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import AppKit
import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid
import SwiftUI

/// Represents a customizable, user-editable color preset.
public struct ColorPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(id: UUID = UUID(), name: String, red: Double, green: Double, blue: Double) {
        self.id = id
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    public var hexString: String {
        let r = Int((red * 255.0).rounded())
        let g = Int((green * 255.0).rounded())
        let b = Int((blue * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Represents the color saved to a specific hardware profile slot.
public struct HardwareSlotColor: Codable, Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var color: Color {
        Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Thread-safe receiver for 64-byte NXP HID Input reports on collection 0xFFC2:0x0003.
private final class NxpInputReceiver: @unchecked Sendable {
    private let condition = NSCondition()
    private var queue: [[UInt8]] = []
    public var reportBuffer = [UInt8](repeating: 0, count: 64)
    private var runLoopThread: Thread?
    private var receiverRunLoop: CFRunLoop?

    public init() {}

    public func attach(device: IOHIDDevice) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDReportCallback = { ctx, result, sender, type, reportID, report, reportLength in
            guard let ctx, result == kIOReturnSuccess, reportLength > 0 else { return }
            let receiver = Unmanaged<NxpInputReceiver>.fromOpaque(ctx).takeUnretainedValue()
            var bytes = [UInt8](repeating: 0, count: 64)
            let copyLen = min(Int(reportLength), 64)
            for i in 0..<copyLen {
                bytes[i] = report[i]
            }
            receiver.enqueue(bytes)
        }

        // Unschedule from main run loop so callbacks fire on our dedicated background run loop
        // even while hardwareQueue is waiting for command responses.
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, &reportBuffer, 64, callback, context)

        let readyLock = NSCondition()
        var started = false
        let thread = Thread { [weak self] in
            guard let self else { return }
            let rl = CFRunLoopGetCurrent()
            readyLock.lock()
            self.receiverRunLoop = rl
            if let rl {
                IOHIDDeviceScheduleWithRunLoop(device, rl, CFRunLoopMode.defaultMode.rawValue)
            }
            started = true
            readyLock.signal()
            readyLock.unlock()

            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 1.0, false)
            }
        }
        thread.name = "com.aperol.nxp-hid-input"
        thread.qualityOfService = QualityOfService.userInteractive
        readyLock.lock()
        thread.start()
        while !started {
            readyLock.wait()
        }
        readyLock.unlock()
        self.runLoopThread = thread
    }

    public func detach(device: IOHIDDevice) {
        if let rl = receiverRunLoop {
            IOHIDDeviceUnscheduleFromRunLoop(device, rl, CFRunLoopMode.defaultMode.rawValue)
        }
        runLoopThread?.cancel()
        if let rl = receiverRunLoop {
            CFRunLoopStop(rl)
        }
        runLoopThread = nil
        receiverRunLoop = nil
    }

    public func clearQueue() {
        condition.lock()
        queue.removeAll(keepingCapacity: true)
        condition.unlock()
    }

    public func enqueue(_ packet: [UInt8]) {
        condition.lock()
        queue.append(packet)
        if queue.count > 64 {
            queue.removeFirst(queue.count - 64)
        }
        condition.broadcast()
        condition.unlock()
    }

    public func waitForMatchingResponse(request: [UInt8], timeoutMs: Int) -> [UInt8]? {
        // Compute non-zero prefix length of request (matching NxpHidIoBase::getReport)
        var prefixLen = request.count
        while prefixLen > 0 && request[prefixLen - 1] == 0 {
            prefixLen -= 1
        }
        prefixLen = max(prefixLen, 2)
        let startIdx = (request.first == 0xFF) ? 1 : 0

        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        condition.lock()
        defer { condition.unlock() }

        while true {
            while !queue.isEmpty {
                let pkt = queue.removeFirst()
                var matches = true
                if startIdx < prefixLen {
                    for i in startIdx..<prefixLen {
                        if pkt[i] != request[i] {
                            matches = false
                            break
                        }
                    }
                }
                if matches {
                    return pkt
                }
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                return nil
            }
            if !condition.wait(until: Date().addingTimeInterval(min(remaining, 0.025))) && Date() >= deadline {
                return nil
            }
        }
    }
}

/// Native IOKit USB HID controller for Corsair K70 MK.2 RGB keyboard.
/// Fully implements the reverse-engineered iCUE `NxpRegularHardwareProfileStorageFeature` &
/// `NxpFileOperationsFeature` protocol over `0xFFC2:0x0004` (OUT) and `0xFFC2:0x0003` (IN):
/// - `clearProfile(slot)` + `commitProfileInfo(slot)` + `setCurrentProfile(slot)`
/// - All 7 onboard NXP filesystem files per slot:
///   `"PROFILE.DAT"`, `"PROFILE.I"`, `"PROFILE.MAP"`, `"lght_00.d"`, `"lght_00.k"`, `"lght_00.r"`, `"lghtcnt.cnt"`
/// - `commitProfileChanges` (`07 17 0E 00`) with full `getLastOperationStatus` (`0E 17 0D 00`) polling.
@MainActor
public final class AperolK70Service: ObservableObject {
    public static let shared = AperolK70Service()

    public static let corsairVendorID: Int = 0x1B1C
    public static let supportedProductIDs: Set<Int> = [
        0x1B49, // K70 RGB MK.2
        0x1B6B, // K70 RGB MK.2 Low Profile
        0x1B55, // K70 RGB MK.2 SE / LP Variant
        0x1B38, // K70 LUX RGB
        0x1B13, // K70 RGB (Legacy)
        0x1B33, // K95 Platinum
        0x1B36  // K68 RGB
    ]

    public static let maxOnboardSlots: Int = 3

    private static let slotUUIDs: [[UInt8]] = [
        [0xC0, 0x85, 0xA1, 0x01, 0x4A, 0x70, 0x4B, 0x70, 0x80, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01],
        [0xC0, 0x85, 0xA1, 0x02, 0x4A, 0x70, 0x4B, 0x70, 0x80, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02],
        [0xC0, 0x85, 0xA1, 0x03, 0x4A, 0x70, 0x4B, 0x70, 0x80, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03]
    ]

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var deviceName: String = "Corsair K70 RGB MK.2"
    @Published public var selectedColor: Color = Color(red: 242.0 / 255.0, green: 101.0 / 255.0, blue: 34.0 / 255.0)
    @Published public var brightness: Double = 1.0
    @Published public var statusMessage: String?
    @Published public var isWriting: Bool = false
    @Published public var selectedSlot: Int = 1 // Target slot: 1, 2, or 3
    @Published public var savedSlots: Set<Int> = [1, 2, 3]
    @Published public var slotProfiles: [Int: HardwareSlotColor] = [:]
    @Published public var presets: [ColorPreset] = []
    @Published public var hoveredPresetId: UUID? = nil
    @Published public var editingPresetId: UUID? = nil
    @Published public private(set) var isStreaming: Bool = false
    @Published public var copiedHex: Bool = false
    public var hasUserInteractedWithColor: Bool = false

    // MARK: - Top Buttons & WinLock Controls
    @Published public var isWinLockDisabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isWinLockDisabled, forKey: "AperolWinLockDisabled_v1")
            sendWinLockDisabledReport(isWinLockDisabled)
        }
    }
    @Published public var winLockLockedColor: Color = Color(red: 242.0 / 255.0, green: 107.0 / 255.0, blue: 30.0 / 255.0) {
        didSet {
            UserDefaults.standard.set(Self.hexFromColor(winLockLockedColor), forKey: "AperolWinLockLockedHex_v1")
            if hasUserInteractedWithColor { applyLiveColor(selectedColor) }
        }
    }
    @Published public var winLockUnlockedColor: Color = Color(red: 242.0 / 255.0, green: 107.0 / 255.0, blue: 30.0 / 255.0) {
        didSet {
            UserDefaults.standard.set(Self.hexFromColor(winLockUnlockedColor), forKey: "AperolWinLockUnlockedHex_v1")
            if hasUserInteractedWithColor { applyLiveColor(selectedColor) }
        }
    }
    @Published public var profileButtonColor: Color = Color(red: 242.0 / 255.0, green: 107.0 / 255.0, blue: 30.0 / 255.0) {
        didSet {
            UserDefaults.standard.set(Self.hexFromColor(profileButtonColor), forKey: "AperolProfileButtonHex_v1")
            if hasUserInteractedWithColor { applyLiveColor(selectedColor) }
        }
    }
    @Published public var brightnessButtonColor: Color = Color(red: 242.0 / 255.0, green: 107.0 / 255.0, blue: 30.0 / 255.0) {
        didSet {
            UserDefaults.standard.set(Self.hexFromColor(brightnessButtonColor), forKey: "AperolBrightnessButtonHex_v1")
            if hasUserInteractedWithColor { applyLiveColor(selectedColor) }
        }
    }

    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice? // 0xFFC2:0x0004 (OUT)
    private var inputDevice: IOHIDDevice?     // 0xFFC2:0x0003 (IN)
    private let inputReceiver = NxpInputReceiver()
    private let hardwareQueue = DispatchQueue(label: "com.aperol.k70.hardware-flash", qos: .userInitiated)
    private var isInitialized: Bool = false
    private var lastStreamTime: Date = Date.distantPast
    private var zoneWorkItem: DispatchWorkItem?

    private init() {
        loadPresets()
        loadSavedSlots()
        loadSlotProfiles()
        loadTopButtonSettings()
        setupHIDManager()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseToHardwareMode() }
        }
    }

    // MARK: - Presets Storage

    private func loadPresets() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "AperolColorPresets_v3"),
           let decoded = try? JSONDecoder().decode([ColorPreset].self, from: data),
           !decoded.isEmpty {
            self.presets = decoded
        } else {
            self.presets = [
                ColorPreset(name: "Aperol Spritz", red: 242.0 / 255.0, green: 101.0 / 255.0, blue: 34.0 / 255.0),
                ColorPreset(name: "Pure Carmine", red: 1.0, green: 0.10, blue: 0.10),
                ColorPreset(name: "Night Vision", red: 70.0 / 255.0, green: 1.0, blue: 0.0),
                ColorPreset(name: "Ice Glacier", red: 154.0 / 255.0, green: 220.0 / 255.0, blue: 231.0 / 255.0),
                ColorPreset(name: "Amber Warmth", red: 1.0, green: 150.0 / 255.0, blue: 0.0),
                ColorPreset(name: "Deep Cyan", red: 0.0, green: 200.0 / 255.0, blue: 1.0),
                ColorPreset(name: "Obsidian Dim", red: 40.0 / 255.0, green: 40.0 / 255.0, blue: 45.0 / 255.0),
                ColorPreset(name: "Stealth (Off)", red: 0.0, green: 0.0, blue: 0.0)
            ]
            savePresets()
        }
    }

    public func savePresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: "AperolColorPresets_v3")
        }
    }

    public func addCurrentColorAsPreset(named: String? = nil) {
        let nsColor = NSColor(selectedColor).usingColorSpace(.sRGB) ?? NSColor(selectedColor)
        let r = Double(nsColor.redComponent)
        let g = Double(nsColor.greenComponent)
        let b = Double(nsColor.blueComponent)
        let name = named ?? "Custom \(currentHexColor)"
        let newPreset = ColorPreset(name: name, red: r, green: g, blue: b)
        presets.append(newPreset)
        savePresets()
        statusMessage = "Added Preset: \(name)"
    }

    public func deletePreset(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        savePresets()
    }

    public func renamePreset(id: UUID, name: String) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].name = name
        savePresets()
    }

    public func setPresetColor(id: UUID, color: Color) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        presets[i].red = Double(ns.redComponent)
        presets[i].green = Double(ns.greenComponent)
        presets[i].blue = Double(ns.blueComponent)
        savePresets()
    }

    public func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }

    public func restoreDefaultPresets() {
        UserDefaults.standard.removeObject(forKey: "AperolColorPresets_v3")
        loadPresets()
    }

    private func loadSavedSlots() {
        if let array = UserDefaults.standard.array(forKey: "AperolSavedSlots_v2") as? [Int] {
            self.savedSlots = Set(array)
        } else {
            self.savedSlots = [1, 2, 3]
        }
    }

    private func markSlotSaved(_ slot: Int) {
        savedSlots.insert(slot)
        UserDefaults.standard.set(Array(savedSlots), forKey: "AperolSavedSlots_v2")
    }

    private func loadSlotProfiles() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "AperolSlotProfiles_v2"),
           let decoded = try? JSONDecoder().decode([Int: HardwareSlotColor].self, from: data),
           !decoded.isEmpty {
            self.slotProfiles = decoded
        } else {
            self.slotProfiles = [
                1: HardwareSlotColor(r: 255, g: 0, b: 0),
                2: HardwareSlotColor(r: 70, g: 255, b: 0),
                3: HardwareSlotColor(r: 154, g: 220, b: 231)
            ]
            saveSlotProfiles()
        }
    }

    public func saveSlotProfiles() {
        if let encoded = try? JSONEncoder().encode(slotProfiles) {
            UserDefaults.standard.set(encoded, forKey: "AperolSlotProfiles_v2")
        }
    }

    public func resetFactoryProfiles() {
        self.slotProfiles = [
            1: HardwareSlotColor(r: 255, g: 0, b: 0),
            2: HardwareSlotColor(r: 70, g: 255, b: 0),
            3: HardwareSlotColor(r: 154, g: 220, b: 231)
        ]
        saveSlotProfiles()
        if let current = slotProfiles[selectedSlot] {
            selectedColor = current.color
        }
        flashAllProfilesToHardware(targetSlot: selectedSlot)
    }

    // MARK: - Top Buttons & WinLock Settings Persistence

    private func loadTopButtonSettings() {
        let defaults = UserDefaults.standard
        self.isWinLockDisabled = defaults.bool(forKey: "AperolWinLockDisabled_v1")
        if let hex = defaults.string(forKey: "AperolWinLockLockedHex_v1"), let c = Self.colorFromHex(hex) {
            self.winLockLockedColor = c
        }
        if let hex = defaults.string(forKey: "AperolWinLockUnlockedHex_v1"), let c = Self.colorFromHex(hex) {
            self.winLockUnlockedColor = c
        }
        if let hex = defaults.string(forKey: "AperolProfileButtonHex_v1"), let c = Self.colorFromHex(hex) {
            self.profileButtonColor = c
        }
        if let hex = defaults.string(forKey: "AperolBrightnessButtonHex_v1"), let c = Self.colorFromHex(hex) {
            self.brightnessButtonColor = c
        }
    }

    public func sendWinLockDisabledReport(_ disabled: Bool) {
        guard let device = connectedDevice else { return }
        var pkt = [UInt8](repeating: 0, count: 64)
        pkt[0] = 0x07
        pkt[1] = 0x48
        pkt[2] = disabled ? 0x00 : 0x80
        pkt[3] = 0x00
        sendPacket(pkt, to: device)
        statusMessage = disabled ? "WinLock Key Action Disabled" : "WinLock Key Action Enabled"
    }

    public func syncAllTopButtonsToSelectedColor() {
        winLockLockedColor = selectedColor
        winLockUnlockedColor = selectedColor
        profileButtonColor = selectedColor
        brightnessButtonColor = selectedColor
        applyLiveColor(selectedColor)
        statusMessage = "Synced all top button colors with active profile"
    }

    public func matchWinLockUnlockedToLocked() {
        winLockUnlockedColor = winLockLockedColor
        applyLiveColor(selectedColor)
        statusMessage = "WinLock unlocked color matched to locked color"
    }

    public static func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int((nsColor.redComponent * 255.0).rounded())
        let g = Int((nsColor.greenComponent * 255.0).rounded())
        let b = Int((nsColor.blueComponent * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    public static func colorFromHex(_ hex: String) -> Color? {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        guard cleanHex.count == 6, let rgb = UInt32(cleanHex, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - HID Management (Dual Collection: 0xFFC2:0x0004 OUT + 0xFFC2:0x0003 IN)

    private func isOutLightingInterface(_ device: IOHIDDevice) -> Bool {
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let maxOut = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        let maxFeat = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
        if usagePage == 0xFFC2 {
            return usage == 0x0004 || (usage == 0x0002 && (maxOut >= 64 || maxFeat >= 64))
        }
        return false
    }

    private func isInResponseInterface(_ device: IOHIDDevice) -> Bool {
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let maxIn = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        return usagePage == 0xFFC2 && usage == 0x0003 && maxIn >= 64
    }

    private func setupHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        let matchingCriteria: [String: Any] = [
            kIOHIDVendorIDKey: Self.corsairVendorID
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingCriteria as CFDictionary)

        let matchingCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context else { return }
            let service = Unmanaged<AperolK70Service>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                service.deviceAttached(device)
            }
        }

        let removalCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context else { return }
            let service = Unmanaged<AperolK70Service>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                service.deviceDetached(device)
            }
        }

        let unsafeContext = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matchingCallback, unsafeContext)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, unsafeContext)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openStatus == kIOReturnSuccess {
            if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                for dev in devices {
                    deviceAttached(dev)
                }
            }
        }
    }

    private func deviceAttached(_ device: IOHIDDevice) {
        guard let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
              Self.supportedProductIDs.contains(productID) else {
            return
        }

        if isInResponseInterface(device) {
            if self.inputDevice != device {
                self.inputDevice = device
                self.inputReceiver.attach(device: device)
            }
            return
        }

        guard isOutLightingInterface(device) else { return }

        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            deviceName = name
        }

        self.connectedDevice = device
        self.isConnected = true
        self.statusMessage = "Connected: \(deviceName)"
    }

    private func deviceDetached(_ device: IOHIDDevice) {
        if inputDevice == device {
            inputReceiver.detach(device: device)
            inputDevice = nil
        }
        if connectedDevice == device {
            connectedDevice = nil
            isConnected = false
            isInitialized = false
            statusMessage = "Device Disconnected"
        }
    }

    // MARK: - Low-Level NXP HID Report Transport (Matches NxpKeyboardHidIo & NxpHidIoBase)

    @discardableResult
    nonisolated private static func sendOutReport(
        _ bytes: [UInt8],
        to device: IOHIDDevice,
        delayMs: UInt32 = 3
    ) -> IOReturn {
        var buf = [UInt8](repeating: 0, count: 64)
        for i in 0..<min(bytes.count, 64) {
            buf[i] = bytes[i]
        }
        var kr: IOReturn = kIOReturnError
        for attempt in 0..<3 {
            // In NxpKeyboardHidIo (protocolVersion 4/5), reportId is 0 and ReportType is Output (1)
            kr = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buf, 64)
            if kr == kIOReturnSuccess {
                break
            }
            // Fallback to Feature report only on legacy protocolVersion 1 devices
            kr = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, buf, 64)
            if kr == kIOReturnSuccess {
                break
            }
            if attempt < 2 {
                usleep(10_000)
            }
        }
        if delayMs > 0 {
            usleep(delayMs * 1000)
        }
        return kr
    }

    nonisolated private static func sendCommand(
        _ cmd: [UInt8],
        to outDevice: IOHIDDevice,
        receiver: NxpInputReceiver,
        hasInputDevice: Bool,
        delayMs: UInt32 = 2
    ) -> [UInt8]? {
        if hasInputDevice {
            for _ in 0..<3 {
                receiver.clearQueue()
                let kr = sendOutReport(cmd, to: outDevice, delayMs: 0)
                guard kr == kIOReturnSuccess else {
                    usleep(10_000)
                    continue
                }
                if let resp = receiver.waitForMatchingResponse(request: cmd, timeoutMs: 250) {
                    if delayMs > 0 {
                        usleep(delayMs * 1000)
                    }
                    return resp
                }
            }
            return nil
        } else {
            // Fallback for legacy single-interface Feature-report keyboards
            guard sendOutReport(cmd, to: outDevice, delayMs: 3) == kIOReturnSuccess else { return nil }
            var resp = [UInt8](repeating: 0, count: 64)
            var len: CFIndex = 64
            let kr = IOHIDDeviceGetReport(outDevice, kIOHIDReportTypeFeature, 0, &resp, &len)
            return kr == kIOReturnSuccess ? resp : nil
        }
    }

    nonisolated private static func getLastOperationStatus(
        outDevice: IOHIDDevice,
        receiver: NxpInputReceiver,
        hasInputDevice: Bool
    ) -> UInt8 {
        guard let resp = sendCommand(
            [0x0E, 0x17, 0x0D, 0x00],
            to: outDevice,
            receiver: receiver,
            hasInputDevice: hasInputDevice,
            delayMs: 2
        ) else {
            return 0xFF
        }
        return resp[4]
    }

    nonisolated private static func waitOp(
        outDevice: IOHIDDevice,
        receiver: NxpInputReceiver,
        hasInputDevice: Bool,
        timeoutMs: Int = 15000,
        initialDelayMs: UInt32 = 8
    ) -> UInt8 {
        if initialDelayMs > 0 {
            usleep(initialDelayMs * 1000)
        }
        let start = Date()
        while Date().timeIntervalSince(start) * 1000.0 < Double(timeoutMs) {
            let st = getLastOperationStatus(
                outDevice: outDevice,
                receiver: receiver,
                hasInputDevice: hasInputDevice
            )
            if st == 0x01 || st == 0xFF {
                usleep(10_000)
                continue
            }
            return st
        }
        return 0xFE
    }

    nonisolated private static func closeFile(
        outDevice: IOHIDDevice,
        receiver: NxpInputReceiver,
        hasInputDevice: Bool
    ) {
        sendOutReport([0x07, 0x17, 0x08, 0x00], to: outDevice, delayMs: 5)
        _ = waitOp(outDevice: outDevice, receiver: receiver, hasInputDevice: hasInputDevice, timeoutMs: 3000, initialDelayMs: 8)
    }

    @discardableResult
    nonisolated private static func openFileForWrite(
        name: String,
        outDevice: IOHIDDevice,
        receiver: NxpInputReceiver,
        hasInputDevice: Bool
    ) -> Bool {
        var pkt: [UInt8] = [0x07, 0x17, 0x05, 0x00]
        pkt.append(contentsOf: name.utf8)
        sendOutReport(pkt, to: outDevice, delayMs: 5)
        var st = waitOp(outDevice: outDevice, receiver: receiver, hasInputDevice: hasInputDevice, timeoutMs: 5000, initialDelayMs: 8)
        if st == 0x03 {
            // FileAlreadyOpened -> close and retry
            closeFile(outDevice: outDevice, receiver: receiver, hasInputDevice: hasInputDevice)
            sendOutReport(pkt, to: outDevice, delayMs: 5)
            st = waitOp(outDevice: outDevice, receiver: receiver, hasInputDevice: hasInputDevice, timeoutMs: 5000, initialDelayMs: 8)
        }
        // In NxpFileOperationsFeature::Impl::getFile<5>, both 0x00 and 0x04 are valid success codes
        return st == 0x00 || st == 0x04
    }

    @discardableResult
    nonisolated private static func writeNxpFile(
        name: String,
        data: [UInt8],
        outDevice: IOHIDDevice,
        receiver: NxpInputReceiver,
        hasInputDevice: Bool
    ) -> Bool {
        guard openFileForWrite(
            name: name,
            outDevice: outDevice,
            receiver: receiver,
            hasInputDevice: hasInputDevice
        ) else {
            return false
        }

        // Write in batches of maxBufferSize = 300 bytes (up to 5 packets x 60 bytes per batch)
        var offset = 0
        while offset < data.count {
            let batchLen = min(300, data.count - offset)
            let batch = Array(data[offset..<(offset + batchLen)])
            let pkts = (batchLen + 59) / 60
            for p in 1...pkts {
                let s = (p - 1) * 60
                let e = min(s + 60, batchLen)
                let chunk = Array(batch[s..<e])
                var pkt: [UInt8] = [0x7F, UInt8(p), UInt8(chunk.count), 0x00]
                pkt.append(contentsOf: chunk)
                sendOutReport(pkt, to: outDevice, delayMs: 3)
            }
            // commit<9>: flush buffer batch to currently open file
            sendOutReport([0x07, 0x17, 0x09, 0x00], to: outDevice, delayMs: 5)
            _ = waitOp(outDevice: outDevice, receiver: receiver, hasInputDevice: hasInputDevice, timeoutMs: 5000, initialDelayMs: 8)
            offset += batchLen
        }

        // commit<8>: close file
        closeFile(outDevice: outDevice, receiver: receiver, hasInputDevice: hasInputDevice)
        return true
    }

    @discardableResult
    private func sendPacket(_ bytes: [UInt8], to device: IOHIDDevice) -> IOReturn {
        Self.sendOutReport(bytes, to: device, delayMs: 0)
    }

    // MARK: - Device Protocol Handshake (Volatile Live Preview)

    private func initializeDeviceIfNeeded() {
        guard let device = connectedDevice, !isInitialized else { return }
        isInitialized = true

        // 1. SpecialFunctionControl: Software control mode
        sendPacket([0x07, 0x04, 0x02, 0x00], to: device)

        // 2. LightingControl: mode software 0x02, brightness 0x03 (MAX)
        var lc = [UInt8](repeating: 0, count: 64)
        lc[0] = 0x07; lc[1] = 0x05; lc[2] = 0x02; lc[3] = 0x00; lc[4] = 0x03
        sendPacket(lc, to: device)

        // 3. SetupLightingControl
        var s1 = [UInt8](repeating: 0, count: 64)
        s1[0] = 0x07; s1[1] = 0x05; s1[2] = 0x08; s1[3] = 0x00; s1[4] = 0x01
        sendPacket(s1, to: device)

        // 4. Matrix mapping: sequence covering all 150 key/zone positions
        let skipped: Set<UInt8> = [0x3F, 0x41, 0x42, 0x50, 0x53, 0x55, 0x6F, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0x80, 0x81]
        var identifier: UInt8 = 0
        for _ in 0..<5 {
            var pkt = [UInt8](repeating: 0, count: 64)
            pkt[0] = 0x07; pkt[1] = 0x40; pkt[2] = 0x1E
            for j in 0..<30 {
                while skipped.contains(identifier) {
                    identifier &+= 1
                }
                pkt[3 + j] = identifier
                identifier &+= 1
            }
            sendPacket(pkt, to: device)
        }

        Thread.sleep(forTimeInterval: 0.015)
    }

    // MARK: - Volatile Real-Time Streaming (Zero EEPROM Wear)

    public func applyLiveColor(_ color: Color) {
        guard let device = connectedDevice, !isWriting else { return }

        let now = Date()
        guard now.timeIntervalSince(lastStreamTime) > 0.02 else { return }
        lastStreamTime = now

        initializeDeviceIfNeeded()

        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = UInt8(clamping: Int((nsColor.redComponent * brightness * 255.0).rounded()))
        let g = UInt8(clamping: Int((nsColor.greenComponent * brightness * 255.0).rounded()))
        let b = UInt8(clamping: Int((nsColor.blueComponent * brightness * 255.0).rounded()))

        let nsBright = NSColor(brightnessButtonColor).usingColorSpace(.sRGB) ?? NSColor(brightnessButtonColor)
        let bR = UInt8(clamping: Int((nsBright.redComponent * brightness * 255.0).rounded()))
        let bG = UInt8(clamping: Int((nsBright.greenComponent * brightness * 255.0).rounded()))
        let bB = UInt8(clamping: Int((nsBright.blueComponent * brightness * 255.0).rounded()))

        let nsWinLock = NSColor(winLockUnlockedColor).usingColorSpace(.sRGB) ?? NSColor(winLockUnlockedColor)
        let wR = UInt8(clamping: Int((nsWinLock.redComponent * brightness * 255.0).rounded()))
        let wG = UInt8(clamping: Int((nsWinLock.greenComponent * brightness * 255.0).rounded()))
        let wB = UInt8(clamping: Int((nsWinLock.blueComponent * brightness * 255.0).rounded()))

        let nsProf = NSColor(profileButtonColor).usingColorSpace(.sRGB) ?? NSColor(profileButtonColor)
        let pR = UInt8(clamping: Int((nsProf.redComponent * brightness * 255.0).rounded()))
        let pG = UInt8(clamping: Int((nsProf.greenComponent * brightness * 255.0).rounded()))
        let pB = UInt8(clamping: Int((nsProf.blueComponent * brightness * 255.0).rounded()))

        func streamChannel(mainVal: UInt8, bVal: UInt8, wVal: UInt8, pVal: UInt8, channel: UInt8, finishVal: UInt8) {
            var channelBuf = [UInt8](repeating: mainVal, count: 168)
            channelBuf[16] = bVal
            channelBuf[114] = wVal
            channelBuf[125] = pVal

            var p1 = [UInt8](repeating: 0, count: 64)
            p1[0] = 0x7F; p1[1] = 0x01; p1[2] = 60; p1[3] = 0x00
            for k in 0..<60 { p1[4 + k] = channelBuf[k] }
            sendPacket(p1, to: device)

            var p2 = [UInt8](repeating: 0, count: 64)
            p2[0] = 0x7F; p2[1] = 0x02; p2[2] = 60; p2[3] = 0x00
            for k in 0..<60 { p2[4 + k] = channelBuf[60 + k] }
            sendPacket(p2, to: device)

            var p3 = [UInt8](repeating: 0, count: 64)
            p3[0] = 0x7F; p3[1] = 0x03; p3[2] = 48; p3[3] = 0x00
            for k in 0..<48 { p3[4 + k] = channelBuf[120 + k] }
            sendPacket(p3, to: device)

            var sub = [UInt8](repeating: 0, count: 64)
            sub[0] = 0x07; sub[1] = 0x28; sub[2] = channel; sub[3] = 0x03; sub[4] = finishVal
            sendPacket(sub, to: device)
        }

        streamChannel(mainVal: r, bVal: bR, wVal: wR, pVal: pR, channel: 1, finishVal: 1)
        streamChannel(mainVal: g, bVal: bG, wVal: wG, pVal: pG, channel: 2, finishVal: 1)
        streamChannel(mainVal: b, bVal: bB, wVal: wB, pVal: pB, channel: 3, finishVal: 2)

        isStreaming = true
        statusMessage = "Live Preview: \(currentHexColor)"
    }

    public func releaseToHardwareMode() {
        zoneWorkItem?.cancel()
        guard let device = connectedDevice, isStreaming else { return }
        sendPacket([0x07, 0x04, 0x01, 0x00], to: device)
        sendPacket([0x07, 0x05, 0x01, 0x00, 0x03], to: device)
        isStreaming = false
        isInitialized = false
        statusMessage = "Keyboard active in standalone hardware mode"
    }

    public func switchToHardwareSlot(_ slot: Int) {
        guard let device = connectedDevice, !isWriting else { return }
        selectedSlot = slot
        if let slotCol = slotProfiles[slot] {
            selectedColor = slotCol.color
        }
        let receiver = self.inputReceiver
        let hasIn = (self.inputDevice != nil)
        let slotIdx = UInt8(max(0, min(2, slot - 1)))

        hardwareQueue.async {
            Self.sendOutReport([0x07, 0x04, 0x02, 0x00], to: device, delayMs: 5)
            Self.sendOutReport([0x07, 0x17, 0x0C, slotIdx], to: device, delayMs: 5)
            _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 3000, initialDelayMs: 8)
            Self.sendOutReport([0x07, 0x04, 0x01, 0x00], to: device, delayMs: 5)
            Self.sendOutReport([0x07, 0x05, 0x01, 0x00, 0x03], to: device, delayMs: 5)
        }
        isStreaming = false
        isInitialized = false
        statusMessage = "Switched to Hardware Profile \(slot)"
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    // MARK: - Hardware Flash (Complete 7-File NXP Hardware Profile Package per Slot)

    public func flashColorToHardware(slot: Int? = nil, completion: (@MainActor () -> Void)? = nil) {
        let targetSlot = slot ?? selectedSlot
        let nsColor = NSColor(selectedColor).usingColorSpace(.sRGB) ?? NSColor(selectedColor)
        let r = UInt8(clamping: Int((nsColor.redComponent * brightness * 255.0).rounded()))
        let g = UInt8(clamping: Int((nsColor.greenComponent * brightness * 255.0).rounded()))
        let b = UInt8(clamping: Int((nsColor.blueComponent * brightness * 255.0).rounded()))

        slotProfiles[targetSlot] = HardwareSlotColor(r: r, g: g, b: b)
        saveSlotProfiles()

        flashAllProfilesToHardware(targetSlot: targetSlot, completion: completion)
    }

    /// Writes all 3 hardware profiles (Slot 1, Slot 2, Slot 3) to onboard SPI NOR flash
    /// using the exact iCUE `NxpRegularHardwareProfileStorageFeature::writeProfilePackage` sequence.
    public func flashAllProfilesToHardware(targetSlot: Int? = nil, completion: (@MainActor () -> Void)? = nil) {
        guard let device = connectedDevice else {
            statusMessage = "Device Not Found"
            return
        }
        guard !isWriting else { return }

        let activeTarget = targetSlot ?? selectedSlot
        isWriting = true
        statusMessage = "Writing all 3 profiles to onboard flash memory..."

        let profilesSnapshot = self.slotProfiles
        let winLockDisabledSnapshot = self.isWinLockDisabled

        let nsWinLockLocked = NSColor(winLockLockedColor).usingColorSpace(.sRGB) ?? NSColor(winLockLockedColor)
        let winLockLockedRGB: (UInt8, UInt8, UInt8) = (
            UInt8(clamping: Int((nsWinLockLocked.redComponent * 255.0).rounded())),
            UInt8(clamping: Int((nsWinLockLocked.greenComponent * 255.0).rounded())),
            UInt8(clamping: Int((nsWinLockLocked.blueComponent * 255.0).rounded()))
        )

        let nsWinLockUnlocked = NSColor(winLockUnlockedColor).usingColorSpace(.sRGB) ?? NSColor(winLockUnlockedColor)
        let winLockUnlockedRGB: (UInt8, UInt8, UInt8) = (
            UInt8(clamping: Int((nsWinLockUnlocked.redComponent * 255.0).rounded())),
            UInt8(clamping: Int((nsWinLockUnlocked.greenComponent * 255.0).rounded())),
            UInt8(clamping: Int((nsWinLockUnlocked.blueComponent * 255.0).rounded()))
        )

        let nsProf = NSColor(profileButtonColor).usingColorSpace(.sRGB) ?? NSColor(profileButtonColor)
        let profRGB: (UInt8, UInt8, UInt8) = (
            UInt8(clamping: Int((nsProf.redComponent * 255.0).rounded())),
            UInt8(clamping: Int((nsProf.greenComponent * 255.0).rounded())),
            UInt8(clamping: Int((nsProf.blueComponent * 255.0).rounded()))
        )

        let nsBright = NSColor(brightnessButtonColor).usingColorSpace(.sRGB) ?? NSColor(brightnessButtonColor)
        let brightRGB: (UInt8, UInt8, UInt8) = (
            UInt8(clamping: Int((nsBright.redComponent * 255.0).rounded())),
            UInt8(clamping: Int((nsBright.greenComponent * 255.0).rounded())),
            UInt8(clamping: Int((nsBright.blueComponent * 255.0).rounded()))
        )

        let receiver = self.inputReceiver
        let hasIn = (self.inputDevice != nil)
        let guids = Self.slotUUIDs

        hardwareQueue.async { [weak self] in
            // 1. Enter Software Control Mode before NXP file operations
            Self.sendOutReport([0x07, 0x04, 0x02, 0x00], to: device, delayMs: 8)
            Self.sendOutReport([0x07, 0x05, 0x02, 0x00, 0x03], to: device, delayMs: 8)

            // 2. Read existing 3-byte hwId cookies for slots 0..2 via 0E 15 01 <slot>
            var cookies: [[UInt8]] = [
                [0x01, 0x00, 0x00],
                [0x02, 0x00, 0x00],
                [0x03, 0x00, 0x00]
            ]
            for s in 0...2 {
                if let resp = Self.sendCommand(
                    [0x0E, 0x15, 0x01, UInt8(s)],
                    to: device,
                    receiver: receiver,
                    hasInputDevice: hasIn,
                    delayMs: 4
                ) {
                    let c = Array(resp[20...22])
                    if c != [0, 0, 0] {
                        cookies[s] = c
                    }
                }
            }
            // Ensure all 3 slot cookies are distinct and non-zero
            if cookies[1] == cookies[0] {
                cookies[1] = [cookies[0][0] &+ 1, cookies[0][1], cookies[0][2]]
                if cookies[1] == [0, 0, 0] { cookies[1] = [0x02, 0x00, 0x00] }
            }
            if cookies[2] == cookies[0] || cookies[2] == cookies[1] {
                cookies[2] = [cookies[1][0] &+ 1, cookies[1][1], cookies[1][2]]
                if cookies[2] == [0, 0, 0] || cookies[2] == cookies[0] {
                    cookies[2] = [0x03, 0x00, 0x00]
                }
            }

            // 3. Program all 3 hardware profile slots (0, 1, 2)
            for s in 0...2 {
                let slotNum = s + 1
                let col = profilesSnapshot[slotNum] ?? HardwareSlotColor(r: 255, g: 0, b: 0)
                let guid = guids[s]
                let hwId = cookies[s]

                Task { @MainActor [weak self] in
                    self?.statusMessage = "Flashing Hardware Profile \(slotNum) of 3..."
                }

                // Step A: clearProfile(s) (NxpHardwareProfileStorageFeature::Impl::clearProfile)
                // When QUuid::isNull(), bytes 4..19 are 0 and byte 23 is 0x00.
                var clearPkt = [UInt8](repeating: 0, count: 64)
                clearPkt[0] = 0x07
                clearPkt[1] = 0x15
                clearPkt[2] = UInt8(s)
                clearPkt[3] = 0x00
                clearPkt[20] = hwId[0]
                clearPkt[21] = hwId[1]
                clearPkt[22] = hwId[2]
                clearPkt[23] = 0x00
                Self.sendOutReport(clearPkt, to: device, delayMs: 10)
                let clearSt = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)
                if clearSt == 0x0C {
                    // NeedCommitChanges -> commitProfileChanges (07 17 0E 00) and retry clear
                    Self.sendOutReport([0x07, 0x17, 0x0E, 0x00], to: device, delayMs: 10)
                    _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)
                    Self.sendOutReport(clearPkt, to: device, delayMs: 10)
                    _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)
                }
                // commitProfileChanges after clearProfile
                Self.sendOutReport([0x07, 0x17, 0x0E, 0x00], to: device, delayMs: 10)
                _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)

                // Step B: commitProfileInfo(s, info) (byte 23 = 0x01 for non-null QUuid)
                var infoPkt = [UInt8](repeating: 0, count: 64)
                infoPkt[0] = 0x07
                infoPkt[1] = 0x15
                infoPkt[2] = UInt8(s)
                infoPkt[3] = 0x00
                for i in 0..<16 { infoPkt[4 + i] = guid[i] }
                infoPkt[20] = hwId[0]
                infoPkt[21] = hwId[1]
                infoPkt[22] = hwId[2]
                infoPkt[23] = 0x01
                Self.sendOutReport(infoPkt, to: device, delayMs: 10)
                let infoSt = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)
                if infoSt == 0x0C {
                    Self.sendOutReport([0x07, 0x17, 0x0E, 0x00], to: device, delayMs: 10)
                    _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)
                    Self.sendOutReport(infoPkt, to: device, delayMs: 10)
                    _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)
                }

                // Step C: setCurrentProfile(s) (07 17 0C <slot>)
                Self.sendOutReport([0x07, 0x17, 0x0C, UInt8(s)], to: device, delayMs: 8)
                _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 5000, initialDelayMs: 10)

                // Step D: Build and write all 7 files in QMap lexicographical order
                // 1. "PROFILE.DAT" (4 bytes): [0x50, isWinLockDisabled ? 0x00 : 0x02, 0x00, 0x00]
                let profileDat: [UInt8] = [0x50, winLockDisabledSnapshot ? 0x00 : 0x02, 0x00, 0x00]

                // 2. "PROFILE.I" (268 bytes)
                var profileI = [UInt8](repeating: 0, count: 268)
                profileI[0] = 0x49
                profileI[1] = 0x00
                for i in 0..<16 { profileI[2 + i] = guid[i] }
                profileI[18] = hwId[0]
                profileI[19] = hwId[1]
                profileI[20] = hwId[2]
                profileI[21] = 0x00
                if let nameData = "Profile \(slotNum)".data(using: .utf16LittleEndian) {
                    let count = min(nameData.count, 230)
                    nameData.copyBytes(to: &profileI[22], count: count)
                }
                profileI[252] = 0x00
                profileI[253] = profRGB.0
                profileI[254] = profRGB.1
                profileI[255] = profRGB.2
                profileI[256] = brightRGB.0
                profileI[257] = brightRGB.1
                profileI[258] = brightRGB.2
                profileI[259] = winLockLockedRGB.0
                profileI[260] = winLockLockedRGB.1
                profileI[261] = winLockLockedRGB.2
                profileI[262] = winLockUnlockedRGB.0
                profileI[263] = winLockUnlockedRGB.1
                profileI[264] = winLockUnlockedRGB.2
                profileI[265] = 0xFF // SidelightingControl enabled

                // 3. "PROFILE.MAP" (4 bytes)
                let profileMap: [UInt8] = [0x41, 0x00, 0x00, 0x00]

                // 4. "lght_00.d" (37 bytes: Static lighting header)
                var lghtD = [UInt8](repeating: 0, count: 37)
                lghtD[0] = 0x07  // Static effect type
                lghtD[18] = 0x01 // Effect enabled flag

                // 5. "lght_00.k" (160 bytes: 156 key indices 0..155)
                var lghtK = [UInt8](repeating: 0, count: 160)
                lghtK[0] = 0x9C  // 156 keys (LE uint32)
                for k in 0..<156 {
                    lghtK[4 + k] = UInt8(k)
                }

                // 6. "lght_00.r" (1024 bytes: 156 x [R, G, B, 0xFF] entries, zero-padded to 1024)
                var lghtR = [UInt8](repeating: 0, count: 1024)
                for k in 0..<156 {
                    let base = k * 4
                    if k == 16 {
                        lghtR[base] = brightRGB.0
                        lghtR[base + 1] = brightRGB.1
                        lghtR[base + 2] = brightRGB.2
                        lghtR[base + 3] = 0xFF
                    } else if k == 114 {
                        lghtR[base] = winLockUnlockedRGB.0
                        lghtR[base + 1] = winLockUnlockedRGB.1
                        lghtR[base + 2] = winLockUnlockedRGB.2
                        lghtR[base + 3] = 0xFF
                    } else if k == 125 {
                        lghtR[base] = profRGB.0
                        lghtR[base + 1] = profRGB.1
                        lghtR[base + 2] = profRGB.2
                        lghtR[base + 3] = 0xFF
                    } else {
                        lghtR[base] = col.r
                        lghtR[base + 1] = col.g
                        lghtR[base + 2] = col.b
                        lghtR[base + 3] = 0xFF
                    }
                }

                // 7. "lghtcnt.cnt" (4 bytes: 1 lighting effect)
                let lghtCnt: [UInt8] = [0x01, 0x00, 0x00, 0x00]

                let filesToWrite: [(String, [UInt8])] = [
                    ("PROFILE.DAT", profileDat),
                    ("PROFILE.I", profileI),
                    ("PROFILE.MAP", profileMap),
                    ("lght_00.d", lghtD),
                    ("lght_00.k", lghtK),
                    ("lght_00.r", lghtR),
                    ("lghtcnt.cnt", lghtCnt)
                ]

                for (fileName, fileBytes) in filesToWrite {
                    Self.writeNxpFile(
                        name: fileName,
                        data: fileBytes,
                        outDevice: device,
                        receiver: receiver,
                        hasInputDevice: hasIn
                    )
                }

                // Step E: commitProfileChanges() (07 17 0E 00) for slot s
                Self.sendOutReport([0x07, 0x17, 0x0E, 0x00], to: device, delayMs: 10)
                _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)
            }

            // 4. Select active target slot (0-based) and commit
            let targetSlotIdx = UInt8(max(0, min(2, activeTarget - 1)))
            Self.sendOutReport([0x07, 0x17, 0x0C, targetSlotIdx], to: device, delayMs: 8)
            _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 5000, initialDelayMs: 10)

            Self.sendOutReport([0x07, 0x17, 0x0E, 0x00], to: device, delayMs: 10)
            _ = Self.waitOp(outDevice: device, receiver: receiver, hasInputDevice: hasIn, timeoutMs: 15000, initialDelayMs: 15)

            // 5. Apply WinLock physical function state & return keyboard to standalone Hardware Mode
            Self.sendOutReport([0x07, 0x48, winLockDisabledSnapshot ? 0x00 : 0x80, 0x00], to: device, delayMs: 5)
            Self.sendOutReport([0x07, 0x04, 0x01, 0x00], to: device, delayMs: 8)
            Self.sendOutReport([0x07, 0x05, 0x01, 0x00, 0x03], to: device, delayMs: 8)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isStreaming = false
                self.isInitialized = false
                for s in 1...3 { self.markSlotSaved(s) }
                self.isWriting = false
                self.statusMessage = "✓ Written to Hardware Memory (All 3 Profiles & Top Buttons)"
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                completion?()
            }
        }
    }

    /// Commits all 3 profiles to hardware memory and terminates the app only after flash completion (0 MB residual RAM).
    public func flashAndQuit() {
        flashColorToHardware(slot: selectedSlot) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    public var currentHexColor: String {
        let nsColor = NSColor(selectedColor).usingColorSpace(.sRGB) ?? NSColor(selectedColor)
        let r = Int((nsColor.redComponent * 255.0).rounded())
        let g = Int((nsColor.greenComponent * 255.0).rounded())
        let b = Int((nsColor.blueComponent * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
