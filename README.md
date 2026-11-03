# Aperol RGB Controller for MacOS 🍹

<p align="center">
  <strong>Dedicated Hardware RGB Flash Programmer for Corsair K70 MK.2 Mechanical Keyboards</strong><br>
  Open once · Select color with instant volatile RAM stream · Commit to onboard memory · Exit (0 MB residual RAM).
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B%20Apple%20Silicon-black?style=for-the-badge" alt="macOS 14+ Apple Silicon">
  <img src="https://img.shields.io/badge/Keyboard-Corsair%20K70%20RGB%20MK.2-FF5F00?style=for-the-badge" alt="Corsair K70 RGB MK.2">
  <img src="https://img.shields.io/badge/License-GPL--3.0--or--later-blue?style=for-the-badge" alt="License GPL 3.0 or later">
</p>

---

## ⚡ Key Features

* **Real Onboard Memory Write (HWCLR):** Uses the same NXP command sequence as ckb-next's `savergb_kb()` (bulk `0x7F` colour packets followed by `07 14 03 01 01 <mode> <channel>`), covering all 144 LED positions including the Profile, Brightness and WinLock buttons. The K70 has a single hardware mode (3 exist only on the K95).
* **Pure Volatile RAM Real-Time Streaming:** Selecting or sliding colors streams 24-bit RGB values directly to volatile device SRAM over USB HID. **Zero flash writes occur during live preview**, completely eliminating EEPROM exhaustion, lockups, and controller latency.
* **Manual Hardware Flash (EEPROM) Commit:** Colors are committed to non-volatile flash memory only when you explicitly press **"Save to Keyboard Memory"** or **"Save & Quit"**. The color persists across reboots, power cuts, and cable disconnections.
* **Non-Intrusive Launch:** Connecting or launching Aperol will **never** overwrite your keyboard's active lighting profile. It passively initializes USB communication and waits for your input.
* **Customizable Color Presets (+ and Delete):** Add any currently selected color as a new preset with a single click on `+ Add Current Color`. Delete presets anytime by hovering over the chip. All presets persist automatically across app sessions.
* **Complete Hardware Coverage (150 Key/Zone Positions):**
  * Profile Switch Button LED (`Key 125`)
  * Brightness Button LED (`Key 16`)
  * Windows Lock Button LED (`Key 114`)
  * Corsair Illuminated Logo & Media Keys
  * Complete 104/105-key keyboard matrix
* **0 MB Residual RAM Architecture:** Does not run as a permanent background daemon. When you are finished, **"Save to Slot & Quit"** commits the lighting to the hardware microcontroller and instantly terminates the process.

---

## 🎨 Calibrated Color Profiles

* **Night Vision Green:** `#46FF00` (RGB 70, 255, 0) — Phosphor night-vision green
* **Ice White:** `#9ADCE7` (RGB 154, 220, 231) — Crisp glacial white
* **Aperol Spritz:** `#F03C00` (RGB 240, 60, 0) — Signature Italian aperitivo orange
* **Samogon Emerald:** `#00E74F` (RGB 0, 231, 79) — Deep radiant emerald
* **Pure Red:** `#FF0000` (RGB 255, 0, 0)
* **Amber Gold:** `#FFA000` (RGB 255, 160, 0)
* **Cyber Magenta:** `#D946EF` (RGB 217, 70, 239)
* **Stealth:** `#000000` (All LEDs turned completely off)

---

## 🚀 Installation & Build

```sh
# Clone repository
git clone https://github.com/srhnagn/Aperol-RGB-Controller-for-MacOS.git
cd "Aperol-RGB-Controller-for-MacOS"

# Compile, sign, and install into /Applications
chmod +x build.sh
./build.sh --install
```

After building, the application is installed directly into `/Applications/Aperol RGB Controller.app` and can be launched via Spotlight or Launchpad.

---

## 📜 License

Licensed under the [GPL-3.0-or-later](LICENSE) terms.
Copyright (C) 2026 Aperol.
