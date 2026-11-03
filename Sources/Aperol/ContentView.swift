// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import SwiftUI

struct ContentView: View {
    @ObservedObject private var service = AperolK70Service.shared

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 10) {
                // Aperol Glass Icon / Amblem
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(
                            colors: [Color(red: 1.0, green: 0.37, blue: 0.0), Color(red: 0.9, green: 0.15, blue: 0.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                        .shadow(color: Color(red: 1.0, green: 0.37, blue: 0.0).opacity(0.3), radius: 6)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Aperol")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Corsair K70 MK.2 Hardware RGB Programmer")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // USB Connection Status
                HStack(spacing: 5) {
                    Circle()
                        .fill(service.isConnected ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(service.isConnected ? "K70 MK.2 Bağlı" : "Bağlantı Yok")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(service.isConnected ? Color.green : Color.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            Divider().opacity(0.3)

            // Main Color Picker Card
            VStack(alignment: .leading, spacing: 12) {
                Text("RENK SEÇİMİ & PALET")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    // Native macOS ColorPicker with full spectrum & eyedropper
                    ColorPicker("", selection: $service.selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 38, height: 32)

                    // Hex Preview Badge
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(service.selectedColor)
                            .frame(width: 20, height: 20)
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

                    // Quick test live button
                    Button {
                        service.flashCurrentColor()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Dene")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                // Quick Color Preset Grid
                VStack(alignment: .leading, spacing: 6) {
                    Text("HAZIR RENKLER")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 6) {
                        presetChip(name: "Aperol", color: Color(red: 1.0, green: 0.37, blue: 0.0))
                        presetChip(name: "Samogon", color: Color(red: 0.20, green: 0.92, blue: 0.55))
                        presetChip(name: "Beyaz", color: .white)
                        presetChip(name: "Kehribar", color: Color(red: 1.0, green: 0.65, blue: 0.0))
                        presetChip(name: "Okyanus", color: Color(red: 0.0, green: 0.65, blue: 1.0))
                        presetChip(name: "Kızıl", color: Color(red: 1.0, green: 0.12, blue: 0.15))
                        presetChip(name: "Mor", color: Color(red: 0.65, green: 0.15, blue: 1.0))
                        presetChip(name: "Stealth (Off)", color: .black)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 18)

            // Info note
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.0))
                Text("Tüm tuşlar, logo, Profil (125), Parlaklık (16) ve WinLock (114) butonları dahildir.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)

            Spacer()

            // Status message
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
                        Text("Belleğe Yaz (EEPROM)")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    service.flashAndQuit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                        Text("Belleğe Yaz ve Çık")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(LinearGradient(
                        colors: [Color(red: 1.0, green: 0.37, blue: 0.0), Color(red: 0.9, green: 0.15, blue: 0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(red: 1.0, green: 0.37, blue: 0.0).opacity(0.4), radius: 6)
                }
                .buttonStyle(.plain)
                .help("Klavyenin flash belleğine kalıcı olarak yazar ve uygulamayı anında kapatır (0 MB RAM residual).")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private func presetChip(name: String, color: Color) -> some View {
        Button {
            service.selectedColor = color
            service.flashCurrentColor()
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
