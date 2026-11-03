// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import SwiftUI

struct ContentView: View {
    @ObservedObject private var service = AperolK70Service.shared

    var body: some View {
        VStack(spacing: 14) {
            // Header with App Branding and USB Connection Status
            HStack(spacing: 12) {
                if let iconUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                   let nsImg = NSImage(contentsOf: iconUrl) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.35), radius: 6)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(
                                colors: [Color(red: 1.0, green: 0.37, blue: 0.12), Color(red: 0.9, green: 0.15, blue: 0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 42, height: 42)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Aperol")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("RGB")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.2))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                            .clipShape(Capsule())
                    }
                    Text("Corsair K70 MK.2 Hardware EEPROM Controller")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // USB Connection Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(service.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(service.isConnected ? "K70 MK.2 Connected" : "Device Not Found")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(service.isConnected ? Color.green : Color.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Divider().opacity(0.3)

            // Onboard Hardware Profile Slots (1, 2, 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                        Text("3 ONBOARD HARDWARE PROFILES (8MB FLASH)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Active: Profile \(service.selectedSlot)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                }

                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { slot in
                        slotCard(slot: slot)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 18)

            // Live Color Palette & Picker
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("COLOR PALETTE & REAL-TIME PREVIEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("SRAM Live Preview (0 EEPROM Wear)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                }

                HStack(spacing: 12) {
                    ColorPicker("", selection: $service.selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 38, height: 32)
                        .onChange(of: service.selectedColor) { _, newColor in
                            guard service.hasUserInteractedWithColor else { return }
                            service.applyLiveColor(newColor)
                        }

                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(service.selectedColor)
                            .frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.2), lineWidth: 0.5))

                        Text(service.currentHexColor)
                            .font(.system(size: 13, weight: .bold).monospaced())
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Button {
                        service.hasUserInteractedWithColor = true
                        service.applyLiveColor(service.selectedColor)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Re-sync")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Re-send volatile color stream across all 150 positions")

                    Button {
                        service.releaseToHardwareMode()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 10, weight: .bold))
                            Text("Release")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Give the keyboard back to its hardware firmware so physical Profile and Brightness buttons respond again")
                }

                // Dynamic Preset Color Profiles (Customizable, Add & Delete)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PRESET COLOR PROFILES")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            service.addCurrentColorAsPreset()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Add Current Color")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.18))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Save the active color as a new custom preset")

                        Button {
                            service.restoreDefaultPresets()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Restore factory presets")
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 6) {
                        ForEach(service.presets) { preset in
                            presetChip(preset: preset)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 18)

            // Info note
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.12))
                Text("Covers all 150 positions: keys, logo, Profile (125), Brightness (16), and WinLock (114).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)

            Spacer()

            // Status notification
            if let msg = service.statusMessage {
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(msg.contains("✓") ? Color.green : Color.secondary)
                    .padding(.horizontal, 18)
            }

            // Bottom Primary Hardware Write Buttons
            HStack(spacing: 10) {
                Button {
                    service.flashColorToHardware(slot: service.selectedSlot)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 12, weight: .bold))
                        Text("Save to Profile \(service.selectedSlot) Memory")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.09))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Writes selected color into keyboard's Profile \(service.selectedSlot) flash memory (EEPROM).")

                Button {
                    service.flashAndQuit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                        Text("Save & Quit")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(LinearGradient(
                        colors: [Color(red: 1.0, green: 0.37, blue: 0.12), Color(red: 0.9, green: 0.15, blue: 0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.35), radius: 6)
                }
                .buttonStyle(.plain)
                .help("Saves to Profile \(service.selectedSlot) hardware flash and terminates immediately (0 MB RAM).")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Slot Card

    private func slotCard(slot: Int) -> some View {
        let isSelected = service.selectedSlot == slot
        let isSaved = service.savedSlots.contains(slot)
        let slotColor = service.slotProfiles[slot]?.color ?? Color.secondary

        return Button {
            service.switchToHardwareSlot(slot)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(red: 1.0, green: 0.37, blue: 0.12) : Color.primary.opacity(0.08))
                        .frame(width: 22, height: 22)
                    Text("\(slot)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("Profile \(slot)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isSelected ? Color(red: 1.0, green: 0.45, blue: 0.2) : .primary)
                        Circle()
                            .fill(slotColor)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                    }
                    Text(isSaved ? "Saved • \(service.slotProfiles[slot]?.hexString ?? "")" : (service.slotProfiles[slot]?.hexString ?? "Hardware Slot"))
                        .font(.system(size: 8.5))
                        .foregroundStyle(isSaved ? Color.green : Color.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.12) : Color.primary.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preset Chip with Edit & Delete Actions

    private func presetChip(preset: ColorPreset) -> some View {
        let isHovered = service.hoveredPresetId == preset.id
        let isEditing = service.editingPresetId == preset.id

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    service.hasUserInteractedWithColor = true
                    service.selectedColor = preset.color
                    service.applyLiveColor(preset.color)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                        Text(preset.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if isHovered || isEditing {
                    Button {
                        service.editingPresetId = isEditing ? nil : preset.id
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(isEditing ? Color(red: 1.0, green: 0.45, blue: 0.2) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit this preset")

                    if service.presets.count > 1 {
                        Button {
                            service.deletePreset(id: preset.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete this preset")
                    }
                }
            }

            if isEditing {
                VStack(spacing: 5) {
                    TextField("Name", text: Binding(
                        get: { preset.name },
                        set: { service.renamePreset(id: preset.id, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))

                    HStack(spacing: 6) {
                        ColorPicker("", selection: Binding(
                            get: { preset.color },
                            set: { service.setPresetColor(id: preset.id, color: $0) }
                        ), supportsOpacity: false)
                        .labelsHidden()

                        Text(preset.hexString)
                            .font(.system(size: 9.5, weight: .semibold).monospaced())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Use active") {
                            service.setPresetColor(id: preset.id, color: service.selectedColor)
                        }
                        .font(.system(size: 9.5))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isHovered || isEditing ? 0.08 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            if hovering { service.hoveredPresetId = preset.id }
            else if service.hoveredPresetId == preset.id { service.hoveredPresetId = nil }
        }
    }
}
