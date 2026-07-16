/** @file XiaomiOverlay.h — Xiaomi-specific hook policy declarations.

    Activation is runtime-gated at the call sites on
    gManifest.WantFakelockHook and gManifest.WantProfileSpoof
    (same gating as FakelockOverlay / ProfileOverlay).

    Covers:
      - mitrustedui TA command interception (fakelock mode-1)
      - SPU security level handling (Xiaomi-specific KeyMint config)
      - DeviceInfo struct offset overrides for Xiaomi devices
**/
#ifndef XIAOMI_OVERLAY_H_
#define XIAOMI_OVERLAY_H_

#include <Uefi.h>
#include <Protocol/EFIVerifiedBoot.h>
#include "HookCommon.h"

/** Xiaomi fakelock policy for mitrustedui QSEECOM commands.
    Returns TRUE and writes EFI_SUCCESS into FakeStatus when the caller
    should drop the command (e.g. cmd 0x0A write_rpmb_boot_info
    equivalent on Xiaomi). Returns FALSE for all other commands —
    caller proceeds with passthrough.

    Caller already determined Handle == gMiTrustedUiHandle. **/
BOOLEAN
XiaomiOverlay_ShouldDropQseeMiTrustedUi (
  IN  UINT32       CmdId,
  OUT EFI_STATUS  *FakeStatus
  );

/** Xiaomi fakelock policy for VBRwDeviceState(READ_CONFIG) post-call mutator.
    Clears is_unlocked and is_unlock_critical in the returned device-state
    buffer. Returns OrigStatus unchanged. **/
EFI_STATUS EFIAPI
XiaomiOverlay_OnVbReadConfig_Post (
  IN  EFI_STATUS  OrigStatus,
  IN  VOID       *Buf,
  IN  UINT32      BufLen
  );

/** Xiaomi fakelock policy for VBDeviceInit pre/post clear. **/
VOID EFIAPI
XiaomiOverlay_OnVbDeviceInit_PrePost (
  IN OUT device_info_vb_t *Devinfo,
  IN     BOOLEAN           IsPre
  );

/** Xiaomi fakelock policy for VBRwDeviceState(WRITE_CONFIG). Returns
    EFI_SUCCESS and does NOT forward to the original. **/
EFI_STATUS EFIAPI
XiaomiOverlay_OnVbWriteConfig (
  IN UINT32  Op,
  IN VOID   *Buf,
  IN UINT32  BufLen
  );

/** Initialize Xiaomi-specific protocol hook additions.
    Called from InstallAll.c when popsicle is detected. **/
EFI_STATUS
XiaomiInitProtocolHooks (VOID);

#endif /* XIAOMI_OVERLAY_H_ */

