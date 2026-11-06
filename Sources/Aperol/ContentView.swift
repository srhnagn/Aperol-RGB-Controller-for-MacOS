// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import SwiftUI

struct ContentView: View {
    @ObservedObject private var service = AperolK70Service.shared

    private let aperolOrange = Color(red: 242.0 / 255.0, green: 107.0 / 255.0, blue: 30.0 / 255.0) // #F26B1E
    private let cardBackground = Color(red: 22.0 / 255.0, green: 24.0 / 255.0, blue: 28.0 / 255.0)
    private let cardBorder = Color.white.opacity(0.07)

    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Header
            headerView

            // MARK: - Section 1: 3 Onboard Hardware Profiles
            hardwareSlotsSection

            // MARK: - Section 2: Color & Real-Time Adjuster
            colorAdjusterSection

            // MARK: - Section 3: Preset Palettes
            presetsSection

            Spacer(minLength: 4)

            // MARK: - Status Toast
            if let msg = service.statusMessage {
                statusBanner(msg: msg)
            }

            // MARK: - Bottom Actions
            bottomActionsView
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 17.0 / 255.0, green: 18.0 / 255.0, blue: 21.0 / 255.0),
                    Color(red: 12.0 / 255.0, green: 13.0 / 255.0, blue: 15.0 / 255.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            // App Icon
            if let iconUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let nsImg = NSImage(contentsOf: iconUrl) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(aperolOrange.opacity(0.35), lineWidth: 1))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(cardBackground)
                        .frame(width: 38, height: 38)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(aperolOrange.opacity(0.5), lineWidth: 1))
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(aperolOrange)
                }
            }

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Aperol")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)

                    Text("K70 MK.2")
                        .font(.system(size: 9.5, weight: .bold).monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(aperolOrange.opacity(0.18))
                        .foregroundStyle(aperolOrange)
                        .clipShape(Capsule())
                }

                Text("Hardware EEPROM Controller")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.6))
            }

            Spacer()

            // Device Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(service.isConnected ? Color(red: 0.2, green: 0.85, blue: 0.4) : Color(red: 0.9, green: 0.25, blue: 0.25))
                    .frame(width: 7, height: 7)

                Text(service.isConnected ? "K70 MK.2" : "Disconnected")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(service.isConnected ? Color(white: 0.85) : Color(white: 0.5))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(cardBorder, lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    // MARK: - Hardware Profiles Section

    private var hardwareSlotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(aperolOrange)

                    Text("ONBOARD HARDWARE PROFILES")
                        .font(.system(size: 9.5, weight: .bold).monospaced())
                        .foregroundStyle(Color(white: 0.55))
                }

                Spacer()

                Text("Active: Profile \(service.selectedSlot)")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(aperolOrange)
            }

            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { slot in
                    slotCard(slot: slot)
                }
            }
        }
        .padding(11)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func slotCard(slot: Int) -> some View {
        let isSelected = service.selectedSlot == slot
        let slotColor = service.slotProfiles[slot]?.color ?? Color.secondary
        let hex = service.slotProfiles[slot]?.hexString ?? "#------"

        return Button {
            service.switchToHardwareSlot(slot)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isSelected ? aperolOrange : Color.white.opacity(0.08))
                            .frame(width: 20, height: 20)
                        Text("\(slot)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isSelected ? .black : Color(white: 0.75))
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(aperolOrange)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(slotColor)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Profile \(slot)")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(isSelected ? .white : Color(white: 0.85))

                        Text(hex)
                            .font(.system(size: 8.5, weight: .medium).monospaced())
                            .foregroundStyle(isSelected ? aperolOrange : Color(white: 0.5))
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? aperolOrange.opacity(0.10) : Color.white.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? aperolOrange.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Color Adjuster Section

    private var colorAdjusterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(aperolOrange)

                    Text("COLOR & REAL-TIME PREVIEW")
                        .font(.system(size: 9.5, weight: .bold).monospaced())
                        .foregroundStyle(Color(white: 0.55))
                }

                Spacer()

                Text("SRAM Live Stream (0 Flash Wear)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(aperolOrange.opacity(0.85))
            }

            HStack(spacing: 12) {
                // Color Picker and Swatch
                ColorPicker("", selection: $service.selectedColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 28)
                    .onChange(of: service.selectedColor) { _, newColor in
                        guard service.hasUserInteractedWithColor else { return }
                        service.applyLiveColor(newColor)
                    }

                // Swatch & Hex Code
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(service.selectedColor)
                        .frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2), lineWidth: 0.5))

                    Text(service.currentHexColor)
                        .font(.system(size: 12, weight: .bold).monospaced())
                        .foregroundStyle(.white)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(service.currentHexColor, forType: .string)
                        service.copiedHex = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            service.copiedHex = false
                        }
                    } label: {
                        Image(systemName: service.copiedHex ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5))
                            .foregroundStyle(service.copiedHex ? Color.green : Color(white: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Copy Hex Color")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                // Re-sync Button
                Button {
                    service.hasUserInteractedWithColor = true
                    service.applyLiveColor(service.selectedColor)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Re-sync")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .foregroundStyle(Color(white: 0.85))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Re-stream volatile preview color to all keys and top buttons")

                // Release Button
                Button {
                    service.releaseToHardwareMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Release")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .foregroundStyle(Color(white: 0.85))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Hand control back to keyboard hardware firmware so physical buttons function")
            }

            // Brightness Slider
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.5))

                Slider(value: $service.brightness, in: 0.0...1.0, step: 0.05)
                    .tint(aperolOrange)
                    .onChange(of: service.brightness) { _, _ in
                        guard service.hasUserInteractedWithColor else { return }
                        service.applyLiveColor(service.selectedColor)
                    }

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(aperolOrange)

                Text("\(Int((service.brightness * 100).rounded()))%")
                    .font(.system(size: 10, weight: .bold).monospaced())
                    .foregroundStyle(Color(white: 0.75))
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.top, 2)
        }
        .padding(11)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Preset Palettes Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(aperolOrange)

                    Text("PRESET COLOR PALETTES")
                        .font(.system(size: 9.5, weight: .bold).monospaced())
                        .foregroundStyle(Color(white: 0.55))
                }

                Spacer()

                Button {
                    service.addCurrentColorAsPreset()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Add Active")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(aperolOrange.opacity(0.15))
                    .foregroundStyle(aperolOrange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Add the currently selected color as a preset")

                Button {
                    service.restoreDefaultPresets()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.45))
                }
                .buttonStyle(.plain)
                .help("Restore factory color presets")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 102))], spacing: 6) {
                ForEach(service.presets) { preset in
                    presetChip(preset: preset)
                }
            }
        }
        .padding(11)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func presetChip(preset: ColorPreset) -> some View {
        let isHovered = service.hoveredPresetId == preset.id
        let isEditing = service.editingPresetId == preset.id

        return VStack(spacing: 3) {
            HStack(spacing: 5) {
                Button {
                    service.hasUserInteractedWithColor = true
                    service.selectedColor = preset.color
                    service.applyLiveColor(preset.color)
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))

                        Text(preset.name)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color(white: 0.85))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if isHovered || isEditing {
                    Button {
                        service.editingPresetId = isEditing ? nil : preset.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(isEditing ? aperolOrange : Color(white: 0.55))
                    }
                    .buttonStyle(.plain)

                    if service.presets.count > 1 {
                        Button {
                            service.deletePreset(id: preset.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5))
                                .foregroundStyle(Color(white: 0.45))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isEditing {
                VStack(spacing: 4) {
                    TextField("Name", text: Binding(
                        get: { preset.name },
                        set: { service.renamePreset(id: preset.id, name: $0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5))
                    .padding(3)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    HStack(spacing: 4) {
                        ColorPicker("", selection: Binding(
                            get: { preset.color },
                            set: { service.setPresetColor(id: preset.id, color: $0) }
                        ), supportsOpacity: false)
                        .labelsHidden()

                        Spacer()

                        Button("Use Active") {
                            service.setPresetColor(id: preset.id, color: service.selectedColor)
                        }
                        .font(.system(size: 8.5, weight: .bold))
                        .buttonStyle(.plain)
                        .foregroundStyle(aperolOrange)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.white.opacity(isHovered || isEditing ? 0.06 : 0.025))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isEditing ? aperolOrange.opacity(0.4) : Color.white.opacity(0.04), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            if hovering { service.hoveredPresetId = preset.id }
            else if service.hoveredPresetId == preset.id { service.hoveredPresetId = nil }
        }
    }

    // MARK: - Status Toast

    private func statusBanner(msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: msg.contains("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(msg.contains("✓") ? Color(red: 0.2, green: 0.85, blue: 0.4) : aperolOrange)

            Text(msg)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color(white: 0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Bottom Primary Action Buttons

    private var bottomActionsView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Button 1: Save to Profile X
                Button {
                    service.flashColorToHardware(slot: service.selectedSlot)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Save to Profile \(service.selectedSlot)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.06))
                    .foregroundStyle(.white)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Commits color to Profile \(service.selectedSlot) in keyboard hardware flash (EEPROM)")

                // Button 2: Save All 3 & Quit (0 MB RAM)
                Button {
                    service.flashAndQuit()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Save All 3 & Quit")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [aperolOrange, Color(red: 217.0 / 255.0, green: 83.0 / 255.0, blue: 15.0 / 255.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .foregroundStyle(.white)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .shadow(color: aperolOrange.opacity(0.30), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .help("Flashes all 3 profiles + WinLock custom colors to hardware flash and exits immediately (0 MB RAM)")
            }

            // Restore Helper
            HStack {
                Button {
                    service.resetFactoryProfiles()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 9))
                        Text("Rebuild All 3 Hardware Slots (Fix Skip / Missing Slot 3)")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(Color(white: 0.45))
                }
                .buttonStyle(.plain)
                .help("Re-initializes Slot 1 Red, Slot 2 Green, Slot 3 Ice White with active flags in hardware EEPROM")
            }
            .padding(.top, 2)
        }
    }
}
