/** @file XiaomiOverlay.c — Xiaomi-specific hook policy implementation.

    Fakelock and persistence-suppression policies for Xiaomi devices
    (popsicle / Snapdragon 8 Gen 5). Activation is runtime-gated by
    callers on gManifest.WantFakelockHook / gManifest.WantProfileSpoof.

    Covers:
      - mitrustedui TA command dropping (fakelock mode-1)
      - VBRwDeviceState READ_CONFIG override (Xiaomi DeviceInfo offsets)
      - VBDeviceInit pre/post clear (Xiaomi-specific struct layout)
      - Initialization hook for Xiaomi-specific protocol additions
**/
#include "XiaomiOverlay.h"

#include <Library/DebugLib.h>
#include <Library/GblLog.h>
#include <Library/GblPayloadLib.h>
#include <Library/DeviceInfo.h>
#include <Protocol/EFIVerifiedBoot.h>
#include "FakelockOverlay.h"
#include "UniversalBaseline.h"

/* Xiaomi mitrustedui cmd-ids that must be dropped for fakelock.
 *
 * Xiaomi does not have OplusSec (GUID E11DDA6A-...), so its persistence
 * mechanism differs. The mitrustedui TA handles UI-level security state
 * but may also persist lock-state metadata to RPMB. Until ground-truth
 * from a stock-locked capture clarifies the exact cmd space, we only
 * drop writes to device-state that could re-lock persistence.
 *
 * TODO: confirm Xiaomi cmd-ids from --verbose captures on a stock
 * locked popsicle device, then replace 0xFF sentinel with actual values.
 */
#define XIAOMI_CMD_PERSISTENT_WRITE  0xFFU   /* TBD — placeholder sentinel */

BOOLEAN
XiaomiOverlay_ShouldDropQseeMiTrustedUi (
  IN  UINT32       CmdId,
  OUT EFI_STATUS  *FakeStatus
  )
{
  /* Placeholder: until ground-truth cmd-ids are confirmed from --verbose
   * captures on stock locked device, do not drop any mitrustedui commands
   * — the sentinel 0xFF will never match real cmd ids. */
  if (CmdId == XIAOMI_CMD_PERSISTENT_WRITE) {
    *FakeStatus = EFI_SUCCESS;
    GBL_INFO ("xmi-mitru | cmd=0x%02x(persistent_write) | DROPPED (mode-1)\n",
              CmdId);
    return TRUE;
  }
  return FALSE;
}

/* --------------------------------------------------------------------------
 * Xiaomi-specific DeviceInfo offset handling.
 *
 * The standard DeviceInfo struct (from <Library/DeviceInfo.h>) defines
 * is_unlocked and is_unlock_critical via C struct-of-zero casting.
 * If Xiaomi's BSP uses the same Qualcomm device_info_vb_t layout,
 * the offsets will match. If Xiaomi adds OEM-specific fields before
 * the standard fields, offsets would differ.
 *
 * Until evidence from a captured popsicle device shows different offsets,
 * we use the standard offset macros (mirrors FakelockOverlay.c pattern).
 * -------------------------------------------------------------------------- */

STATIC UINTN
XiaomiOffsetOfIsUnlocked (VOID)
{
  return (UINTN)&(((DeviceInfo *)0)->is_unlocked);
}

STATIC UINTN
XiaomiOffsetOfIsUnlockCritical (VOID)
{
  return (UINTN)&(((DeviceInfo *)0)->is_unlock_critical);
}

/* --------------------------------------------------------------------------
 * Xiaomi fakelock VB overlay — mirrors FakelockOverlay functions but
 * uses Xiaomi-specific offsets when they differ.
 * -------------------------------------------------------------------------- */

EFI_STATUS EFIAPI
XiaomiOverlay_OnVbReadConfig_Post (
  IN  EFI_STATUS  OrigStatus,
  IN  VOID       *Buf,
  IN  UINT32      BufLen
  )
{
  UINT8   *B;
  UINTN    IsUnlockedOff;
  UINTN    IsUnlockCriticalOff;
  BOOLEAN  OldUnlocked;
  BOOLEAN  OldUnlockCritical;

  if (EFI_ERROR (OrigStatus) || Buf == NULL) {
    return OrigStatus;
  }

  B                   = (UINT8 *)Buf;
  IsUnlockedOff       = XiaomiOffsetOfIsUnlocked ();
  IsUnlockCriticalOff = XiaomiOffsetOfIsUnlockCritical ();

  if ((UINTN)BufLen <= IsUnlockedOff ||
      (UINTN)BufLen <= IsUnlockCriticalOff) {
    DEBUG ((DEBUG_WARN,
            "xmi-vb | READ_CONFIG | buffer too small len=%u need>%u\n",
            BufLen, (UINT32)IsUnlockCriticalOff));
    return OrigStatus;
  }

  OldUnlocked       = B[IsUnlockedOff]       ? TRUE : FALSE;
  OldUnlockCritical = B[IsUnlockCriticalOff] ? TRUE : FALSE;
  B[IsUnlockedOff]       = 0;
  B[IsUnlockCriticalOff] = 0;

  GBL_INFO ("xmi-vb-fakelock | READ_CONFIG | is_unlocked %u->0 | is_unlock_critical %u->0\n",
            (UINT32)OldUnlocked, (UINT32)OldUnlockCritical);

  return OrigStatus;
}

EFI_STATUS EFIAPI
XiaomiOverlay_OnVbWriteConfig (
  IN UINT32  Op,
  IN VOID   *Buf,
  IN UINT32  BufLen
  )
{
  GBL_INFO ("xmi-vb-rwstate | op=WRITE_CONFIG | bufLen=%u | swallowed (mode-1)\n",
            BufLen);
  return EFI_SUCCESS;
}

/** Xiaomi VBDeviceInit pre/post clear.
    Mirrors FakelockOverlay_OnVbDeviceInit_PrePost but with a Xiaomi
    logging prefix so its traffic is distinguishable in logs.
    Currently delegates directly — offsets appear identical.
    Separate function so Xiaomi-specific offset logic can be swapped
    in later without changing the VerifiedBootHook call site. **/
VOID EFIAPI
XiaomiOverlay_OnVbDeviceInit_PrePost (
  IN OUT device_info_vb_t *Devinfo,
  IN     BOOLEAN           IsPre
  )
{
  BOOLEAN OldUnlocked;
  BOOLEAN OldUnlockCritical;

  if (Devinfo == NULL) {
    return;
  }

  OldUnlocked       = Devinfo->is_unlocked       ? TRUE : FALSE;
  OldUnlockCritical = Devinfo->is_unlock_critical ? TRUE : FALSE;
  Devinfo->is_unlocked        = FALSE;
  Devinfo->is_unlock_critical = FALSE;

  GBL_INFO ("xmi-vb-fakelock | VBDeviceInit/%a | is_unlocked %u->0 | is_unlock_critical %u->0\n",
            IsPre ? "pre" : "post",
            (UINT32)OldUnlocked, (UINT32)OldUnlockCritical);
}

EFI_STATUS
XiaomiInitProtocolHooks (VOID)
{
  /* Xiaomi-specific protocol hook additions:
     - VerifiedBoot hooks use XiaomiOverlay_* wrappers instead of
       FakelockOverlay_* wrappers
     - QSEECOM hooks use XiaomiHook instead of QseecomHook
     - SPU security level is assumed active (no config override needed
       — Xiaomi ABL sets vendor.gatekeeper.is_security_level_spu=1 at
       runtime)
     - KeyMint uses StrongBox NXP + Thales SE (same wire format as
       Qualcomm standard, so ProfileRewrite offsets apply unchanged)
  */
  GBL_INFO ("XiaomiOverlay: initialized for popsicle/pudding family\n");
  return EFI_SUCCESS;
}
