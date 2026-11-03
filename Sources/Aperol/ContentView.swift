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
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .shadow(color: Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.35), radius: 6)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(LinearGradient(
                                colors: [Color(red: 1.0, green: 0.37, blue: 0.12), Color(red: 0.9, green: 0.15, blue: 0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 40, height: 40)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Aperol")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text("RGB")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.25))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                            .clipShape(Capsule())
                    }
                    Text("Corsair K70 MK.2 Hardware EEPROM Controller")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // USB Connection Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(service.isConnected ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(service.isConnected ? "K70 MK.2 Connected" : "Device Not Found")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(service.isConnected ? Color.green : Color.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Divider().opacity(0.25)

            // Onboard Hardware Profile Slots (1, 2, 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                        Text("ONBOARD HARDWARE PROFILE SLOTS")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Capacity: 3 Profiles Max (Hardware Switchable)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { slot in
                        slotCard(slot: slot)
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 18)

            // Live Color Palette & Picker
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("COLOR PALETTE & REAL-TIME PREVIEW")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Changes apply to keyboard volatile RAM in real time")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                }

                HStack(spacing: 12) {
                    ColorPicker("", selection: $service.selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 38, height: 32)
                        .onChange(of: service.selectedColor) { _, newColor in
                            service.applyLiveColor(newColor)
                        }

                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(service.selectedColor)
                            .frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 0.5))

                        Text(service.currentHexColor)
                            .font(.system(size: 13, weight: .bold).monospaced())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Button {
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
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Re-send volatile color stream across all 150 positions")
                }

                // Dynamic Preset Color Profiles (Customizable, Add & Delete)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PRESET COLOR PROFILES")
                            .font(.system(size: 9, weight: .bold))
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
                            .background(Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.2))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Save the active color as a new custom preset")

                        Button {
                            service.restoreDefaultPresets()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Restore factory presets")
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
                        ForEach(service.presets) { preset in
                            presetChip(preset: preset)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 18)

            // Info note
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.12))
                Text("Covers all 150 key positions, logo, Profile (125), Brightness (16), and WinLock (114).")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)

            Spacer()

            // Status notification
            if let msg = service.statusMessage {
                Text(msg)
                    .font(.system(size: 10.5, weight: .medium))
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
                        Text("Save to Hardware Slot \(service.selectedSlot)")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Writes selected color into keyboard's internal hardware flash memory (EEPROM).")

                Button {
                    service.flashAndQuit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                        Text("Save to Slot \(service.selectedSlot) & Quit")
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
                    .shadow(color: Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.4), radius: 6)
                }
                .buttonStyle(.plain)
                .help("Saves to selected hardware profile slot and terminates immediately (0 MB RAM).")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Slot Card

    private func slotCard(slot: Int) -> some View {
        let isSelected = service.selectedSlot == slot
        let isSaved = service.savedSlots.contains(slot)

        return Button {
            service.selectedSlot = slot
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(red: 1.0, green: 0.37, blue: 0.12) : Color.white.opacity(0.1))
                        .frame(width: 20, height: 20)
                    Text("\(slot)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Profile \(slot)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(isSaved ? "Saved in EEPROM" : "Slot Available")
                        .font(.system(size: 8.5))
                        .foregroundStyle(isSaved ? Color.green : Color.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.18) : Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preset Chip with Delete Action

    private func presetChip(preset: ColorPreset) -> some View {
        let isHovered = service.hoveredPresetId == preset.id

        return HStack(spacing: 4) {
            Button {
                service.selectedColor = preset.color
                service.applyLiveColor(preset.color)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(preset.color)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))

                    Text(preset.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isHovered && service.presets.count > 1 {
                Button {
                    service.deletePreset(id: preset.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete this preset")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(isHovered ? 0.1 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onHover { hovering in
            service.hoveredPresetId = hovering ? preset.id : nil
        }
    }
}
