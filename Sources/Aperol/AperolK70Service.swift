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

/// Native IOKit USB HID controller for Corsair K70 MK.2 RGB keyboard.
/// Fully implements the reverse-engineered hardware SPI Flash storage protocol:
/// - Single-interface synchronous Feature Report control (0xFFC2:0x0004)
/// - All 7 onboard NXP filesystem files per slot:
///   "PROFILE.DAT", "PROFILE.I", "PROFILE.MAP", "lght_00.d", "lght_00.k", "lght_00.r", "lghtcnt.cnt"
/// - SPI NOR Flash commit (0x07 0x17 0x0E 0x00) with 5.0s sector erase settle time.
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

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var deviceName: String = "Corsair K70 RGB MK.2"
    @Published public var selectedColor: Color = Color(red: 1.0, green: 0.0, blue: 0.0) {
        didSet {
            if isTopButtonsAutoSynced {
                syncTopButtonsToActiveColor(selectedColor)
            }
        }
    }
    @Published public var brightness: Double = 1.0
    @Published public var statusMessage: String?
    @Published public var isWriting: Bool = false
    @Published public var selectedSlot: Int = 1 {
        didSet {
            UserDefaults.standard.set(selectedSlot, forKey: "AperolActiveSlot_v1")
        }
    }
    @Published public var savedSlots: Set<Int> = [1, 2, 3]
    @Published public var slotProfiles: [Int: HardwareSlotColor] = [:]
    @Published public var presets: [ColorPreset] = []
    @Published public var hoveredPresetId: UUID? = nil
    @Published public var editingPresetId: UUID? = nil
    @Published public private(set) var isStreaming: Bool = false
    @Published public var copiedHex: Bool = false
    public var hasUserInteractedWithColor: Bool = false

    // MARK: - Top Buttons & WinLock Controls
    @Published public var isTopButtonsAutoSynced: Bool = true {
        didSet {
            UserDefaults.standard.set(isTopButtonsAutoSynced, forKey: "AperolTopButtonsAutoSynced_v2")
            if isTopButtonsAutoSynced {
                syncTopButtonsToActiveColor(selectedColor)
            }
        }
    }
    @Published public var isWinLockDisabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isWinLockDisabled, forKey: "AperolWinLockDisabled_v1")
            sendWinLockDisabledReport(isWinLockDisabled)
        }
    }
    @Published public var winLockLockedColor: Color = Color(red: 1.0, green: 0.0, blue: 0.0) {
        didSet {
            UserDefaults.standard.set(Self.hexFromColor(winLockLockedColor), forKey: "AperolWinLockLockedHex_v1")
            if hasUserInteractedWithColor { applyLiveColor(selectedColor) }
        }
    }
    @Published public var winLockUnlockedColor: Color = Color(red: 1.0, green: 0.0, blue: 0.0) {
        didSet {
            UserDefaults.standard.set(Self.hexFromColor(winLockUnlockedColor), forKey: "AperolWinLockUnlockedHex_v1")
            if hasUserInteractedWithColor { applyLiveColor(selectedColor) }
        }
    }
    @Published public var profileButtonColor: Color = Color(red: 1.0, green: 0.0, blue: 0.0) {
        didSet {
            UserDefaults.standard.set(Self.hexFromColor(profileButtonColor), forKey: "AperolProfileButtonHex_v1")
            if hasUserInteractedWithColor { applyLiveColor(selectedColor) }
        }
    }
    @Published public var brightnessButtonColor: Color = Color(red: 1.0, green: 0.0, blue: 0.0) {
        didSet {
            UserDefaults.standard.set(Self.hexFromColor(brightnessButtonColor), forKey: "AperolBrightnessButtonHex_v1")
            if hasUserInteractedWithColor { applyLiveColor(selectedColor) }
        }
    }

    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice? // 0xFFC2:0x0004
    private let hardwareQueue = DispatchQueue(label: "com.aperol.k70.hardware-flash", qos: .userInitiated)
    private var isInitialized: Bool = false
    private var lastStreamTime: Date = Date.distantPast
    private var zoneWorkItem: DispatchWorkItem?

    private init() {
        loadPresets()
        loadSavedSlots()
        loadSlotProfiles()
        if let initialColor = slotProfiles[selectedSlot]?.color {
            self.selectedColor = initialColor
        }
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
        if let savedSlot = UserDefaults.standard.object(forKey: "AperolActiveSlot_v1") as? Int, (1...3).contains(savedSlot) {
            self.selectedSlot = savedSlot
        } else {
            self.selectedSlot = 2
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
        if defaults.object(forKey: "AperolTopButtonsAutoSynced_v2") != nil {
            self.isTopButtonsAutoSynced = defaults.bool(forKey: "AperolTopButtonsAutoSynced_v2")
        } else {
            self.isTopButtonsAutoSynced = true
        }

        if isTopButtonsAutoSynced {
            self.winLockLockedColor = selectedColor
            self.winLockUnlockedColor = selectedColor
            self.profileButtonColor = selectedColor
            self.brightnessButtonColor = selectedColor
        } else {
            if let hex = defaults.string(forKey: "AperolWinLockLockedHex_v1"), let c = Self.colorFromHex(hex) {
                self.winLockLockedColor = c
            } else {
                self.winLockLockedColor = selectedColor
            }
            if let hex = defaults.string(forKey: "AperolWinLockUnlockedHex_v1"), let c = Self.colorFromHex(hex) {
                self.winLockUnlockedColor = c
            } else {
                self.winLockUnlockedColor = selectedColor
            }
            if let hex = defaults.string(forKey: "AperolProfileButtonHex_v1"), let c = Self.colorFromHex(hex) {
                self.profileButtonColor = c
            } else {
                self.profileButtonColor = selectedColor
            }
            if let hex = defaults.string(forKey: "AperolBrightnessButtonHex_v1"), let c = Self.colorFromHex(hex) {
                self.brightnessButtonColor = c
            } else {
                self.brightnessButtonColor = selectedColor
            }
        }
    }

    public func syncTopButtonsToActiveColor(_ color: Color) {
        winLockLockedColor = color
        winLockUnlockedColor = color
        profileButtonColor = color
        brightnessButtonColor = color
        if hasUserInteractedWithColor {
            applyLiveColor(color)
        }
    }

    public func sendWinLockDisabledReport(_ disabled: Bool) {
        guard let device = connectedDevice else { return }
        _ = Self.sendReport([0x07, 0x48, disabled ? 0x00 : 0x80, 0x00], to: device)
        statusMessage = disabled ? "WinLock Key Action Disabled" : "WinLock Key Action Enabled"
    }

    public func syncAllTopButtonsToSelectedColor() {
        isTopButtonsAutoSynced = true
        syncTopButtonsToActiveColor(selectedColor)
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

    // MARK: - HID Management (0xFFC2:0x0004 Feature Report Interface)

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

        guard isOutLightingInterface(device) else { return }

        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            deviceName = name
        }

        self.connectedDevice = device
        self.isConnected = true
        self.statusMessage = "Connected: \(deviceName)"
    }

    private func deviceDetached(_ device: IOHIDDevice) {
        if connectedDevice == device {
            connectedDevice = nil
            isConnected = false
            isInitialized = false
            statusMessage = "Device Disconnected"
        }
    }

    // MARK: - Proven Synchronous HID Transport (from K70HardwareProfileBurner)

    @discardableResult
    nonisolated private static func sendReport(
        _ bytes: [UInt8],
        to device: IOHIDDevice
    ) -> Bool {
        var pkt = [UInt8](repeating: 0, count: 64)
        for (i, b) in bytes.enumerated() where i < 64 { pkt[i] = b }
        let kr = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, pkt, 64)
        if kr == kIOReturnSuccess {
            return true
        }
        let krOut = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pkt, 64)
        return krOut == kIOReturnSuccess
    }

    nonisolated private static func getOpStatus(
        dev: IOHIDDevice
    ) -> (st: UInt8, err: UInt8) {
        _ = sendReport([0x0E, 0x17, 0x0D, 0x00], to: dev)
        usleep(15000) // 15ms settle time for MCU USB FIFO
        var resp = [UInt8](repeating: 0, count: 64)
        var len = 64
        let kr = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 0, &resp, &len)
        if kr == kIOReturnSuccess {
            return (resp[4], resp[5])
        }
        return (0xFE, 0xFE)
    }

    nonisolated private static func waitOp(
        dev: IOHIDDevice,
        timeoutMs: Int = 4000,
        desc: String = ""
    ) -> (st: UInt8, err: UInt8) {
        usleep(40000) // 40ms initial settle time
        let start = Date()
        while Date().timeIntervalSince(start) * 1000.0 < Double(timeoutMs) {
            let (st, err) = getOpStatus(dev: dev)
            // 0x01 = InProgress, 0xFE = USB bus settling / SPI flash busy
            if st != 0x01 && st != 0xFE {
                return (st, err)
            }
            usleep(40000) // 40ms polling interval
        }
        return (0xFE, 0xFE)
    }

    nonisolated private static func closeFile(dev: IOHIDDevice) {
        _ = sendReport([0x07, 0x17, 0x08, 0x00], to: dev)
        _ = waitOp(dev: dev, timeoutMs: 3000, desc: "closeFile")
        usleep(30000)
    }

    @discardableResult
    nonisolated private static func openFileForWrite(
        name: String,
        dev: IOHIDDevice,
        timeoutMs: Int = 8000
    ) -> Bool {
        var openPkt = [UInt8](repeating: 0, count: 64)
        openPkt[0] = 0x07; openPkt[1] = 0x17; openPkt[2] = 0x05; openPkt[3] = 0x00
        let nameBytes = Array(name.utf8)
        for i in 0..<nameBytes.count { openPkt[4 + i] = nameBytes[i] }

        let start = Date()
        while Date().timeIntervalSince(start) * 1000.0 < Double(timeoutMs) {
            let ok = sendReport(openPkt, to: dev)
            if !ok {
                usleep(200000)
                continue
            }
            let res = waitOp(dev: dev, timeoutMs: 3500, desc: "openWrite \(name)")
            if res.st == 0x00 || res.st == 0x04 {
                return true
            }
            if res.st == 0x03 { // FileAlreadyOpened -> close and retry
                closeFile(dev: dev)
            } else if res.st == 0x0C || res.st == 0x0D { // Flash busy
                usleep(500000) // Wait 500ms for flash erase/write cycle
            } else {
                usleep(200000)
            }
        }
        return false
    }

    @discardableResult
    nonisolated private static func writeFile(
        name: String,
        data: [UInt8],
        dev: IOHIDDevice
    ) -> Bool {
        guard openFileForWrite(name: name, dev: dev) else {
            return false
        }
        var offset = 0
        while offset < data.count {
            let batchLen = min(300, data.count - offset)
            let batch = Array(data[offset..<(offset + batchLen)])
            let pkts = (batchLen + 59) / 60
            for p in 1...pkts {
                let s = (p - 1) * 60
                let e = min(s + 60, batchLen)
                let chunk = Array(batch[s..<e])
                var pkt = [UInt8](repeating: 0, count: 64)
                pkt[0] = 0x7F; pkt[1] = UInt8(p); pkt[2] = UInt8(chunk.count); pkt[3] = 0x00
                for i in 0..<chunk.count { pkt[4 + i] = chunk[i] }
                let ok = sendReport(pkt, to: dev)
                if !ok {
                    closeFile(dev: dev)
                    return false
                }
                usleep(12000) // 12ms quiet delay between chunk packets
            }
            // Flush batch to MCU buffer: 0x09 commits the 300-byte SRAM buffer into file stream
            let okFlush = sendReport([0x07, 0x17, 0x09, 0x00], to: dev)
            if !okFlush {
                closeFile(dev: dev)
                return false
            }
            usleep(25000) // 25ms settle time for SRAM commit
            offset += batchLen
        }
        closeFile(dev: dev)
        // If this was the large RGB buffer (lght_00.r), give SPI Flash 800ms to commit the 1024 bytes
        if data.count >= 500 {
            usleep(800000) // 800ms settle for SPI Flash
        } else {
            usleep(50000)  // 50ms settle for small files
        }
        return true
    }

    // MARK: - Device Protocol Handshake (Volatile Live Preview)

    private func initializeDeviceIfNeeded() {
        guard let device = connectedDevice, !isInitialized else { return }
        isInitialized = true

        // 1. SpecialFunctionControl: Software control mode
        Self.sendReport([0x07, 0x04, 0x02, 0x00], to: device)

        // 2. LightingControl: mode software 0x02, brightness 0x03 (MAX)
        var lc = [UInt8](repeating: 0, count: 64)
        lc[0] = 0x07; lc[1] = 0x05; lc[2] = 0x02; lc[3] = 0x00; lc[4] = 0x03
        Self.sendReport(lc, to: device)

        // 3. SetupLightingControl
        var s1 = [UInt8](repeating: 0, count: 64)
        s1[0] = 0x07; s1[1] = 0x05; s1[2] = 0x08; s1[3] = 0x00; s1[4] = 0x01
        Self.sendReport(s1, to: device)

        usleep(15000)
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

        let (bR, bG, bB): (UInt8, UInt8, UInt8)
        let (wR, wG, wB): (UInt8, UInt8, UInt8)
        let (pR, pG, pB): (UInt8, UInt8, UInt8)

        if isTopButtonsAutoSynced {
            bR = r; bG = g; bB = b
            wR = r; wG = g; wB = b
            pR = r; pG = g; pB = b
        } else {
            let nsBright = NSColor(brightnessButtonColor).usingColorSpace(.sRGB) ?? NSColor(brightnessButtonColor)
            bR = UInt8(clamping: Int((nsBright.redComponent * brightness * 255.0).rounded()))
            bG = UInt8(clamping: Int((nsBright.greenComponent * brightness * 255.0).rounded()))
            bB = UInt8(clamping: Int((nsBright.blueComponent * brightness * 255.0).rounded()))

            let nsWinLock = NSColor(winLockUnlockedColor).usingColorSpace(.sRGB) ?? NSColor(winLockUnlockedColor)
            wR = UInt8(clamping: Int((nsWinLock.redComponent * brightness * 255.0).rounded()))
            wG = UInt8(clamping: Int((nsWinLock.greenComponent * brightness * 255.0).rounded()))
            wB = UInt8(clamping: Int((nsWinLock.blueComponent * brightness * 255.0).rounded()))

            let nsProf = NSColor(profileButtonColor).usingColorSpace(.sRGB) ?? NSColor(profileButtonColor)
            pR = UInt8(clamping: Int((nsProf.redComponent * brightness * 255.0).rounded()))
            pG = UInt8(clamping: Int((nsProf.greenComponent * brightness * 255.0).rounded()))
            pB = UInt8(clamping: Int((nsProf.blueComponent * brightness * 255.0).rounded()))
        }

        // K70 MK.2 hardware LED scancode map:
        // Position 8 = WinLock Button (KEY_EN_WINDOWS_LOCK)
        // Position 125 = Profile Switch Button (KEY_EN_PROFILE)
        // Position 137 = Brightness Button (KEY_EN_BRIGHTNESS)
        // Note: Position 16 is '<' (ISO backslash) and Position 114 is ',' (ISO hash) -> they remain mainVal!
        func streamChannel(mainVal: UInt8, bVal: UInt8, wVal: UInt8, pVal: UInt8, channel: UInt8, finishVal: UInt8) {
            var channelBuf = [UInt8](repeating: mainVal, count: 168)
            channelBuf[8] = wVal     // WinLock Button
            channelBuf[125] = pVal   // Profile Switch Button
            channelBuf[137] = bVal   // Brightness Button

            var p1 = [UInt8](repeating: 0, count: 64)
            p1[0] = 0x7F; p1[1] = 0x01; p1[2] = 60; p1[3] = 0x00
            for k in 0..<60 { p1[4 + k] = channelBuf[k] }
            Self.sendReport(p1, to: device)

            var p2 = [UInt8](repeating: 0, count: 64)
            p2[0] = 0x7F; p2[1] = 0x02; p2[2] = 60; p2[3] = 0x00
            for k in 0..<60 { p2[4 + k] = channelBuf[60 + k] }
            Self.sendReport(p2, to: device)

            var p3 = [UInt8](repeating: 0, count: 64)
            p3[0] = 0x7F; p3[1] = 0x03; p3[2] = 48; p3[3] = 0x00
            for k in 0..<48 { p3[4 + k] = channelBuf[120 + k] }
            Self.sendReport(p3, to: device)

            var sub = [UInt8](repeating: 0, count: 64)
            sub[0] = 0x07; sub[1] = 0x28; sub[2] = channel; sub[3] = 0x03; sub[4] = finishVal
            Self.sendReport(sub, to: device)
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
        Self.sendReport([0x07, 0x04, 0x01, 0x00], to: device)
        Self.sendReport([0x07, 0x05, 0x01, 0x00, 0x03], to: device)
        isStreaming = false
        isInitialized = false
        statusMessage = "Keyboard active in standalone hardware mode"
    }

    public func switchToHardwareSlot(_ slot: Int) {
        guard let device = connectedDevice, !isWriting else { return }
        selectedSlot = slot
        if let slotCol = slotProfiles[slot] {
            selectedColor = slotCol.color
            if isTopButtonsAutoSynced {
                syncTopButtonsToActiveColor(slotCol.color)
            }
        }
        let slotIdx = UInt8(max(0, min(2, slot - 1)))

        hardwareQueue.async { [weak self] in
            guard let self else { return }
            // 1. Enter software mode
            Self.sendReport([0x07, 0x04, 0x02, 0x00], to: device)
            Self.sendReport([0x07, 0x05, 0x02, 0x00, 0x03], to: device)
            usleep(50000)

            // 2. Select slot directory & commit
            Self.sendReport([0x07, 0x17, 0x0C, slotIdx], to: device)
            usleep(100000)
            Self.sendReport([0x07, 0x17, 0x0E, 0x00], to: device)
            sleep(1)

            // 3. Return to hardware mode
            Self.sendReport([0x07, 0x04, 0x01, 0x00], to: device)
            Self.sendReport([0x07, 0x05, 0x01, 0x00, 0x03], to: device)
            usleep(50000)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isStreaming = false
                self.isInitialized = false
                self.statusMessage = "Switched to Hardware Profile \(slot)"
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            }
        }
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
    /// using the proven reliable K70HardwareProfileBurner sequence.
    public func flashAllProfilesToHardware(targetSlot: Int? = nil, completion: (@MainActor () -> Void)? = nil) {
        guard let device = connectedDevice else {
            statusMessage = "Device Not Found"
            return
        }
        guard !isWriting else { return }

        let activeTarget = targetSlot ?? selectedSlot
        isWriting = true
        statusMessage = "Flashing hardware profiles to onboard flash memory..."

        let profilesSnapshot = self.slotProfiles
        let winLockDisabledSnapshot = self.isWinLockDisabled

        hardwareQueue.async { [weak self] in
            // 1. Enter Software Mode
            Self.sendReport([0x07, 0x04, 0x02, 0x00], to: device)
            Self.sendReport([0x07, 0x05, 0x02, 0x00, 0x03], to: device)
            usleep(50000)

            for s in 0...2 {
                let slotNum = s + 1
                let col = profilesSnapshot[slotNum] ?? HardwareSlotColor(r: 255, g: 0, b: 0)

                Task { @MainActor [weak self] in
                    self?.statusMessage = "Programming Slot \(slotNum) of 3 (R:\(col.r), G:\(col.g), B:\(col.b))..."
                }

                // Step A: Register Profile Info (0x15)
                let guid: [UInt8] = [
                    0xC0, 0x85, 0xA1, 0x01,
                    0x4A, 0x70, 0x4B, 0x70,
                    0x80, UInt8(slotNum), 0x00, 0x00,
                    0x00, 0x00, 0x00, UInt8(slotNum)
                ]
                let hwId: [UInt8] = [UInt8(slotNum), 0x00, 0x00]

                var infoPkt = [UInt8](repeating: 0, count: 64)
                infoPkt[0] = 0x07; infoPkt[1] = 0x15; infoPkt[2] = UInt8(s); infoPkt[3] = 0x00
                for i in 0..<16 { infoPkt[4 + i] = guid[i] }
                infoPkt[20] = hwId[0]; infoPkt[21] = hwId[1]; infoPkt[22] = hwId[2]; infoPkt[23] = 0x01

                var infoRegistered = false
                for _ in 1...5 {
                    let ok = Self.sendReport(infoPkt, to: device)
                    if !ok { break }
                    let infoSt = Self.waitOp(dev: device, timeoutMs: 3000, desc: "commitProfileInfo \(slotNum)")
                    if infoSt.st == 0x00 {
                        infoRegistered = true
                        break
                    } else if infoSt.st == 0x0C || infoSt.st == 0x0D {
                        sleep(2)
                    } else {
                        usleep(200000)
                    }
                }

                guard infoRegistered else {
                    Task { @MainActor [weak self] in
                        self?.isWriting = false
                        self?.statusMessage = "❌ Flash Error: Slot \(slotNum) profile info failed"
                    }
                    return
                }

                // Step B: Set Current Profile Slot Directory (0x0C)
                let okSlot = Self.sendReport([0x07, 0x17, 0x0C, UInt8(s)], to: device)
                guard okSlot else {
                    Task { @MainActor [weak self] in
                        self?.isWriting = false
                        self?.statusMessage = "❌ Flash Error: Slot \(slotNum) directory failed"
                    }
                    return
                }
                usleep(150000) // 150ms settle for slot directory pointer

                // Step C: Build 7 Profile Files
                // 1. PROFILE.DAT
                let profileDat: [UInt8] = [0x50, winLockDisabledSnapshot ? 0x00 : 0x02, 0x00, 0x00]

                // 2. PROFILE.I (268 bytes): Every profile slot burns its own true uniform color to all top buttons!
                var profileI = [UInt8](repeating: 0, count: 268)
                profileI[0] = 0x49; profileI[1] = 0x00
                for i in 0..<16 { profileI[2 + i] = guid[i] }
                profileI[18] = hwId[0]; profileI[19] = hwId[1]; profileI[20] = hwId[2]; profileI[21] = 0x00
                if let nameData = "Profile \(slotNum)".data(using: .utf16LittleEndian) {
                    nameData.copyBytes(to: &profileI[22], count: min(nameData.count, 230))
                }
                profileI[252] = 0x00

                // Identical to K70HardwareProfileBurner: Top buttons match each profile's authentic color!
                profileI[253] = col.r; profileI[254] = col.g; profileI[255] = col.b // Profile Button RGB
                profileI[256] = col.r; profileI[257] = col.g; profileI[258] = col.b // Brightness Button RGB
                profileI[259] = col.r; profileI[260] = col.g; profileI[261] = col.b // WinLock Locked RGB
                profileI[262] = col.r; profileI[263] = col.g; profileI[264] = col.b // WinLock Unlocked RGB
                profileI[265] = 0xFF // SidelightingControl enabled

                // 3. PROFILE.MAP
                let profileMap: [UInt8] = [0x41, 0x00, 0x00, 0x00]

                // 4. lght_00.d
                var lghtD = [UInt8](repeating: 0, count: 37)
                lghtD[0] = 0x07
                lghtD[18] = 0x01

                // 5. lght_00.k
                var lghtK = [UInt8](repeating: 0, count: 160)
                lghtK[0] = 0x9C
                for k in 0..<156 { lghtK[4 + k] = UInt8(k) }

                // 6. lght_00.r (1024 bytes allocated)
                var lghtR = [UInt8](repeating: 0, count: 1024)
                for k in 0..<156 {
                    let base = k * 4
                    lghtR[base]     = col.r
                    lghtR[base + 1] = col.g
                    lghtR[base + 2] = col.b
                    lghtR[base + 3] = 0xFF
                }

                // 7. lghtcnt.cnt
                let lghtCnt: [UInt8] = [0x01, 0x00, 0x00, 0x00]

                let files: [(String, [UInt8])] = [
                    ("PROFILE.DAT", profileDat),
                    ("PROFILE.I", profileI),
                    ("PROFILE.MAP", profileMap),
                    ("lght_00.d", lghtD),
                    ("lght_00.k", lghtK),
                    ("lght_00.r", lghtR),
                    ("lghtcnt.cnt", lghtCnt)
                ]

                var writeSuccess = true
                for (fname, bytes) in files {
                    if !Self.writeFile(name: fname, data: bytes, dev: device) {
                        writeSuccess = false
                        break
                    }
                }

                guard writeSuccess else {
                    Task { @MainActor [weak self] in
                        self?.isWriting = false
                        self?.statusMessage = "❌ Flash Error: Slot \(slotNum) write failed"
                    }
                    return
                }

                // Step D: Commit Profile Changes to physical SPI NOR Flash (0x0E)
                let okCommit = Self.sendReport([0x07, 0x17, 0x0E, 0x00], to: device)
                guard okCommit else {
                    Task { @MainActor [weak self] in
                        self?.isWriting = false
                        self?.statusMessage = "❌ Flash Error: Slot \(slotNum) commit failed"
                    }
                    return
                }
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Slot \(slotNum) saved! SPI Flash settling (5s)..."
                }
                sleep(5)
            }

            // Step 4: Set active slot
            let targetSlotIdx = UInt8(max(0, min(2, activeTarget - 1)))
            _ = Self.sendReport([0x07, 0x17, 0x0C, targetSlotIdx], to: device)
            usleep(100000)
            _ = Self.sendReport([0x07, 0x17, 0x0E, 0x00], to: device)
            sleep(2)

            // Step 5: Apply WinLock physical key action
            _ = Self.sendReport([0x07, 0x48, winLockDisabledSnapshot ? 0x00 : 0x80, 0x00], to: device)
            usleep(50000)

            // Step 6: Return keyboard to standalone Hardware Mode
            _ = Self.sendReport([0x07, 0x04, 0x01, 0x00], to: device)
            _ = Self.sendReport([0x07, 0x05, 0x01, 0x00, 0x03], to: device)
            usleep(50000)

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
