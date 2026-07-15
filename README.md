# Fake BL Manager

**⚠️ UNDER DEVELOPMENT - NOT READY FOR PRODUCTION USE**

A simple, safe, and controlled tool for managing Fake Locked Bootloader on Snapdragon 8 Gen 5 / 8 Elite Gen 5 devices.

[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## What is Fake BL Manager?

Fake BL Manager is a complete rework of the original concept designed to provide:

- **Simple**: One-click installation with interactive UI
- **Safe**: Automatic GBL detection, rollback checks, and backups
- **Controlled**: Complete downgrade management with version databases
- **Complete**: TWRP installer, Magisk module, and PC tool included

---

## Features

### Simple Installation
- Automatic device detection
- One-click install with progress bar
- Interactive UI in TWRP and webview

### Safety Checks
- GBL vulnerability detection
- Rollback version verification
- System backup before changes
- Verify installation after patching

### ABL Downgrade
- Controlled ABL version management
- Anti-rollback protection check
- Automatic downgrade when needed
- Safe version database

### OTA Protection
- Automatic patch after OTA updates
- Version retention system
- Conflict detection

### Backup & Restore
- Full system backup (ABL, vbmeta, boot)
- Quick backup for critical partitions
- Easy restore with verification

---

## Supported Devices

### Snapdragon 8 Gen 5 / 8 Elite Gen 5
All devices with Snapdragon 8 Gen 5 or 8 Elite Gen 5 are supported:
- Xiaomi 14 Ultra / 14 Pro / 14 / 13T Pro
- OnePlus 12 / 11 / 10T
- And other devices using these chipsets

### Requirements
- Bootloader must be unlocked
- Kernel must NOT have Baseband Guard
- ABL version < OS3.0.300 (or use downgrade)

---

## Installation Methods

### 1. TWRP Installer
Flashable ZIP for TWRP recovery:
- Auto-detection and checks
- Interactive installation menu
- Optional backup
- Format request when needed

### 2. Magisk Module
Module for Magisk / KernelSU / APatch:
- Webview UI for monitoring
- One-click install
- OTA retention
- Background service

### 3. PC Tool
Desktop application for Linux / Windows / macOS:
- GUI for full control
- ABL analysis and patching
- Rollback version check
- Backup / restore

---

## Quick Start

**⚠️ This project is under development. No release binaries are available yet.**

To use this project, you need to:
1. Clone this repository
2. Build the binaries from source
3. Follow the installation instructions in the `TWRP_INSTALLER/` and `MAGISK_MODULE/` directories

---

## Development Status

**Status:** Under development - NOT READY FOR PRODUCTION

**Next steps before release:**
- [ ] Build TWRP installer ZIP
- [ ] Build Magisk module ZIP  
- [ ] Build PC tool binaries
- [ ] Add complete documentation
- [ ] Testing on physical devices

---

## Documentation

- [Installation Guide](wiki/docs/install.md)
- [Downgrade Guide](wiki/docs/downgrade.md)
- [Rollback Check](wiki/docs/rollback.md)
- [Backup & Restore](wiki/docs/backup.md)
- [OTA Protection](wiki/docs/ota.md)
- [Troubleshooting](wiki/docs/troubleshooting.md)

---

## Disclaimer

**Use at your own risk!**

While Fake BL Manager includes multiple safety checks, there is always a risk of:
- Bootloop if patch fails
- Data loss if format required
- Brick if rollback protection triggered

**Always backup your device before installing!**

---

## Credits

- Author: antocorvo3000

---

## License

This project uses the GPL v3 license. See [LICENSE](LICENSE) for details.

---

## Disclaimer

**This project is currently under development and not ready for production use.**

Use at your own risk. The installation process may brick your device if not done correctly.

---
