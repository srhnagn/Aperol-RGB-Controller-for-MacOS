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

/// Native IOKit USB HID controller for Corsair K70 MK.2 RGB keyboard.
/// Writes directly to the hardware onboard EEPROM/flash memory (`lght_00.d`, `lght_01.d`, `lght_02.d`)
/// covering all keys, logo, and top control buttons (Profile, Brightness, WinLock).
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

    public static let maxOnboardSlots: Int = 3

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var deviceName: String = "Corsair K70 RGB MK.2"
    @Published public var selectedColor: Color = Color(red: 240.0 / 255.0, green: 60.0 / 255.0, blue: 0.0)
    @Published public var brightness: Double = 1.0
    @Published public var statusMessage: String?
    @Published public var isWriting: Bool = false
    @Published public var selectedSlot: Int = 1 // Target slot: 1, 2, or 3
    @Published public var savedSlots: Set<Int> = [1] // Slots written to hardware
    @Published public var presets: [ColorPreset] = []
    @Published public var hoveredPresetId: UUID? = nil

    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?
    private var isInitialized: Bool = false
    private var lastStreamTime: Date = Date.distantPast

    private init() {
        loadPresets()
        loadSavedSlots()
        setupHIDManager()
    }

    // MARK: - Presets Storage

    private func loadPresets() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "AperolColorPresets"),
           let decoded = try? JSONDecoder().decode([ColorPreset].self, from: data) {
            self.presets = decoded
        } else {
            // Default initial presets with exact calibrated colors
            self.presets = [
                ColorPreset(name: "Pure Red", red: 1.0, green: 0.0, blue: 0.0),
                ColorPreset(name: "Ice White", red: 154.0 / 255.0, green: 220.0 / 255.0, blue: 231.0 / 255.0),
                ColorPreset(name: "Night Vision Green", red: 70.0 / 255.0, green: 255.0 / 255.0, blue: 0.0), // 70, 255, 0
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
            UserDefaults.standard.set(encoded, forKey: "AperolColorPresets")
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

    public func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }

    public func restoreDefaultPresets() {
        UserDefaults.standard.removeObject(forKey: "AperolColorPresets")
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

        // Initialize hardware mapping into software mode passively without forcing default color
        initializeDeviceIfNeeded()
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
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buf, 64)
    }

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
        // This includes standard matrix + Top Buttons (Profile 125, Brightness 16, WinLock 114, Logo 59)
        let skipped: Set<UInt8> = [0x3F, 0x41, 0x42, 0x50, 0x53, 0x55, 0x6F, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0x80, 0x81]
        var identifier: UInt8 = 0
        for _ in 0..<5 {
            var pkt = [UInt8](repeating: 0, count: 64)
            pkt[0] = 0x07; pkt[1] = 0x40; pkt[2] = 0x1E
            for j in 0..<30 {
                while skipped.contains(identifier) {
                    identifier &+= 1
                }
                pkt[4 + 2 * j] = identifier
                pkt[4 + 2 * j + 1] = 0xC0
                identifier &+= 1
            }
            sendPacket(pkt, to: device)
        }
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

        // Volatile SRAM stream across 150 keys (60 + 60 + 30)
        func streamChannel(val: UInt8, channel: UInt8, finishVal: UInt8) {
            var p1 = [UInt8](repeating: val, count: 64)
            p1[0] = 0x7F; p1[1] = 0x01; p1[2] = 60; p1[3] = 0x00
            sendPacket(p1, to: device)

            var p2 = [UInt8](repeating: val, count: 64)
            p2[0] = 0x7F; p2[1] = 0x02; p2[2] = 60; p2[3] = 0x00
            sendPacket(p2, to: device)

            var p3 = [UInt8](repeating: val, count: 64)
            p3[0] = 0x7F; p3[1] = 0x03; p3[2] = 30; p3[3] = 0x00
            sendPacket(p3, to: device)

            var sub = [UInt8](repeating: 0, count: 64)
            sub[0] = 0x07; sub[1] = 0x28; sub[2] = channel; sub[3] = 0x03; sub[4] = finishVal
            sendPacket(sub, to: device)
        }

        streamChannel(val: r, channel: 1, finishVal: 1)
        streamChannel(val: g, channel: 2, finishVal: 1)
        streamChannel(val: b, channel: 3, finishVal: 2)

        statusMessage = "Live Preview: \(currentHexColor)"
    }

    // MARK: - Hardware Flash (EEPROM) Commit (Manual Only)

    /// Commits the active color to the chosen onboard hardware profile slot (`lght_00.d`, `lght_01.d`, or `lght_02.d`).
    public func flashColorToHardware(slot: Int? = nil) {
        guard let device = connectedDevice else {
            statusMessage = "Device Not Found"
            return
        }

        let targetSlot = slot ?? selectedSlot
        isWriting = true

        let nsColor = NSColor(selectedColor).usingColorSpace(.sRGB) ?? NSColor(selectedColor)
        let red = UInt8(clamping: Int((nsColor.redComponent * brightness * 255.0).rounded()))
        let green = UInt8(clamping: Int((nsColor.greenComponent * brightness * 255.0).rounded()))
        let blue = UInt8(clamping: Int((nsColor.blueComponent * brightness * 255.0).rounded()))

        // 1. Set Hardware Brightness
        let hwBrightness: UInt8 = (red == 0 && green == 0 && blue == 0) ? 0 : 3
        var bPkt = [UInt8](repeating: 0, count: 64)
        bPkt[0] = 0x07; bPkt[1] = 0x05; bPkt[2] = 0x02; bPkt[4] = hwBrightness
        sendPacket(bPkt, to: device)

        // 2. Target Profile Filename: "lght_00.d", "lght_01.d", or "lght_02.d"
        let slotIndexChar: UInt8 = UInt8(0x30 + ((targetSlot - 1) % 3)) // '0', '1', or '2'
        var namePkt = [UInt8](repeating: 0, count: 64)
        namePkt[0] = 0x07; namePkt[1] = 0x17; namePkt[2] = 0x05
        let nameBytes: [UInt8] = [0x6C, 0x67, 0x68, 0x74, 0x5F, 0x30, slotIndexChar, 0x2E, 0x64] // "lght_0X.d"
        for (idx, b) in nameBytes.enumerated() {
            namePkt[4 + idx] = b
        }
        sendPacket(namePkt, to: device)

        // 3. Hardware ColorShift Static Mode Packet
        var modePkt = [UInt8](repeating: 0, count: 64)
        modePkt[0] = 0x7F; modePkt[1] = 0x01; modePkt[2] = 0x0D
        modePkt[4] = 0x00 // Mode 0x00 = ColorShift
        modePkt[5] = 0x01 // Speed
        modePkt[6] = 0x03 // MODE_COLORS_MODE_SPECIFIC
        modePkt[7] = 0x00 // Direction
        modePkt[9] = red; modePkt[10] = green; modePkt[11] = blue; modePkt[12] = 0xFF
        modePkt[13] = red; modePkt[14] = green; modePkt[15] = blue; modePkt[16] = 0xFF
        sendPacket(modePkt, to: device)

        var stop1 = [UInt8](repeating: 0, count: 64)
        stop1[0] = 0x07; stop1[1] = 0x17; stop1[2] = 0x09
        sendPacket(stop1, to: device)

        var stop2 = [UInt8](repeating: 0, count: 64)
        stop2[0] = 0x07; stop2[1] = 0x17; stop2[2] = 0x08
        sendPacket(stop2, to: device)

        // 4. Hardware Zone Profile Colors for top buttons and auxiliary zones
        for zone: UInt8 in [0x01, 0x02, 0x03, 0x04, 0x05, 0x11, 0x12, 0x13, 0x14, 0x15] {
            var zPkt = [UInt8](repeating: 0, count: 64)
            zPkt[0] = 0x07; zPkt[1] = 0x13; zPkt[2] = zone; zPkt[3] = 0x01
            zPkt[4] = red; zPkt[5] = green; zPkt[6] = blue
            sendPacket(zPkt, to: device)
        }

        // 5. Switch to Hardware Lighting Mode
        var hwPkt = [UInt8](repeating: 0, count: 64)
        hwPkt[0] = 0x07; hwPkt[1] = 0x04; hwPkt[2] = 0x01
        sendPacket(hwPkt, to: device)

        var hwLight = [UInt8](repeating: 0, count: 64)
        hwLight[0] = 0x07; hwLight[1] = 0x05; hwLight[2] = 0x01
        sendPacket(hwLight, to: device)

        markSlotSaved(targetSlot)
        isWriting = false
        statusMessage = "✓ Written to Hardware Profile Slot \(targetSlot) (EEPROM)"
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
