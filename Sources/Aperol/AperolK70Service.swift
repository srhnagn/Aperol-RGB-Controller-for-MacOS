// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import AppKit
import Foundation
import IOKit
import IOKit.hid
import SwiftUI

/// Native IOKit USB HID controller for Corsair K70 MK.2 RGB keyboard.
/// Writes directly to the hardware onboard EEPROM/flash memory (`lght_00.d`)
/// covering all keys, logo, and the top control buttons (Profile, Brightness, WinLock).
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

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var deviceName: String = "Corsair K70 RGB MK.2"
    @Published public var selectedColor: Color = Color(red: 1.0, green: 0.37, blue: 0.0) // Aperol Spritz signature
    @Published public var brightness: Double = 1.0
    @Published public var statusMessage: String?
    @Published public var isWriting: Bool = false

    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?
    private var isInitialized: Bool = false

    private init() {
        setupHIDManager()
    }

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
        self.statusMessage = "Klavye Hazır (\(deviceName))"

        initializeDeviceIfNeeded()
    }

    private func deviceDetached(_ device: IOHIDDevice) {
        if connectedDevice == device {
            connectedDevice = nil
            isConnected = false
            isInitialized = false
            statusMessage = "Klavye Bağlantısı Kesildi"
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

        // 1. SpecialFunctionControl
        sendPacket([0x07, 0x04, 0x02], to: device)

        // 2. LightingControl: mode software 0x02, brightness 0x03 (MAX)
        var lc = [UInt8](repeating: 0, count: 64)
        lc[0] = 0x07; lc[1] = 0x05; lc[2] = 0x02; lc[3] = 0x00; lc[4] = 0x03
        sendPacket(lc, to: device)

        // 3. SetupLightingControl
        var s1 = [UInt8](repeating: 0, count: 64)
        s1[0] = 0x07; s1[1] = 0x05; s1[2] = 0x08; s1[3] = 0x00; s1[4] = 0x01
        sendPacket(s1, to: device)

        // 4. Matrix mapping: sequence of 120 key IDs
        let skipped: Set<UInt8> = [0x3F, 0x41, 0x42, 0x50, 0x53, 0x55, 0x6F, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0x80, 0x81]
        var identifier: UInt8 = 0
        for _ in 0..<4 {
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

    /// Writes the selected color to the keyboard's internal hardware flash/EEPROM memory
    /// and updates the live LED state across all keys and top utility buttons.
    public func flashColorToHardware(red: UInt8, green: UInt8, blue: UInt8) {
        guard let device = connectedDevice else {
            statusMessage = "Corsair Klavye Bulunamadı"
            return
        }

        isWriting = true

        // 1. Direct Live Stream to all 144 key positions (including top buttons: 16, 114, 125, 47, 59)
        func streamChannel(val: UInt8, channel: UInt8, finishVal: UInt8) {
            var p1 = [UInt8](repeating: val, count: 64)
            p1[0] = 0x7F; p1[1] = 0x01; p1[2] = 60; p1[3] = 0x00
            sendPacket(p1, to: device)

            var p2 = [UInt8](repeating: val, count: 64)
            p2[0] = 0x7F; p2[1] = 0x02; p2[2] = 60; p2[3] = 0x00
            sendPacket(p2, to: device)

            var p3 = [UInt8](repeating: val, count: 64)
            p3[0] = 0x7F; p3[1] = 0x03; p3[2] = 24; p3[3] = 0x00
            sendPacket(p3, to: device)

            var sub = [UInt8](repeating: 0, count: 64)
            sub[0] = 0x07; sub[1] = 0x28; sub[2] = channel; sub[3] = 0x03; sub[4] = finishVal
            sendPacket(sub, to: device)
        }

        streamChannel(val: red, channel: 1, finishVal: 1)
        streamChannel(val: green, channel: 2, finishVal: 1)
        streamChannel(val: blue, channel: 3, finishVal: 2)

        // 2. Write to Hardware EEPROM / Flash Profile "lght_00.d"
        let hwBrightness: UInt8 = (red == 0 && green == 0 && blue == 0) ? 0 : 3
        var bPkt = [UInt8](repeating: 0, count: 64)
        bPkt[0] = 0x07; bPkt[1] = 0x05; bPkt[2] = 0x02; bPkt[4] = hwBrightness
        sendPacket(bPkt, to: device)

        var namePkt = [UInt8](repeating: 0, count: 64)
        namePkt[0] = 0x07; namePkt[1] = 0x17; namePkt[2] = 0x05
        let nameBytes: [UInt8] = [0x6C, 0x67, 0x68, 0x74, 0x5F, 0x30, 0x30, 0x2E, 0x64] // "lght_00.d"
        for (idx, b) in nameBytes.enumerated() {
            namePkt[4 + idx] = b
        }
        sendPacket(namePkt, to: device)

        var modePkt = [UInt8](repeating: 0, count: 64)
        modePkt[0] = 0x7F; modePkt[1] = 0x01; modePkt[2] = 0x0D
        modePkt[4] = 0x00 // Mode 0x00 = ColorShift
        modePkt[5] = 0x01 // speed
        modePkt[6] = 0x03 // MODE_COLORS_MODE_SPECIFIC
        modePkt[7] = 0x00 // direction
        modePkt[9] = red; modePkt[10] = green; modePkt[11] = blue; modePkt[12] = 0xFF
        modePkt[13] = red; modePkt[14] = green; modePkt[15] = blue; modePkt[16] = 0xFF
        sendPacket(modePkt, to: device)

        var stop1 = [UInt8](repeating: 0, count: 64)
        stop1[0] = 0x07; stop1[1] = 0x17; stop1[2] = 0x09
        sendPacket(stop1, to: device)

        var stop2 = [UInt8](repeating: 0, count: 64)
        stop2[0] = 0x07; stop2[1] = 0x17; stop2[2] = 0x08
        sendPacket(stop2, to: device)

        var hwPkt = [UInt8](repeating: 0, count: 64)
        hwPkt[0] = 0x07; hwPkt[1] = 0x04; hwPkt[2] = 0x01
        sendPacket(hwPkt, to: device)

        var hwLight = [UInt8](repeating: 0, count: 64)
        hwLight[0] = 0x07; hwLight[1] = 0x05; hwLight[2] = 0x01
        sendPacket(hwLight, to: device)

        isWriting = false
        statusMessage = "✓ Donanım Belleğine (EEPROM) Başarıyla Yazıldı!"
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    /// Flashes the currently selectedColor.
    public func flashCurrentColor() {
        let nsColor = NSColor(selectedColor).usingColorSpace(.sRGB) ?? NSColor(selectedColor)
        let r = UInt8(clamping: Int((nsColor.redComponent * brightness * 255.0).rounded()))
        let g = UInt8(clamping: Int((nsColor.greenComponent * brightness * 255.0).rounded()))
        let b = UInt8(clamping: Int((nsColor.blueComponent * brightness * 255.0).rounded()))
        flashColorToHardware(red: r, green: g, blue: b)
    }

    /// Writes to hardware flash memory and immediately terminates the app (0 MB RAM footprint).
    public func flashAndQuit() {
        flashCurrentColor()
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
