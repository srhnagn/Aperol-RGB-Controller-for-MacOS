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
/// and writes directly to hardware memory via OpenRGB lght_0X.d filesystem stream + NXP HWCLR command (FIELD 0x14)
/// covering all 150 positions: all keys, logo, Profile (125), Brightness (16), and WinLock (114).
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

    private static let masterProfileUUID = UUID(uuidString: "C085A100-0000-0000-0000-000000000000")!
    private static let slotUUIDs: [UUID] = [
        UUID(uuidString: "C085A101-0000-0000-0000-000000000001")!,
        UUID(uuidString: "C085A102-0000-0000-0000-000000000002")!,
        UUID(uuidString: "C085A103-0000-0000-0000-000000000003")!
    ]

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var deviceName: String = "Corsair K70 RGB MK.2"
    @Published public var selectedColor: Color = Color(red: 240.0 / 255.0, green: 60.0 / 255.0, blue: 0.0)
    @Published public var brightness: Double = 1.0
    @Published public var statusMessage: String?
    @Published public var isWriting: Bool = false
    @Published public var selectedSlot: Int = 1 // Target slot: 1, 2, or 3
    @Published public var savedSlots: Set<Int> = [] // Slots written to hardware by Aperol
    @Published public var slotProfiles: [Int: HardwareSlotColor] = [:]
    @Published public var presets: [ColorPreset] = []
    @Published public var hoveredPresetId: UUID? = nil
    @Published public var editingPresetId: UUID? = nil
    @Published public private(set) var isStreaming: Bool = false
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
        if let data = defaults.data(forKey: "AperolColorPresets_v2"),
           let decoded = try? JSONDecoder().decode([ColorPreset].self, from: data),
           !decoded.isEmpty {
            self.presets = decoded
        } else {
            // Default initial presets with exact calibrated colors
            self.presets = [
                ColorPreset(name: "Pure Red", red: 1.0, green: 0.0, blue: 0.0),
                ColorPreset(name: "Night Vision Green", red: 70.0 / 255.0, green: 255.0 / 255.0, blue: 0.0), // 70, 255, 0
                ColorPreset(name: "Ice White", red: 154.0 / 255.0, green: 220.0 / 255.0, blue: 231.0 / 255.0),
                ColorPreset(name: "Aperol Spritz", red: 240.0 / 255.0, green: 60.0 / 255.0, blue: 0.0),
                ColorPreset(name: "Samogon", red: 0.0, green: 231.0 / 255.0, blue: 79.0 / 255.0),
                ColorPreset(name: "Amber Gold", red: 1.0, green: 160.0 / 255.0, blue: 0.0),
                ColorPreset(name: "Cyber Magenta", red: 217.0 / 255.0, green: 70.0 / 255.0, blue: 239.0 / 255.0),
                ColorPreset(name: "Stealth (Off)", red: 0.0, green: 0.0, blue: 0.0)
            ]
            savePresets()
        }
    }

    public func savePresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: "AperolColorPresets_v2")
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
        UserDefaults.standard.removeObject(forKey: "AperolColorPresets_v2")
        loadPresets()
    }

    private func loadSavedSlots() {
        if let array = UserDefaults.standard.array(forKey: "AperolSavedSlots") as? [Int] {
            self.savedSlots = Set(array)
        }
    }

    private func markSlotSaved(_ slot: Int) {
        savedSlots.insert(slot)
        UserDefaults.standard.set(Array(savedSlots), forKey: "AperolSavedSlots")
    }

    private func loadSlotProfiles() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "AperolSlotProfiles_v1"),
           let decoded = try? JSONDecoder().decode([Int: HardwareSlotColor].self, from: data),
           !decoded.isEmpty {
            self.slotProfiles = decoded
        } else {
            // Default 3 hardware profiles:
            // Profile 1: Pure Red
            // Profile 2: Night Vision Green (70, 255, 0)
            // Profile 3: Ice White (154, 220, 231)
            self.slotProfiles = [
                1: HardwareSlotColor(r: 255, g: 0, b: 0),
                2: HardwareSlotColor(r: 70, g: 255, b: 0),
                3: HardwareSlotColor(r: 154, g: 220, b: 231)
            ]
            saveSlotProfiles()
        }
    }

    private func saveSlotProfiles() {
        if let encoded = try? JSONEncoder().encode(slotProfiles) {
            UserDefaults.standard.set(encoded, forKey: "AperolSlotProfiles_v1")
        }
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
        self.statusMessage = "Connected: \(deviceName) (3 Onboard Profiles)"

        // Do NOT touch or overwrite the keyboard on attach: the keyboard continues executing its stored profile
        // until the user explicitly selects or modifies a color.
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

        // Allow MCU to settle
        Thread.sleep(forTimeInterval: 0.02)
    }

    // MARK: - Volatile Real-Time Streaming (Zero EEPROM Writes)

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

    /// Hands the keyboard back to its own firmware (stored profile, Profile and Brightness buttons work again).
    public func releaseToHardwareMode() {
        zoneWorkItem?.cancel()
        guard let device = connectedDevice, isStreaming else { return }
        sendPacket([0x07, 0x04, 0x01], to: device)
        sendPacket([0x07, 0x05, 0x01], to: device)
        isStreaming = false
        isInitialized = false
        statusMessage = "Keyboard released to hardware firmware"
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

        // Hand back to hardware mode so the slot's stored profile is displayed immediately
        sendPacket([0x07, 0x04, 0x01], to: device)
        sendPacket([0x07, 0x05, 0x01], to: device)
        isStreaming = false
        isInitialized = false
        statusMessage = "Switched to Hardware Profile \(slot)"
    }

    // MARK: - Hardware Flash (EEPROM) Commit (Manual Only)

    /// Commits color to the keyboard's onboard memory for the selected slot (1, 2, or 3)
    /// while preserving all 3 hardware profiles so the physical Profile switch button continues cycling seamlessly.
    public func flashColorToHardware(slot: Int? = nil) {
        guard let device = connectedDevice else {
            statusMessage = "Device Not Found"
            return
        }
        let targetSlot = slot ?? selectedSlot
        isWriting = true
        initializeDeviceIfNeeded()

        let nsColor = NSColor(selectedColor).usingColorSpace(.sRGB) ?? NSColor(selectedColor)
        let red = UInt8(clamping: Int((nsColor.redComponent * brightness * 255.0).rounded()))
        let green = UInt8(clamping: Int((nsColor.greenComponent * brightness * 255.0).rounded()))
        let blue = UInt8(clamping: Int((nsColor.blueComponent * brightness * 255.0).rounded()))

        // Update stored profile color for target slot
        slotProfiles[targetSlot] = HardwareSlotColor(r: red, g: green, b: blue)
        saveSlotProfiles()

        func paced(_ pkt: [UInt8], delay: TimeInterval = 0.015) {
            sendPacket(pkt, to: device)
            Thread.sleep(forTimeInterval: delay)
        }

        // 1. Set Hardware Brightness (0x03 max)
        paced([0x07, 0x05, 0x02, 0x00, 0x03])

        // 2. Save Mode Names (0: Master, 1: Slot 1, 2: Slot 2, 3: Slot 3)
        func sendModeName(slot: UInt8, name: String) {
            var namePkt = [UInt8](repeating: 0, count: 64)
            namePkt[0] = 0x07; namePkt[1] = 0x16; namePkt[2] = 0x01; namePkt[3] = slot
            if let nameData = name.data(using: .utf16LittleEndian) {
                nameData.copyBytes(to: &namePkt[4], count: min(nameData.count, 56))
            }
            paced(namePkt)
        }
        sendModeName(slot: 0, name: "K70 MK.2")
        sendModeName(slot: 1, name: "Profile 1")
        sendModeName(slot: 2, name: "Profile 2")
        sendModeName(slot: 3, name: "Profile 3")

        // 3. Save Mode 0 (Master Descriptor with total modecount = 3, active slot, max modes = 3)
        var p0 = [UInt8](repeating: 0, count: 64)
        p0[0] = 0x07; p0[1] = 0x15; p0[2] = 0x01; p0[3] = 0x00
        withUnsafeBytes(of: Self.masterProfileUUID.uuid) { raw in
            p0.replaceSubrange(4..<4+raw.count, with: raw)
        }
        p0[24] = 0x03; p0[25] = 0x00; p0[26] = 0x00; p0[27] = 0x00 // Total modes = 3
        p0[28] = UInt8(targetSlot - 1); p0[29] = 0x00 // Active slot index (0..2)
        p0[30] = 0x03; p0[31] = 0x00 // Max modes = 3
        paced(p0)

        // 4. Save Mode 1, 2, 3 IDs
        for s in 1...3 {
            var idPkt = [UInt8](repeating: 0, count: 64)
            idPkt[0] = 0x07; idPkt[1] = 0x15; idPkt[2] = 0x01; idPkt[3] = UInt8(s)
            withUnsafeBytes(of: Self.slotUUIDs[s - 1].uuid) { raw in
                idPkt.replaceSubrange(4..<4+raw.count, with: raw)
            }
            paced(idPkt)
        }

        // 5. Write 3-Profile Directory Table (0x07, 0x17, 0x04, 0x00) with all 3 slots
        var dirPkt = [UInt8](repeating: 0, count: 64)
        dirPkt[0] = 0x07; dirPkt[1] = 0x17; dirPkt[2] = 0x04; dirPkt[3] = 0x00
        // Slot 1
        withUnsafeBytes(of: Self.slotUUIDs[0].uuid) { raw in dirPkt.replaceSubrange(4..<4+raw.count, with: raw) }
        dirPkt[20] = 0x19; dirPkt[21] = 0x00; dirPkt[22] = 0x00; dirPkt[23] = 0x00
        // Slot 2
        withUnsafeBytes(of: Self.slotUUIDs[1].uuid) { raw in dirPkt.replaceSubrange(24..<24+raw.count, with: raw) }
        dirPkt[40] = 0x09; dirPkt[41] = 0x00; dirPkt[42] = 0x00; dirPkt[43] = 0x00
        // Slot 3
        withUnsafeBytes(of: Self.slotUUIDs[2].uuid) { raw in dirPkt.replaceSubrange(44..<44+raw.count, with: raw) }
        dirPkt[60] = 0x01; dirPkt[61] = 0x00; dirPkt[62] = 0x00; dirPkt[63] = 0x00
        paced(dirPkt)

        // 6. Write Hardware Files "lght_0X.d" for ALL 3 slots (populates hardware playback engine)
        for s in 1...3 {
            let col = slotProfiles[s] ?? HardwareSlotColor(r: 255, g: 0, b: 0)
            var fOpen = [UInt8](repeating: 0, count: 64)
            fOpen[0] = 0x07; fOpen[1] = 0x17; fOpen[2] = 0x05; fOpen[3] = 0x00
            let filename = "lght_0\(s - 1).d"
            for (i, b) in filename.utf8.enumerated() {
                fOpen[4 + i] = b
            }
            paced(fOpen)

            var streamPkt = [UInt8](repeating: 0, count: 64)
            streamPkt[0] = 0x7F; streamPkt[1] = 0x01; streamPkt[2] = 0x0D; streamPkt[3] = 0x00
            streamPkt[4] = 0x00 // static
            streamPkt[5] = 0x02 // speed
            streamPkt[6] = 0x03 // mode specific
            streamPkt[7] = 0x00; streamPkt[8] = 0x00
            streamPkt[9] = col.r; streamPkt[10] = col.g; streamPkt[11] = col.b; streamPkt[12] = 0xFF
            streamPkt[13] = col.r; streamPkt[14] = col.g; streamPkt[15] = col.b; streamPkt[16] = 0xFF
            paced(streamPkt)

            paced([0x07, 0x17, 0x09])
            paced([0x07, 0x17, 0x08])
        }

        // 7. Save Full RGB Matrix for targetSlot (168 bytes across p1, p2, p3 covering all 150 keys and logo)
        for (channel, val) in [(UInt8(1), red), (UInt8(2), green), (UInt8(3), blue)] {
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
            commit[4] = 0x01; commit[5] = UInt8(targetSlot); commit[6] = channel
            paced(commit)
        }

        // 8. End-of-Save Packet
        paced([0x07, 0x14, 0x04, 0x01, 0x01])

        // 9. Switch active slot to targetSlot
        paced([0x07, 0x17, 0x0C, UInt8(targetSlot - 1)])

        Thread.sleep(forTimeInterval: 0.100)

        // 10. Return to hardware mode so keyboard executes stored profile
        paced([0x07, 0x04, 0x01])
        paced([0x07, 0x05, 0x01])

        isStreaming = false
        isInitialized = false
        markSlotSaved(targetSlot)
        isWriting = false
        statusMessage = "✓ Written to Profile \(targetSlot) Memory (All 3 Profiles Active)"
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    /// Commits color to hardware memory and immediately terminates the app (0 MB residual RAM).
    public func flashAndQuit() {
        flashColorToHardware(slot: selectedSlot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
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
