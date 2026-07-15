# Fake BL Manager

A simple, safe, and controlled tool for managing Fake Locked Bootloader on Snapdragon 8 Gen 5 / 8 Elite Gen 5 devices.

**This is a fork of [GBL Root Canoe](https://github.com/superturtlee/gbl_root_canoe) with enhanced safety, simplicity, and control features.**

[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/antocorvo3000/fake-bl-manager/releases)

---

## What is Fake BL Manager?

Fake BL Manager is an improved version of `gbl_root_canoe` that provides:

- **Simple**: One-click installation with interactive UI
- **Safe**: Automatic GBL detection, rollback checks, and backups
- **Controlled**: Complete downgrade management with version databases
- **Complete**: TWRP installer, Magisk module, and PC tool included

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

## Supported Devices

- Xiaomi 14 Ultra / 14 Pro / 14 / 13T Pro
- OnePlus 12 / 11 / 10T
- Other Snapdragon 8 Gen 5 / 8 Elite Gen 5 devices

## Installation Methods

### 1. TWRP Installer
Flashable ZIP for TWRP recovery:
```
- Auto-detection and checks
- Interactive installation menu
- Optional backup
- Format request when needed
```

### 2. Magisk Module
Module for Magisk / KernelSU / APatch:
```
- Webview UI for monitoring
- One-click install
- OTA retention
- Background service
```

### 3. PC Tool
Desktop application for Linux / Windows / macOS:
```
- GUI for full control
- ABL analysis and patching
- Rollback version check
- Backup / restore
```

## Quick Start

### From TWRP
1. Download `fake-bl-manager-twrp.zip`
2. Flash in TWRP
3. Follow the interactive menu
4. Reboot to system

### From Magisk
1. Download `fake-bl-manager-module.zip`
2. Install via Magisk / KernelSU
3. Open webview UI (localhost:8080)
4. Click "Install"

### From PC
1. Download `fake-bl-manager-pc.tar.gz`
2. Extract and run
3. Follow the GUI instructions

## Documentation

- [Installation Guide](wiki/docs/install.md)
- [Downgrade Guide](wiki/docs/downgrade.md)
- [Rollback Check](wiki/docs/rollback.md)
- [Backup & Restore](wiki/docs/backup.md)
- [OTA Protection](wiki/docs/ota.md)
- [Troubleshooting](wiki/docs/troubleshooting.md)

## Disclaimer

**Use at your own risk!**

While Fake BL Manager includes multiple safety checks, there is always a risk of:
- Bootloop if patch fails
- Data loss if format required
- Brick if rollback protection triggered

**Always backup your device before installing!**

## Credits

- Original project: [GBL Root Canoe](https://github.com/superturtlee/gbl_root_canoe)
- Fake BL Manager: Enhanced with safety, simplicity, and control

## License

This project uses the original GPL license from GBL Root Canoe. See [LICENSE](LICENSE) for details.

Note: The modified components in Fake BL Manager are licensed under GPL as well, in accordance with the original project's terms.
