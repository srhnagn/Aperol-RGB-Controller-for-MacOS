// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import SwiftUI

struct ContentView: View {
    @ObservedObject private var service = AperolK70Service.shared

    var body: some View {
        VStack(spacing: 16) {
            // Header with App Branding and USB Status
            HStack(spacing: 12) {
                // App Icon Presentation
                if let iconUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                   let nsImg = NSImage(contentsOf: iconUrl) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
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
                            .frame(width: 42, height: 42)
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

                // USB Connection Status Indicator
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
            .padding(.top, 18)

            Divider().opacity(0.3)

            // Main Color Configuration Card
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("COLOR PALETTE & REAL-TIME PREVIEW")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Changes apply to keyboard instantly")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.2))
                }

                HStack(spacing: 12) {
                    // Native macOS ColorPicker with full spectrum, sliders & eyedropper
                    ColorPicker("", selection: $service.selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 38, height: 32)
                        .onChange(of: service.selectedColor) { _, newColor in
                            service.applyLiveColor(newColor)
                        }

                    // Hex Preview Badge
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

                    // Quick Refresh / Re-sync Button
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
                    .help("Re-send lighting packets to all keys and top buttons")
                }

                // Quick Color Preset Grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("PRESET COLOR PROFILES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 6) {
                        presetChip(name: "Pure Red", color: Color(red: 1.0, green: 0.0, blue: 0.0))
                        presetChip(name: "Ice White", color: Color(red: 0.88, green: 0.95, blue: 1.0))
                        presetChip(name: "Rover Green", color: Color(red: 0.0, green: 0.90, blue: 0.46)) // 2000s Range Rover cockpit green
                        presetChip(name: "Aperol Spritz", color: Color(red: 1.0, green: 0.37, blue: 0.12))
                        presetChip(name: "Samogon", color: Color(red: 0.20, green: 0.92, blue: 0.55))
                        presetChip(name: "Amber Gold", color: Color(red: 1.0, green: 0.63, blue: 0.0))
                        presetChip(name: "Cyber Magenta", color: Color(red: 0.85, green: 0.27, blue: 0.94))
                        presetChip(name: "Stealth (Off)", color: .black)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 18)

            // Hardware Coverage Note
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

            // Bottom Primary Action Buttons
            HStack(spacing: 10) {
                Button {
                    service.flashCurrentColor()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 12, weight: .bold))
                        Text("Save to Flash (EEPROM)")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Writes the active color to hardware memory so it persists across reboots and disconnections.")

                Button {
                    service.flashAndQuit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                        Text("Save to Flash & Quit")
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
                .help("Commits color to hardware memory and terminates immediately (0 MB residual RAM footprint).")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private func presetChip(name: String, color: Color) -> some View {
        Button {
            service.selectedColor = color
            service.applyLiveColor(color)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                Text(name)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}
