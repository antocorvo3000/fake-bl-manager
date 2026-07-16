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
All devices with Snapdragon 8 Gen 5 or 8 Elite Gen 5 are supported.

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

## GBL-Chainload Port (Experimental)

This project includes a port of [`gbl-chainload`](https://github.com/1vivy/gbl-chainload) for Xiaomi devices.

While standard Fake BL Manager patches ABL/EFISP for boot and Superfastboot, **GBL-Chainload (Mode-1)** uses
protocol hooks to intercept boot state queries and reports `locked/green` to the Kernel and TrustZone.

This is required to pass Play Integrity and fully hide unlock state from the OS. **WIP: Porting to popsicle.**

### Xiaomi Popsicle Port Status

| Component | Status | File |
|---|---|---|
| GBL exploit confirmed | ✅ | `patch_abl` passes 5/5 patches |
| ABL string anchors | ✅ | `patch6/7` compatible strings found |
| TrustZone TA identified | ✅ | `mitrustedui` (not OplusSec GUID) |
| Reserve partition mapped | ✅ | `devinfo` (8KB, equiv. `oplusreserve1`) |
| XiaomiHook.c (QSEECOM hooks) | ✅ | Hooks `mitrustedui` TA StartApp/SendCmd |
| XiaomiOverlay.c (fakelock) | ✅ | Clears `is_unlocked` / `is_unlock_critical` |
| OEM enum + build integration | ✅ | `GBL_OEM_XIAOMI = 2` added to manifest |
| BlockIoHook.c (devinfo) | ✅ | `devinfo` partition added to reserve detection |
| Ground-truth cmd-ids | ❌ TBD | Requires `--verbose` capture on stock locked device |
| DeviceInfo offsets | ❌ TBD | May differ from standard Qualcomm layout |

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
