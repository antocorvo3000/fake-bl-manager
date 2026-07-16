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

/** Initialize Xiaomi-specific protocol hook additions.
    Called from InstallAll.c when popsicle is detected. **/
EFI_STATUS
XiaomiInitProtocolHooks (VOID);

#endif /* XIAOMI_OVERLAY_H_ */
