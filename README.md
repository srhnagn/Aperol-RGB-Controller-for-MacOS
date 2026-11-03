# Aperol RGB Controller for MacOS 🍹

<p align="center">
  <strong>Dedicated Hardware RGB Flash Programmer for Corsair K70 MK.2 Mechanical Keyboards</strong><br>
  Open once · Select color · Write to onboard EEPROM · Exit (0 MB residual RAM).
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B%20Apple%20Silicon-black?style=for-the-badge" alt="macOS 14+ Apple Silicon">
  <img src="https://img.shields.io/badge/Keyboard-Corsair%20K70%20RGB%20MK.2-FF5F00?style=for-the-badge" alt="Corsair K70 RGB MK.2">
  <img src="https://img.shields.io/badge/License-GPL--3.0--or--later-blue?style=for-the-badge" alt="License GPL 3.0 or later">
</p>

---

## ⚡ Özellikler

* **Tam Donanım Belleğine (EEPROM) Yazma:** Seçilen statik RGB rengini klavyenin dahili flash belleğine (`lght_00.d`) kalıcı olarak işler. Mac kapansa, yeniden başlasa veya kablo sökülse bile klavye rengi donanımda kalır.
* **Üst Tuşlar Dahil Tam Klavye Desteği:**
  * Profil Değiştirme Butonu LED'i (`Key 125`)
  * Parlaklık Butonu LED'i (`Key 16`)
  * Windows Lock Butonu LED'i (`Key 114`)
  * Corsair Logosu ve Ses/Medya LED'leri
  * Tüm 104/105 tuş matrisi
* **0 MB Residual RAM:** Arka planda 7/24 çalışmaz. İşi bittiğinde **"Belleğe Yaz ve Çık"** butonuyla mikrodenetleyiciye yazıp kendini anında kapatır.
* **Yerel macOS Renk Paleti:** Renk çarkı, spektrum, RGB/HSB sürgüleri ve renk damlalığı (eyedropper).
* **Hazır İkonik Renkler:** Aperol Spritz Turuncusu, Samogon Zümrüt Yeşili, Kar Beyazı, Kehribar Sarı, Okyanus Mavisi, Kızıl Kırmızı, Mor ve Stealth (Tamamen Kapalı).

---

## 🚀 Kurulum & Derleme

```sh
git clone https://github.com/srhnagn/Aperol-RGB-Controller-for-MacOS.git
cd "Aperol-RGB-Controller-for-MacOS"
chmod +x build.sh
./build.sh --install
```

Derlendikten sonra `/Applications/Aperol RGB Controller.app` olarak kurulur ve Spotlight veya Launchpad üzerinden tek tıkla çalıştırılabilir.

---

## 📜 Lisans

GPL-3.0-or-later
Copyright (C) 2026 Aperol.
