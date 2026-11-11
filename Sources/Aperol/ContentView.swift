// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import SwiftUI

struct ContentView: View {
    @ObservedObject private var service = AperolK70Service.shared

    private let aperolOrange = Color(red: 242.0 / 255.0, green: 107.0 / 255.0, blue: 30.0 / 255.0) // #F26B1E
    private let cardBackground = Color(red: 21.0 / 255.0, green: 23.0 / 255.0, blue: 27.0 / 255.0)
    private let cardBorder = Color.white.opacity(0.065)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // MARK: - Header
                headerView

                // MARK: - Section 1: 3 Onboard Hardware Profiles
                hardwareSlotsSection

                // MARK: - Section 2: Color & Real-Time Adjuster
                colorAdjusterSection

                // MARK: - Section 3: Top Hardware Buttons & Win-Lock
                topButtonsSection

                // MARK: - Section 4: Preset Palettes
                presetsSection

                // MARK: - Status Toast
                if let msg = service.statusMessage {
                    statusBanner(msg: msg)
                }

                // MARK: - Bottom Actions
                bottomActionsView
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 16.0 / 255.0, green: 17.0 / 255.0, blue: 20.0 / 255.0),
                    Color(red: 11.0 / 255.0, green: 12.0 / 255.0, blue: 14.0 / 255.0)
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

                Text("Hardware Flash & EEPROM Controller")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
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

                    Text("MAIN KEYS COLOR & PREVIEW")
                        .font(.system(size: 9.5, weight: .bold).monospaced())
                        .foregroundStyle(Color(white: 0.55))
                }

                Spacer()

                Text("Volatile Live Stream")
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

    // MARK: - Top Buttons & WinLock Section

    private var topButtonsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.2.square.on.square")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(aperolOrange)

                    Text("TOP HARDWARE BUTTONS & WIN-LOCK")
                        .font(.system(size: 9.5, weight: .bold).monospaced())
                        .foregroundStyle(Color(white: 0.55))
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: service.isTopButtonsAutoSynced ? "checkmark.circle.fill" : "slider.horizontal.3")
                        .font(.system(size: 9))
                        .foregroundStyle(service.isTopButtonsAutoSynced ? Color.green : aperolOrange)
                    Text(service.isTopButtonsAutoSynced ? "Auto-Synced" : "Custom Accent")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(service.isTopButtonsAutoSynced ? Color.green : aperolOrange)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((service.isTopButtonsAutoSynced ? Color.green : aperolOrange).opacity(0.12))
                .clipShape(Capsule())
            }

            // WinLock Action Disable Toggle
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: service.isWinLockDisabled ? "lock.slash.fill" : "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(service.isWinLockDisabled ? aperolOrange : Color(white: 0.6))

                        Text("Disable Physical WinLock Key Action")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text("Pressing physical lock key has zero effect; never locks macOS Option/Win keys")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(white: 0.5))
                }

                Spacer()

                Toggle("", isOn: $service.isWinLockDisabled)
                    .toggleStyle(SwitchToggleStyle(tint: aperolOrange))
                    .labelsHidden()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Unified 3-Button Overview (Profile, Brightness, WinLock)
            HStack(spacing: 8) {
                topButtonStatusBadge(
                    title: "Profile Button",
                    icon: "person.crop.circle",
                    color: service.profileButtonColor
                )

                topButtonStatusBadge(
                    title: "Brightness",
                    icon: "sun.max.fill",
                    color: service.brightnessButtonColor
                )

                topButtonStatusBadge(
                    title: "WinLock",
                    icon: "lock.fill",
                    color: service.winLockLockedColor
                )
            }

            // Auto-Sync Toggle & Custom Override Disclosure
            HStack {
                Toggle(isOn: $service.isTopButtonsAutoSynced) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto-Sync with Active Profile Color")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Top buttons always follow the active profile color for complete visual uniformity")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: aperolOrange))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Optional Individual Pickers if Auto-Sync is turned off
            if !service.isTopButtonsAutoSynced {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    topButtonColorCard(
                        title: "WinLock (Locked)",
                        icon: "lock.fill",
                        color: $service.winLockLockedColor
                    )

                    topButtonColorCard(
                        title: "WinLock (Unlocked)",
                        icon: "lock.open.fill",
                        color: $service.winLockUnlockedColor,
                        accessoryButton: {
                            Button {
                                service.matchWinLockUnlockedToLocked()
                            } label: {
                                Text("Match")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(aperolOrange.opacity(0.15))
                                    .foregroundStyle(aperolOrange)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    )

                    topButtonColorCard(
                        title: "Profile Button",
                        icon: "person.crop.circle",
                        color: $service.profileButtonColor
                    )

                    topButtonColorCard(
                        title: "Brightness Button",
                        icon: "sun.max.fill",
                        color: $service.brightnessButtonColor
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(11)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func topButtonStatusBadge(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: color.opacity(0.6), radius: 3)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 8))
                        .foregroundStyle(Color(white: 0.7))
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(AperolK70Service.hexFromColor(color))
                    .font(.system(size: 8, weight: .medium).monospaced())
                    .foregroundStyle(Color(white: 0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func topButtonColorCard<Accessory: View>(
        title: String,
        icon: String,
        color: Binding<Color>,
        @ViewBuilder accessoryButton: () -> Accessory = { EmptyView() }
    ) -> some View {
        let hex = AperolK70Service.hexFromColor(color.wrappedValue)
        return HStack(spacing: 8) {
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundStyle(aperolOrange)

                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.9))
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Text(hex)
                        .font(.system(size: 8.5, weight: .medium).monospaced())
                        .foregroundStyle(Color(white: 0.5))

                    accessoryButton()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .help("Restore curated factory color presets")
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
            HStack(spacing: 8) {
                Button {
                    service.resetFactoryProfiles()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 9))
                        Text("Rebuild All 3 Hardware Slots")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(Color(white: 0.55))
                }
                .buttonStyle(.plain)
                .help("Re-initializes all 3 profiles with valid active flags in hardware EEPROM")

                Text("•")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(white: 0.25))

                Text("Hold ESC while plugging USB (5s) for hardware factory reset")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.40))
            }
            .padding(.top, 2)
        }
    }
}
