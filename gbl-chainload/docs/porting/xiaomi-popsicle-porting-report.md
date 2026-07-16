# Porting gbl-chainload to Xiaomi 17 Pro Max ("popsicle", Snapdragon 8 Gen 5)

## a. Protocol map

### Protocols currently hooked by gbl-chainload

| Protocol | Protocol GUID (symbol) | Qualitative classification | Hook role | OPLUO-specific? |
|---|---|---|---|---|
| **QCOM_VERIFIEDBOOT_PROTOCOL** | `gEfiQcomVerifiedBootProtocolGuid` (from `<Protocol/EFIVerifiedBoot.h>`) | **Qualcomm-standard** (in `QcomModulePkg`) | Wraps all 10 vtable entries: `VBRwDeviceState`, `VBDeviceInit`, `VBSendRot`, `VBSendMilestone`, `VBVerifyImage`, `VBDeviceResetState`, `VBIsDeviceSecure`, `VBGetBootState`, `VBGetCertFingerPrint`, `VBIsKeymasterEnabled`. Mode-1 fakelock mutates device-state in `READ_CONFIG` to clear `is_unlocked`/`is_unlock_critical`; swallows `WRITE_CONFIG` and `VBDeviceResetState`. | **No** — this is the Qualcomm-standard verified-boot protocol. All QCOM devices with an ABL should expose it, though OEMs may add OEM-specific fields to the `DeviceInfo` struct. |
| **QCOM_SCM_PROTOCOL** | `gQcomScmProtocolGuid` (from `<Protocol/EFIScm.h>`) | **Qualcomm-standard** | Wraps 5 slots: `ScmSysCall`, `ScmFastCall2`, `ScmSipSysCall`, `ScmSendCommand`, `ScmQseeSysCall`. Universal baseline drops 3 SIP calls before TZ: `TZ_BLOW_SW_FUSE_ID` (0x02000801), `TZ_UPDATE_ROLLBACK_VERSION_ID` (0x0200011E), `TZ_UPDATE_ROLLBACK_VERSION_IF_AB_PARTITION_FEATURE_ENABLED_ID` (0x32000110). | **No** — Qualcomm SMC interface. Decodes standard SIP SmcIds (0x02000604, 0x02000804, etc.) which are Qualcomm ABI. |
| **QCOM_QSEECOM_PROTOCOL** | `gQcomQseecomProtocolGuid` (from `<Protocol/EFIQseecom.h>`) | **Qualcomm-standard** (but OplusSec TA is OPLUO) | Wraps `QseecomStartApp` + `QseecomSendCmd`. Decodes KeyMaster TA cmd-ids (0x201 SET_ROT, 0x208 SET_BOOT_STATE, 0x207 SET_VERSION, 0x211 SET_VBH, etc.). Mode-1 drops OplusSec cmd `0x0A` (write_rpmb_boot_info). Mode-2 rewrites KM send buffers. | **Protocol: No**. But OplusSec TA (GUID `E11DDA6A-651B-4AB4-B8C5-30B352B472E2`) is **OPLUO-specific** — Xiaomi does NOT have this TA. |
| **SPSS Protocol** (Secure Processor SubSystem bridge) | `gEfiSPSSProtocolGuid` (from `<Protocol/EFISPSS.h>`) | **Qualcomm-OEM hybrid** | Wraps `SPSSDxe_ShareKeyMintInfo` — mirrors RoT/BootState/Vbh to the SPU. Mode-2 rewrites the packed struct. | **Semi** — SPSS is a Qcom protocol GUID, but the SPU (Secure Processor Unit) integration is heavily OEM-specific. Xiaomi may or may not have an SPU equivalent. |
| **EFI_BLOCK_IO_PROTOCOL** | `gEfiBlockIoProtocolGuid` (from `<Protocol/BlockIo.h>`) | **EFI-standard** | Hooks partition `ReadBlocks`/`WriteBlocks`. Swallows writes to `oplusreserve1`/`opporeserve1` partitions (DeepTest token preservation). Blocks EFISP reads/writes. | **No for protocol; YES for partition names.** `oplusreserve1` and `opporeserve1` are OPLUO partition names. Xiaomi does NOT have these. Xiaomi has different reserve partitions (if any). |

### OPLUO-specific vs Qualcomm-standard summary

- **Qualcomm-standard (will exist on Snapdragon 8 Gen 5 Xiaomi ABL)**:
  - `QCOM_VERIFIEDBOOT_PROTOCOL` — the core target for fakelock
  - `QCOM_SCM_PROTOCOL` — universal TZ SIP drop (rollback prevention)
  - `QCOM_QSEECOM_PROTOCOL` — QSEE/KeyMaster communication
  - SCM SIP constants (0x02000801, 0x0200011E, 0x32000110, 0x02000604, etc.)

- **OPLUO-specific (will NOT exist on Xiaomi)**:
  - OplusSec TA (GUID `E11DDA6A-651B-4AB4-B8C5-30B352B472E2`) — Oplus-specific TrustZone app
  - `oplusreserve1` / `opporeserve1` GPT partition names — Oplus reserve partitions
  - `"oplus_phoenix"`, `"phoenix"`, `"oplusreserve"` QSEE TA names — Oplus-specific TAs
  - OplusSec cmd space (0x04, 0x09, 0x0A) — read/write_rpmb_boot_info

- **Semi-OEM (may differ on Xiaomi)**:
  - `DeviceInfo` struct layout (offsets of `is_unlocked`, `is_unlock_critical`)
  - SPSS/SPU bridge — exists on QCOM but SPU config may differ
  - KeyMaster cmd-id space (generally Qualcomm-standard but OEM additions possible)
  - Partition names (GPT)
  - vbmeta descriptor layout / AVB public key formats

## b. Patch structure

### What Mode-1 actually patches

Mode-1 has two **distinct** mutation surfaces:

#### 1. Protocol-hook fakelock (PRIMARY — no binary patching needed)

This is the main fakelock mechanism. It does NOT use the dynamic patch engine at all. Instead:

- **`VerifiedBootHook.c`** intercepts `QCOM_VERIFIEDBOOT_PROTOCOL` vtable calls:
  - **`VBRwDeviceState(READ_CONFIG)`**: Post-call, clears `is_unlocked` and `is_unlock_critical` fields in the returned `DeviceInfo` buffer. Uses `FakelockOverlay_OnVbReadConfig_Post()` which computes field offsets from the `DeviceInfo` struct definition (`Mode1OffsetOfIsUnlocked()`, `Mode1OffsetOfIsUnlockCritical()`).

  - **`VBDeviceInit`**: Pre- and post-call, sets `Devinfo->is_unlocked = FALSE` and `Devinfo->is_unlock_critical = FALSE`. This directly affects ABL's internal device state view.

  - **`VBRwDeviceState(WRITE_CONFIG)`**: **Swallowed entirely** — returns `EFI_SUCCESS` without forwarding. Prevents persistence of lock-state experiments to RPMB.

  - **`VBDeviceResetState`**: **Swallowed** — returns `EFI_SUCCESS` without forwarding. Prevents ABL from resetting lock state.

- **`QseecomHook.c`** (mode-1 only):
  - Detects OplusSec TA by GUID on `QseecomStartApp`
  - On `QseecomSendCmd`, if handle matches OplusSec and cmd is `0x0A` (write_rpmb_boot_info), **drops** the call — returns `EFI_SUCCESS` without forwarding to TZ

#### 2. Universal baseline (always active, any mode)

- **`UniversalBaseline.c`**: Drops 3 SCM SIP calls universally:
  - `TZ_BLOW_SW_FUSE_ID` (0x02000801) — prevents soft-fuse advancement
  - `TZ_UPDATE_ROLLBACK_VERSION_ID` (0x0200011E) — prevents anti-rollback index bump
  - `TZ_UPDATE_ROLLBACK_VERSION_IF_AB_PARTITION_FEATURE_ENABLED_ID` (0x32000110) — same, A/B-aware path

- **`BlockIoHook.c`**: Swallows writes to `oplusreserve1`/`opporeserve1` partitions, particularly the DeepTest token block at `LastBlock - 0x3a5`.

- **`ScmHook.c`**: Observation-only wrapper for all 5 SCM slots, with universal SIP drop policy applied in `HookedScmSipSysCall`.

#### Dynamic patch engine (Tier-2 fallback)

Separate from the protocol hooks, the dynamic patch engine patches the **unwrapped ABL PE binary** at runtime:

- **`patch6`**: String-anchored. Scans for refusal strings like "Flashing is not allowed in Lock State", "Erase is not allowed in Lock State", "Slot Change is not allowed in Lock State". Rewrites the preceding branch gate. This is OEM-specific and will need Xiaomi-specific strings.

- **`patch7`**: String-anchored. Scans for `"Your device has been unlocked and can't be trusted"` (Orange State warning). Resolves ADRP+ADD pair targeting the string, walks back <=0x40 to nearest `CBZ Wn`, rewrites to unconditional `B`. Cross-build compatible, but only fires on Oplus ABLs.

- **`patch10`**: String-anchored. Scans for `"Persistent values required for AVB_HASHTREE_ERROR_MODE_MANAGED_RESTART_AND_EIO"` in libavb. Forces allow-verification-error.

- **`patch1`**: EFISP recursion guard. Only applies where the ABL contains the EFISP re-entry marker. EU-specific.

All dynamic patches are **string-anchored** (except patch1), which makes them cross-build portable within the same OEM family but OEM-specific across brands.

## c. What would need to change for Xiaomi vs OnePlus

### 1. `BlockIoHook.c` — reserve partition names

**Change needed**: HIGH

Currently matches `L"oplusreserve1"` and `L"opporeserve1"`. Xiaomi does NOT use these partition names. You need to:

- Discover what Xiaomi calls its equivalent reserve/token partition(s). Likely candidates:
  - `devinfo` / `metadata` / `frp` / `persist` — Xiaomi may store unlock tokens here
  - Some devices use `cust` or `misc`
  - Xiaomi may NOT have a direct equivalent — their DeepTest equivalent might work differently

**Action**: Extract GPT from popsicle (`fastboot get_staged` or `dump` of partition table), identify the partition where unlock/relock state is stored, and modify `IsOplusReservePartitionName()` to also match Xiaomi partition names. Consider renaming the function to something like `IsReservePartitionName()` with an OEM-specific prefix list.

### 2. `FakelockOverlay.c` — `DeviceInfo` field offsets

**Change needed**: MEDIUM

The `DeviceInfo` struct (from `<Library/DeviceInfo.h>`) defines offsets for `is_unlocked` and `is_unlock_critical` via C struct-of-zero casting. If Xiaomi's `DeviceInfo` struct has different field layouts or additional OEM-specific fields, these offsets may not match.

**Action**: Compare `DeviceInfo` struct definition between Oplus and Xiaomi BSPs. If different, introduce an OEM-specific offset override or a config-driven offset resolution.

### 3. OplusSec TA handling

**Change needed**: LOW (just needs it to not fire)

`QseecomHook.c` has hardcoded logic for the OplusSec TA (GUID `E11DDA6A-651B-4AB4-B8C5-30B352B472E2`) and its cmd space (0x04, 0x09, 0x0A). This code is gated by handle matching, so it simply won't trigger on Xiaomi (no OplusSec TA will be started).

**Action**: No change needed for mode-1. The Fakelock policy `FakelockOverlay_ShouldDropQseeOplusSec` returns `FALSE` when `gOplusSecHandle == (UINT32)-1` (unknown). However, if Xiaomi has an **equivalent** TA with similar persistence semantics, you may want to identify it and add equivalent handling.

### 4. `Phoenix-shaped` TA detection

**Change needed**: LOW

`QseecomHook.c` tags `"oplus_phoenix"`, `"phoenix"`, `"oplusreserve"`, `"oplusreserve1"` as Phoenix-shaped for wide hex dumps. Xiaomi may have different TA names.

**Action**: Not strictly required for mode-1 (observation-only). For mode-2 debugging, add Xiaomi TA name detection.

### 5. Dynamic patches — `patch6`, `patch7`, `patch10`

**Change needed**: HIGH

These patches scan for **Oplus-specific refusal strings** in the ABL binary. Xiaomi ABL will have different strings. Examples:

- Instead of "Flashing is not allowed in Lock State", Xiaomi might use "Device is locked. Unlock the device before flash" or similar.
- The orange-state warning string may differ.
- The libavb persistent-values string is Qualcomm libavb-standard, so `patch10` might work as-is.

**Action**:
1. Extract the Xiaomi ABL (`fastboot oem unlock` to enable, then dump `abl_a` partition).
2. `strings` the ABL to find equivalent strings.
3. Create a new patch group (e.g., `xiaomi/`) in `GblChainloadPkg/Library/DynamicPatchLib/` or add Xiaomi-specific search strings to the existing patch table in the `patch-engine` crate.
4. Consider making the patch engine support OEM-tagged patch groups with device-identity matching.

### 6. KeyMaster cmd-id space

**Change needed**: UNDETERMINED

The KeyMaster cmd-ids (0x201, 0x208, 0x207, 0x211, etc.) are Qualcomm-standard and should be identical on Snapdragon 8 Gen 5 devices. Xiaomi may add additional OEM-specific cmds.

**Action**: Capture a verbose (`--verbose`) boot log from popsicle with mode-0 to observe actual QSEE traffic. Compare cmid-id space against the known Oplus table.

### 7. SPSS / SPU bridge

**Change needed**: UNKNOWN

SPSS (`gEfiSPSSProtocolGuid`) mirrors KeyMaster state to the SPU (Secure Processor Unit). Xiaomi may or may not have an SPU equivalent.

**Action**: If `InstallSpssHook()` returns `EFI_NOT_FOUND` on Xiaomi, that's OK for mode-1 (it's optional unless `WantProfileSpoof` is set). For mode-2, investigate whether Xiaomi has an equivalent SPU and its protocol.

### 8. Boot partition names

**Change needed**: LOW

`BootFlow.c` resolves the active ABL partition name as `L"abl_a"` or `L"abl_b"` via `GetCurrentSlotSuffix()`, with fallback to `L"abl"` for non-A/B devices. Most Xiaomi devices use A/B partitions, so this should work.

**Action**: No change needed unless Xiaomi uses a different naming convention.

## d. Porting plan — step-by-step for "popsicle"

### Phase 1: Ground-truth data collection (required before any code changes)

1. **Extract partitions**:
   ```bash
   fastboot get_staged /tmp/partitions.img   # or use fastboot dump
   dd if=/dev/block/bootdevice/by-name/abl_a of=abl_a.img
   dd if=/dev/block/bootdevice/by-name/abl_b of=abl_b.img
   dd if=/dev/block/bootdevice/by-name/vbmeta_a of=vbmeta_a.img
   ```

2. **Obtain GPT partition table**:
   ```bash
   fdisk -l /dev/block/sda   # or equivalent
   # Look for partition names — specifically any "reserve", "devinfo", "frp" partitions
   ```

3. **Strings analysis of Xiaomi ABL**:
   ```bash
   strings abl_a.img | grep -iE "lock|flash|unlock|erase|slot|orange|trusted|verified"
   # Identify equivalents to Oplus strings used by patch6/patch7
   ```

4. **Capture mode-0 verbose boot log**:
   - Build mode-0: `./scripts/build.sh --mode 0 --verbose --debug`
   - Flash to EFISP, boot, capture UefiLog
   - This will show which protocols exist/missing on Xiaomi

5. **Identify what protocols are present**: Look in the mode-0 log for:
   - `VerifiedBootHook: installed X of 10 slots` — confirms `QCOM_VERIFIEDBOOT_PROTOCOL` exists
   - `ScmHook: installed X of 5 slots` — confirms `QCOM_SCM_PROTOCOL` exists
   - `QseecomHook: installed` — confirms `QCOM_QSEECOM_PROTOCOL` exists
   - `SpssHook:` output — whether SPSS exists or not
   - `BlockIoHook:` output — what partition names are found

6. **Extract `DeviceInfo` struct layout**: From the mode-0 log, examine the hex dumps of `VBDeviceInit` and `VBRwDeviceState` buffers to confirm `is_unlocked` and `is_unlock_critical` offsets.

### Phase 2: Minimal port (mode-1 fakelock without dynamic patches)

1. **Modify `BlockIoHook.c`** (or add a config mechanism):
   ```
   /home/anto/gbl-chainload/GblChainloadPkg/Library/ProtocolHookLib/BlockIoHook.c
   ```
   - Add Xiaomi reserve partition names if identified, OR
   - Make the match list config-driven via a build-time or runtime table
   - Function to modify: `IsOplusReservePartitionName()` (line ~94)

2. **Verify `DeviceInfo` offsets match**:
   Review `/home/anto/gbl-chainload/GblChainloadPkg/Library/ProtocolHookLib/FakelockOverlay.c`
   - Functions `Mode1OffsetOfIsUnlocked()` and `Mode1OffsetOfIsUnlockCritical()` use struct-of-zero casting
   - If Xiaomi's `DeviceInfo` differs, either:
     a. Patch `Include/Library/DeviceInfo.h` to support OEM-specific offsets, OR
     b. Add runtime offset detection from the observed VBDeviceInit buffer shape

3. **Add Xiaomi-specific dynamic patches** (optional, for full compatibility):
   ```
   /home/anto/gbl-chainload/crates/patch-engine/   # if adding to Rust patch engine
   # OR
   /home/anto/gbl-chainload/GblChainloadPkg/Library/DynamicPatchLib/
   ```
   - Create a Xiaomi patch table with equivalent strings to patch6/patch7
   - Register patches in the `DynamicPatchLib` infrastructure

4. **Add Xiaomi TA names** (for debugging visibility):
   ```
   /home/anto/gbl-chainload/GblChainloadPkg/Library/ProtocolHookLib/QseecomHook.c
   ```
   - In `HookedStartApp()` around line ~456, add Xiaomi TA name detection
   - This does not affect functionality — only diagnostic output

### Phase 3: Full port (with dynamic patches and OEM integration)

1. **Build and test mode-0** on popsicle:
   ```bash
   ./scripts/build.sh --mode 0 --verbose --debug
   ```

2. **Build and test mode-1** on popsicle:
   ```bash
   ./scripts/build.sh --mode 1 --debug
   ```

3. **Capture full boot logs**, verify:
   - All protocol hooks install successfully
   - `DeviceInfo` fields clear correctly on READ_CONFIG/VBDeviceInit
   - WRITE_CONFIG and VBDeviceResetState are swallowed
   - No OplusSec TA is detected (expected)
   - KeyMaster cmd-ids match expected Qualcomm set

4. **Test boot with stock images** (not custom recovery):
   - Flash stock recovery, vendor_boot, boot
   - Verify boot completes with locked/green state reported to kernel

### Phase 4: Recovery graft + custom recovery (optional, milestone work)

See the recovery graft plan in `docs/project/next-milestone.md` — same as for Oplus, but applied to Xiaomi recovery images.

## e. Build instructions

### Building for a new target (no code changes needed initially)

The project builds the same way regardless of target device. The device-specific behavior is determined at runtime by what protocols and partitions are available:

```bash
# Mode-0 (observation, safe):
cd /home/anto/gbl-chainload
./scripts/build.sh --mode 0 --debug --verbose

# Mode-1 (fakelock):
./scripts/build.sh --mode 1 --debug

# Dev capture (all logs visible):
./scripts/build.sh --mode 1 --debug --verbose --auto
```

Output:
- `dist/mode-0.efi` — observation build
- `dist/mode-1.efi` — fakelock build

### Adding device-specific patches

If you need to add Xiaomi-specific patches to the dynamic patch engine:

1. **In the Rust patch engine** (modern path):
   ```
   /home/anto/gbl-chainload/crates/patch-engine/src/
   ```
   Add a new patch group or extend the `abl_permissive` group with Xiaomi-specific strings.

2. **Build with the patch engine**:
   ```bash
   ./scripts/build.sh --mode 1
   ```

### Packing the GBLP1 container (for installation)

```bash
# Pack a cached ABL + manifest into the GBLP1 container format
cargo run --bin gbl -- pack \
  --out gbl-chainload.efi.packed \
  --cached-abl patched_abl.efi \
  --source raw_abl.img \
  --extracted stock_abl.efi \
  --manifest 0x0001   # 0x0001 = fakelock hook enabled
```

### Installing to EFISP

```bash
# Commit the file to the EFISP partition with backup + verify
cargo run --bin gbl -- commit \
  --src gbl-chainload.efi.packed \
  --dst /dev/block/gbl_chainload \
  --backup /sdcard/efisp.bak \
  --verify
```

---

## Summary of key differences

| Aspect | OnePlus/Oppo | Xiaomi (popsicle) | Change required? |
|---|---|---|---|
| `QCOM_VERIFIEDBOOT_PROTOCOL` | Present, 10 slots | Should be present | No |
| `QCOM_SCM_PROTOCOL` | Present, 5 slots | Should be present | No |
| `QCOM_QSEECOM_PROTOCOL` | Present, 2 slots | Should be present | No |
| OplusSec TA | Present, GUID-matched | Not present | No (code won't trigger) |
| SPSS protocol | Present | Unknown | Maybe (mode-2 only) |
| Partition `oplusreserve1` | Present | Not present | **Yes** — add Xiaomi names |
| `DeviceInfo` struct layout | Known offsets | Unknown | **Maybe** — verify offsets |
| ABL refusal strings (patch6/7) | Known | Unknown | **Yes** — add Xiaomi strings |
| `patch10` (libavb) | Works | Should work (Qualcomm libavb) | Likely no |
| KeyMaster cmd-ids | 0x200-0x219 range | Should be same | Likely no |
