# Aperol RGB Controller for MacOS 🍹

<p align="center">
  <strong>Dedicated Hardware RGB Flash Programmer for Corsair K70 MK.2 Mechanical Keyboards</strong><br>
  Open once · Select color with instant live preview · Write to onboard EEPROM · Exit (0 MB residual RAM).
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B%20Apple%20Silicon-black?style=for-the-badge" alt="macOS 14+ Apple Silicon">
  <img src="https://img.shields.io/badge/Keyboard-Corsair%20K70%20RGB%20MK.2-FF5F00?style=for-the-badge" alt="Corsair K70 RGB MK.2">
  <img src="https://img.shields.io/badge/License-GPL--3.0--or--later-blue?style=for-the-badge" alt="License GPL 3.0 or later">
</p>

---

## ⚡ Key Features

* **True Hardware Flash (EEPROM) Writing:** Commits your selected static 24-bit RGB color directly to the keyboard's internal flash storage (`lght_00.d` and hardware zones). The color persists across reboots, power cuts, and cable disconnections without needing any software daemon.
* **Instant Real-Time Preview:** As soon as you pick a color or click a preset, lighting updates across the physical keyboard in real time over USB HID without waiting for manual confirmation.
* **Complete Hardware Coverage (All 150 Key/Zone Positions):**
  * Profile Switch Button LED (`Key 125`)
  * Brightness Button LED (`Key 16`)
  * Windows Lock Button LED (`Key 114`)
  * Corsair Logo & Media Keys
  * Complete 104/105-key keyboard matrix
* **0 MB Residual RAM Architecture:** Does not run as a permanent daemon. When you are finished, **"Save to Flash & Quit"** commits the lighting to the hardware microcontroller and instantly terminates the process.
* **Native macOS Color Palette:** Full spectrum color wheel, sliders, hex input, and eyedropper support via native SwiftUI ColorPicker.
* **Iconic Hardware Presets:**
  * **Pure Red:** `#FF0000` (RGB 255, 0, 0)
  * **Ice White:** `#9ADCE7` (RGB 154, 220, 231)
  * **Night Vision Green:** `#7BFF00` (RGB 123, 255, 0)
  * **Aperol Spritz:** `#F03C00` (RGB 240, 60, 0)
  * **Samogon Emerald:** `#00E74F` (RGB 0, 231, 79)
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
