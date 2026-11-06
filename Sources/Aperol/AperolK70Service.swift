// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import AppKit
import Foundation
import IOKit
import IOKit.hid
import SwiftUI

/// Represents a customizable, user-editable color preset.
public struct ColorPreset: Identifiable, Codable, Equatable {
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
public struct HardwareSlotColor: Codable, Equatable {
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
/// Fully controls 3 onboard hardware profiles (8MB onboard flash memory), volatile SRAM live streaming,
/// and writes directly to hardware memory via reverse-engineered NXP flash protocol:
/// - 3-Slot Directory Table & Active Descriptors (CMD 0x15 & 0x17)
/// - Hardware Lighting Playback Files (lghtcnt.cnt + lght_0X.d)
/// - Full 24-bit RGB Matrix (CMD 0x14 SUB 0x03) across all 150 positions
/// - WinLock Custom ON/OFF Colors per slot (CMD 0x14 SUB 0x06 & 0x07)
/// - Final NXP Profile Commit (CMD 0x17 SUB 0x0E)
@MainActor
public final class AperolK70Service: ObservableObject {
    public static let shared = AperolK70Service()

    public static let corsairVendorID: Int = 0x1B1C
    public static let supportedProductIDs: Set<Int> = [
        0x1B49, // K70 RGB MK.2
        0x1B6B, // K70 RGB MK.2 Low Profile
        0x1B55, // K70 RGB MK.2 LP Variant
        0x1B38, // K70 LUX RGB
        0x1B13, // K70 RGB (Legacy)
        0x1B33, // K95 Platinum
        0x1B36  // K68 RGB
    ]

    public static let maxOnboardSlots: Int = 3 // K70 MK.2 has 3 onboard hardware profiles in 8MB flash

    private static let slotUUIDs: [UUID] = [
        UUID(uuidString: "C085A101-0000-0000-0000-000000000001")!,
        UUID(uuidString: "C085A102-0000-0000-0000-000000000002")!,
        UUID(uuidString: "C085A103-0000-0000-0000-000000000003")!
    ]

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var deviceName: String = "Corsair K70 RGB MK.2"
    @Published public var selectedColor: Color = Color(red: 242.0 / 255.0, green: 101.0 / 255.0, blue: 34.0 / 255.0)
    @Published public var brightness: Double = 1.0
    @Published public var statusMessage: String?
    @Published public var isWriting: Bool = false
    @Published public var selectedSlot: Int = 1 // Target slot: 1, 2, or 3
    @Published public var savedSlots: Set<Int> = [1, 2, 3] // Slots written to hardware by Aperol
    @Published public var slotProfiles: [Int: HardwareSlotColor] = [:]
    @Published public var presets: [ColorPreset] = []
    @Published public var hoveredPresetId: UUID? = nil
    @Published public var editingPresetId: UUID? = nil
    @Published public private(set) var isStreaming: Bool = false
    @Published public var copiedHex: Bool = false
    public var hasUserInteractedWithColor: Bool = false

    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?
    private var isInitialized: Bool = false
    private var lastStreamTime: Date = Date.distantPast
    private var zoneWorkItem: DispatchWorkItem?

    private init() {
        loadPresets()
        loadSavedSlots()
        loadSlotProfiles()
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
            // Curated, timeless colors that look exceptional on mechanical RGB backlights
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
            // Factory defaults for all 3 hardware profiles:
            // Profile 1: Pure Red (#FF0000)
            // Profile 2: Night Vision Green (70, 255, 0)
            // Profile 3: Ice Glacier White (154, 220, 231)
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
        statusMessage = "✓ Restored & Flashed All 3 Factory Profiles"
    }

    // MARK: - HID Management

    private func isLightingInterface(_ device: IOHIDDevice) -> Bool {
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let maxOut = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        let maxFeat = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
        return usagePage == 0xFFC2 || maxOut >= 64 || maxFeat >= 64
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

        guard isLightingInterface(device) else { return }

        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            deviceName = name
        }

        self.connectedDevice = device
        self.isConnected = true
        self.statusMessage = "Connected: \(deviceName)"

        // Do NOT overwrite or touch the keyboard on attach: keyboard executes its onboard profile
        // until the user interacts or modifies color.
    }

    private func deviceDetached(_ device: IOHIDDevice) {
        if connectedDevice == device {
            connectedDevice = nil
            isConnected = false
            isInitialized = false
            statusMessage = "Device Disconnected"
        }
    }

    @discardableResult
    private func sendPacket(_ bytes: [UInt8], to device: IOHIDDevice) -> IOReturn {
        var buf = [UInt8](repeating: 0, count: 64)
        for i in 0..<min(bytes.count, 64) {
            buf[i] = bytes[i]
        }
        let reportId = CFIndex(buf[0])
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportId, buf, buf.count)
    }

    // MARK: - Device Protocol Handshake

    private func initializeDeviceIfNeeded() {
        guard let device = connectedDevice, !isInitialized else { return }
        isInitialized = true

        // 1. SpecialFunctionControl: Software control mode
        sendPacket([0x07, 0x04, 0x02], to: device)

        // 2. LightingControl: mode software 0x02, brightness 0x03 (MAX)
        var lc = [UInt8](repeating: 0, count: 64)
        lc[0] = 0x07; lc[1] = 0x05; lc[2] = 0x02; lc[3] = 0x00; lc[4] = 0x03
        sendPacket(lc, to: device)

        // 3. SetupLightingControl
        var s1 = [UInt8](repeating: 0, count: 64)
        s1[0] = 0x07; s1[1] = 0x05; s1[2] = 0x08; s1[3] = 0x00; s1[4] = 0x01
        sendPacket(s1, to: device)

        // 4. Matrix mapping: sequence covering all 150 key/zone positions
        // This includes standard matrix + Top Buttons (Profile 125, Brightness 16, WinLock 114, Logo 47/59)
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

        Thread.sleep(forTimeInterval: 0.02)
    }

    // MARK: - Volatile Real-Time Streaming (Zero EEPROM Wear)

    /// Immediately applies the color to all keys, logo, and top buttons in volatile SRAM in real time.
    /// Strictly NEVER writes to EEPROM flash memory so it cannot wear or exhaust the flash controller.
    public func applyLiveColor(_ color: Color) {
        guard let device = connectedDevice else { return }

        let now = Date()
        guard now.timeIntervalSince(lastStreamTime) > 0.02 else { return }
        lastStreamTime = now

        initializeDeviceIfNeeded()

        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = UInt8(clamping: Int((nsColor.redComponent * brightness * 255.0).rounded()))
        let g = UInt8(clamping: Int((nsColor.greenComponent * brightness * 255.0).rounded()))
        let b = UInt8(clamping: Int((nsColor.blueComponent * brightness * 255.0).rounded()))

        // Volatile SRAM stream across 168 bytes (60 + 60 + 48) covering all 150 positions
        func streamChannel(val: UInt8, channel: UInt8, finishVal: UInt8) {
            var p1 = [UInt8](repeating: val, count: 64)
            p1[0] = 0x7F; p1[1] = 0x01; p1[2] = 60; p1[3] = 0x00
            sendPacket(p1, to: device)

            var p2 = [UInt8](repeating: val, count: 64)
            p2[0] = 0x7F; p2[1] = 0x02; p2[2] = 60; p2[3] = 0x00
            sendPacket(p2, to: device)

            var p3 = [UInt8](repeating: val, count: 64)
            p3[0] = 0x7F; p3[1] = 0x03; p3[2] = 0x30; p3[3] = 0x00 // 48 bytes
            sendPacket(p3, to: device)

            var sub = [UInt8](repeating: 0, count: 64)
            sub[0] = 0x07; sub[1] = 0x28; sub[2] = channel; sub[3] = 0x03; sub[4] = finishVal
            sendPacket(sub, to: device)
        }

        streamChannel(val: r, channel: 1, finishVal: 1)
        streamChannel(val: g, channel: 2, finishVal: 1)
        streamChannel(val: b, channel: 3, finishVal: 2)

        isStreaming = true
        statusMessage = "Live Preview: \(currentHexColor)"
    }

    /// Hands the keyboard back to its own hardware firmware (stored profile, Profile and Brightness buttons work again).
    public func releaseToHardwareMode() {
        zoneWorkItem?.cancel()
        guard let device = connectedDevice, isStreaming else { return }
        sendPacket([0x07, 0x04, 0x01], to: device)
        sendPacket([0x07, 0x05, 0x01], to: device)
        isStreaming = false
        isInitialized = false
        statusMessage = "Keyboard active in standalone hardware mode"
    }

    /// Immediately switches the keyboard hardware to the given onboard slot (1, 2, or 3).
    public func switchToHardwareSlot(_ slot: Int) {
        guard let device = connectedDevice else { return }
        selectedSlot = slot
        if let slotCol = slotProfiles[slot] {
            selectedColor = slotCol.color
        }
        var sw = [UInt8](repeating: 0, count: 64)
        sw[0] = 0x07; sw[1] = 0x17; sw[2] = 0x0C; sw[3] = UInt8(slot - 1)
        sendPacket(sw, to: device)

        // Hand back to hardware mode so the slot's stored profile displays immediately
        sendPacket([0x07, 0x04, 0x01], to: device)
        sendPacket([0x07, 0x05, 0x01], to: device)
        isStreaming = false
        isInitialized = false
        statusMessage = "Switched to Hardware Profile \(slot)"
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    // MARK: - Hardware Flash (EEPROM) Commit

    /// Commits color for the target slot (or active slot), then burns ALL 3 hardware profiles
    /// cleanly into EEPROM using the official reverse-engineered NXP flash protocol:
    /// - Re-activates Slot 3 with valid bit 0x01
    /// - Sets WinLock ON/OFF custom colors for each slot (CMD 0x14 SUB 0x06 & 0x07)
    /// - Writes lghtcnt.cnt + lght_0X.d (Static effect type 0x07)
    /// - Commits RGB Matrix (CMD 0x14 SUB 0x03 & 0x04)
    /// - Commits NXP Profile Changes (CMD 0x17 SUB 0x0E)
    public func flashColorToHardware(slot: Int? = nil) {
        let targetSlot = slot ?? selectedSlot
        let nsColor = NSColor(selectedColor).usingColorSpace(.sRGB) ?? NSColor(selectedColor)
        let r = UInt8(clamping: Int((nsColor.redComponent * brightness * 255.0).rounded()))
        let g = UInt8(clamping: Int((nsColor.greenComponent * brightness * 255.0).rounded()))
        let b = UInt8(clamping: Int((nsColor.blueComponent * brightness * 255.0).rounded()))

        slotProfiles[targetSlot] = HardwareSlotColor(r: r, g: g, b: b)
        saveSlotProfiles()

        flashAllProfilesToHardware(targetSlot: targetSlot)
    }

    /// Flashes all 3 hardware profiles (Slot 1, Slot 2, Slot 3) to the keyboard flash memory.
    /// This fully restores Slot 3 so physical Profile button cycling is seamless (1 -> 2 -> 3 -> 1).
    public func flashAllProfilesToHardware(targetSlot: Int? = nil) {
        guard let device = connectedDevice else {
            statusMessage = "Device Not Found"
            return
        }

        let activeTarget = targetSlot ?? selectedSlot
        isWriting = true
        initializeDeviceIfNeeded()

        func paced(_ pkt: [UInt8], delay: TimeInterval = 0.015) {
            sendPacket(pkt, to: device)
            Thread.sleep(forTimeInterval: delay)
        }

        // 1. Set Hardware Brightness (0x03 max)
        paced([0x07, 0x05, 0x02, 0x00, 0x03])

        // 2. Register / Activate ALL 3 Hardware Profiles in Flash Memory (CMD 0x15)
        // From libLegacyProtocols.dylib (NxpHardwareProfileStorageFeature::commitProfileInfo):
        for s in 0...2 {
            var desc = [UInt8](repeating: 0, count: 64)
            desc[0] = 0x07
            desc[1] = 0x15
            desc[2] = UInt8(s) // 0, 1, 2
            desc[3] = 0x00
            withUnsafeBytes(of: Self.slotUUIDs[s].uuid) { raw in
                desc.replaceSubrange(4..<4+raw.count, with: raw)
            }
            desc[20] = 0x01
            desc[21] = 0x00
            desc[22] = 0x00
            desc[23] = 0x01 // ACTIVE / VALID BIT (Mandatory for physical button cycle)
            paced(desc)
        }

        // 3. Save Full 24-bit RGB Matrix for ALL 3 SLOTS
        for s in 1...3 {
            let col = slotProfiles[s] ?? HardwareSlotColor(r: 255, g: 0, b: 0)
            for (channel, val) in [(UInt8(1), col.r), (UInt8(2), col.g), (UInt8(3), col.b)] {
                var p1 = [UInt8](repeating: val, count: 64)
                p1[0] = 0x7F; p1[1] = 0x01; p1[2] = 60; p1[3] = 0x00
                paced(p1)

                var p2 = [UInt8](repeating: val, count: 64)
                p2[0] = 0x7F; p2[1] = 0x02; p2[2] = 60; p2[3] = 0x00
                paced(p2)

                var p3 = [UInt8](repeating: val, count: 64)
                p3[0] = 0x7F; p3[1] = 0x03; p3[2] = 48; p3[3] = 0x00
                paced(p3)

                var commit = [UInt8](repeating: 0, count: 64)
                commit[0] = 0x07; commit[1] = 0x14; commit[2] = 0x03; commit[3] = 0x01
                commit[4] = 0x01; commit[5] = UInt8(s); commit[6] = channel
                paced(commit)
            }

            // End-of-Save Packet for slot s (CMD 0x14 SUB 0x04)
            var endSave = [UInt8](repeating: 0, count: 64)
            endSave[0] = 0x07; endSave[1] = 0x14; endSave[2] = 0x04; endSave[3] = 0x01; endSave[4] = UInt8(s)
            paced(endSave)
        }

        // 4. Write WinLock ON and OFF Custom Colors for ALL 3 SLOTS (CMD 0x14 SUB 0x07 & 0x06)
        // This permanently programs the protected WinLock LED to match each profile in EEPROM!
        for s in 1...3 {
            let col = slotProfiles[s] ?? HardwareSlotColor(r: 255, g: 0, b: 0)

            // WinLock ON color
            var winLockOn = [UInt8](repeating: 0, count: 64)
            winLockOn[0] = 0x07; winLockOn[1] = 0x14; winLockOn[2] = 0x07; winLockOn[3] = 0x01
            winLockOn[4] = UInt8(s); winLockOn[5] = col.r; winLockOn[6] = col.g; winLockOn[7] = col.b
            paced(winLockOn)

            // WinLock OFF color
            var winLockOff = [UInt8](repeating: 0, count: 64)
            winLockOff[0] = 0x07; winLockOff[1] = 0x14; winLockOff[2] = 0x06; winLockOff[3] = 0x01
            winLockOff[4] = UInt8(s); winLockOff[5] = col.r; winLockOff[6] = col.g; winLockOff[7] = col.b
            paced(winLockOff)
        }

        // 5. Official NXP Commit Profile Changes (CMD 0x17 SUB 0x0E)
        // Flushes non-volatile buffers and commits changes to hardware flash
        var nlpCommit = [UInt8](repeating: 0, count: 64)
        nlpCommit[0] = 0x07; nlpCommit[1] = 0x17; nlpCommit[2] = 0x0E; nlpCommit[3] = 0x00
        paced(nlpCommit, delay: 0.08)

        // Allow MCU flash write cycle to settle
        Thread.sleep(forTimeInterval: 0.12)

        // 6. Switch active slot to targetSlot (0-based)
        paced([0x07, 0x17, 0x0C, UInt8(activeTarget - 1)])
        Thread.sleep(forTimeInterval: 0.05)

        // 7. Return to standalone hardware mode
        paced([0x07, 0x04, 0x01])
        paced([0x07, 0x05, 0x01])

        isStreaming = false
        isInitialized = false
        for s in 1...3 { markSlotSaved(s) }
        isWriting = false
        statusMessage = "✓ Written to Hardware Memory (All 3 Profiles & WinLock Active)"
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    /// Commits color to hardware memory and immediately terminates the app (0 MB residual RAM).
    public func flashAndQuit() {
        flashColorToHardware(slot: selectedSlot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            NSApplication.shared.terminate(nil)
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
