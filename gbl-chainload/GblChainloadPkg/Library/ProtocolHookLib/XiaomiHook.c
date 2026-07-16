/** @file XiaomiHook.c — verbose hook for QCOM_QSEECOM_PROTOCOL (Xiaomi / popsicle).

    Mirrors the structure of QseecomHook.c but detects Xiaomi-specific
    TrustZone app "mitrustedui" instead of OplusSec TA.

    Key differences:
      - Xiaomi uses "mitrustedui" (ASCII TA name) rather than a GUID-based
        OplusSec (GUID E11DDA6A-651B-4AB4-B8C5-30B352B472E2).
      - Xiaomi KeyMint commands use the same Qualcomm cmd-id space
        (0x200+ SET_ROT, SET_BOOT_STATE, etc.) but may have additional
        Xiaomi-specific cmd ids.
      - Xiaomi uses SPU security level (vendor.gatekeeper.is_security_level_spu = 1)
        and StrongBox NXP + Thales secure element for KeyMint.

    The QSEECOM protocol mechanics are Qualcomm-standard (StartApp /
    SendCmd), so the hook infrastructure is identical — only the TA
    identification and cmd-space interpretation differ.
**/

#include <Uefi.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/GblLog.h>
#include <Library/GblPayloadLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Protocol/EFIQseecom.h>
#include "HookCommon.h"
#include "ProfileOverlay.h"
#include "UniversalBaseline.h"
#include "XiaomiOverlay.h"

STATIC QCOM_QSEECOM_SEND_CMD_APP gOriginalSendCmd  = NULL;
STATIC QCOM_QSEECOM_START_APP    gOriginalStartApp = NULL;
STATIC QCOM_QSEECOM_PROTOCOL    *gHookedProtocol   = NULL;

HOOK_REENTRY_DEFINE (gXiaomiSendGuard);
HOOK_REENTRY_DEFINE (gXiaomiStartGuard);

/* Track the handle of the Xiaomi mitrustedui TA. -1U means "not yet known". */
STATIC UINT32 gMiTrustedUiHandle = (UINT32)-1;

#define XIAOMI_TA_APPNAME  "mitrustedui"   /* ASCII — not GUID */
#define QSEE_APPNAME_MAX    64u

/* ---- Helpers (mirror QseecomHook.c) ---- */

/** Format up-to-MaxBytes bytes of Buf as lowercase hex into Out.
    Out must be >= MaxBytes*2 + 1. Always NUL-terminates. **/
STATIC VOID
XiaomiHexN (
  IN  CONST UINT8 *Buf,
  IN  UINT32       Len,
  IN  UINTN        MaxBytes,
  OUT CHAR8       *Out,
  IN  UINTN        OutSize
  )
{
  STATIC CONST CHAR8 kHex[] = "0123456789abcdef";
  UINTN Take, i, j;

  if (Out == NULL || OutSize == 0) return;
  Out[0] = '\0';
  if (Buf == NULL) { AsciiStrCpyS (Out, OutSize, "(null)"); return; }
  if (Len == 0)    { AsciiStrCpyS (Out, OutSize, "(empty)"); return; }

  Take = (Len < MaxBytes) ? Len : MaxBytes;
  if (OutSize < (Take * 2 + 1)) {
    Take = (OutSize - 1) / 2;
  }

  for (i = 0, j = 0; i < Take; i++) {
    Out[j++] = kHex[(Buf[i] >> 4) & 0xF];
    Out[j++] = kHex[ Buf[i]       & 0xF];
  }
  Out[j] = '\0';
}

/** Copy up to QSEE_APPNAME_MAX bytes as bounded ASCII name.
    Returns TRUE if a valid ASCII name was copied (printable chars 0x20–0x7e).
*/
STATIC BOOLEAN
XiaomiCopyBoundedAsciiAppName (
  IN  CONST CHAR8 *AppName,
  OUT CHAR8       *Out,
  IN  UINTN        OutSize
  )
{
  UINTN i;

  if (Out == NULL || OutSize == 0) {
    return FALSE;
  }
  Out[0] = '\0';

  if (AppName == NULL) {
    return FALSE;
  }

  for (i = 0; i < QSEE_APPNAME_MAX && i + 1 < OutSize; i++) {
    CHAR8 Ch = AppName[i];
    if (Ch == '\0') {
      Out[i] = '\0';
      return i > 0;
    }
    if ((UINT8)Ch < 0x20 || (UINT8)Ch > 0x7e) {
      Out[0] = '\0';
      return FALSE;
    }
    Out[i] = Ch;
  }

  Out[0] = '\0';
  return FALSE;
}

/** Detect the Xiaomi mitrustedui TA by its ASCII name string. **/
STATIC BOOLEAN
IsMiTrustedUiName (
  IN CONST CHAR8 *AppNameAscii
  )
{
  if (AppNameAscii == NULL) {
    return FALSE;
  }
  return AsciiStrCmp (AppNameAscii, XIAOMI_TA_APPNAME) == 0;
}

/** Read a u32 little-endian from Buf[Off..Off+4) if in bounds; else 0. **/
STATIC UINT32
XiaomiReadU32At (
  IN CONST UINT8 *Buf,
  IN UINT32       Len,
  IN UINT32       Off
  )
{
  UINT32 V = 0;
  if (Buf == NULL || Off > Len || Len - Off < 4) return 0;
  CopyMem (&V, Buf + Off, sizeof (V));
  return V;
}

/* -----------------------------------------------------------
 * KeyMaster cmd-id decoder (same Qualcomm cmd space as QseecomHook.c,
 * but Xiaomi may carry additional OEM-specific cmd ids).
 * ----------------------------------------------------------- */

STATIC VOID
XiaomiDecodeKnownCmd (
  IN UINT32       CmdId,
  IN UINT32       Handle,
  IN CONST UINT8 *SendBuf,
  IN UINT32       SendLen,
  IN CONST UINT8 *RspBuf,
  IN UINT32       RspLen,
  IN EFI_STATUS   Status
  )
{
  CHAR8 Hex[65];

  switch (CmdId) {

    case 0x00000200: {
      /* Probe / get-version. */
      UINT32 RStatus = XiaomiReadU32At (RspBuf, RspLen, 0);
      UINT32 VMaj    = XiaomiReadU32At (RspBuf, RspLen, 4);
      UINT32 VMin    = XiaomiReadU32At (RspBuf, RspLen, 8);
      UINT32 VBld    = XiaomiReadU32At (RspBuf, RspLen, 12);
      UINT32 BId     = XiaomiReadU32At (RspBuf, RspLen, 16);
      VERBOSE ("xmi-km | cmd=0x%08x(probe) | h=%u | rstatus=0x%x | "
               "ver=%u.%u.%u | buildId=0x%x | st=%r\n",
               CmdId, Handle, RStatus, VMaj, VMin, VBld, BId, Status);
      (VOID)RStatus; (VOID)VMaj; (VOID)VMin; (VOID)VBld; (VOID)BId;
      break;
    }

    case 0x00000201: {
      /* SET_ROT — KmSetRotReqWire (44 B).
         Xiaomi same format; RoT digest is SHA256(AVBPubKey || IsUnlockedByte). */
      UINT32 RotOffset = XiaomiReadU32At (SendBuf, SendLen, 4);
      UINT32 RotSize   = XiaomiReadU32At (SendBuf, SendLen, 8);
      XiaomiHexN (SendBuf + 12, (SendLen >= 12) ? (SendLen - 12) : 0, 32,
                  Hex, sizeof (Hex));
      GBL_INFO ("xmi-km | cmd=0x%08x(SET_ROT) | h=%u | offset=%u | size=%u | "
                "rotDigest=%a | st=%r\n",
                CmdId, Handle, RotOffset, RotSize, Hex, Status);
      break;
    }

    case 0x00000202: {
      UINT32 AddrLo = XiaomiReadU32At (SendBuf, SendLen, 4);
      UINT32 AddrHi = XiaomiReadU32At (SendBuf, SendLen, 8);
      VERBOSE ("xmi-km | cmd=0x%08x(READ_KM_DEVICE_STATE) | h=%u | "
               "addr=0x%x_%08x | st=%r\n",
               CmdId, Handle, AddrHi, AddrLo, Status);
      (VOID)AddrLo; (VOID)AddrHi;
      break;
    }

    case 0x00000203: {
      /* WRITE_KM_DEVICE_STATE — write mutation */
      UINT32 AddrLo = XiaomiReadU32At (SendBuf, SendLen, 4);
      UINT32 AddrHi = XiaomiReadU32At (SendBuf, SendLen, 8);
      GBL_INFO ("xmi-km | cmd=0x%08x(WRITE_KM_DEVICE_STATE) | h=%u | "
                "addr=0x%x_%08x | st=%r\n",
                CmdId, Handle, AddrHi, AddrLo, Status);
      break;
    }

    case 0x00000204: {
      /* MILESTONE_CALL */
      GBL_INFO ("xmi-km | cmd=0x%08x(MILESTONE_CALL) | h=%u | st=%r\n",
                CmdId, Handle, Status);
      break;
    }

    case 0x00000207: {
      /* SET_VERSION */
      UINT32 Ver = XiaomiReadU32At (SendBuf, SendLen, 4);
      UINT32 Spl = XiaomiReadU32At (SendBuf, SendLen, 8);
      GBL_INFO ("xmi-km | cmd=0x%08x(SET_VERSION) | h=%u | osVer=0x%x | "
                "spl=0x%x | st=%r\n",
                CmdId, Handle, Ver, Spl, Status);
      break;
    }

    case 0x00000208: {
      /* SET_BOOT_STATE — KmSetBootStateReqWire (64 B).
         Xiaomi uses SPU security level but same wire format as
         standard Keymaster (Color: 0=GREEN, 1=YELLOW, 2=ORANGE, 3=RED). */
      UINT32 Version = XiaomiReadU32At (SendBuf, SendLen, 4);
      UINT32 Offset  = XiaomiReadU32At (SendBuf, SendLen, 8);
      UINT32 Size    = XiaomiReadU32At (SendBuf, SendLen, 12);
      UINT32 Unlk    = XiaomiReadU32At (SendBuf, SendLen, 16);
      UINT32 Color   = XiaomiReadU32At (SendBuf, SendLen, 16 + 4 + 32);
      UINT32 SysVer  = XiaomiReadU32At (SendBuf, SendLen, 16 + 4 + 32 + 4);
      UINT32 SysSpl  = XiaomiReadU32At (SendBuf, SendLen, 16 + 4 + 32 + 8);
      XiaomiHexN (SendBuf + 20, (SendLen >= 20) ? (SendLen - 20) : 0, 32,
                  Hex, sizeof (Hex));
      GBL_INFO ("xmi-km | cmd=0x%08x(SET_BOOT_STATE) | h=%u | ver=%u | "
                "offset=%u | size=%u | isUnlocked=%u | pubKey=%a | "
                "color=%u | sysVer=0x%x | sysSpl=0x%x | st=%r\n",
                CmdId, Handle, Version, Offset, Size, Unlk, Hex, Color,
                SysVer, SysSpl, Status);
      break;
    }

    case 0x00000211: {
      /* SET_VBH */
      XiaomiHexN (SendBuf + 4, (SendLen >= 4) ? (SendLen - 4) : 0, 32,
                  Hex, sizeof (Hex));
      GBL_INFO ("xmi-km | cmd=0x%08x(SET_VBH) | h=%u | vbh=%a | st=%r\n",
                CmdId, Handle, Hex, Status);
      break;
    }

    case 0x00000218: {
      /* FBE_SET_SEED — DO NOT mutate (same as QseecomHook). */
      UINT32 SeedCrc = 0;
      if (SendBuf != NULL && SendLen > 4) {
        SeedCrc = CalculateCrc32 ((VOID *)(SendBuf + 4), (UINTN)(SendLen - 4));
      }
      GBL_INFO ("xmi-km | cmd=0x%08x(FBE_SET_SEED) | h=%u | sl=%u | "
                "seedCrc=0x%08x | st=%r | DO-NOT-MUTATE\n",
                CmdId, Handle, SendLen, SeedCrc, Status);
      break;
    }

    case 0x00000219: {
      /* GENERATE_FRS_AND_UDS — DO NOT mutate */
      UINT32 FdrFlag   = XiaomiReadU32At (SendBuf, SendLen, 4);
      UINT32 FrsSecLen = XiaomiReadU32At (SendBuf, SendLen, 8);
      VERBOSE ("xmi-km | cmd=0x%08x(GENERATE_FRS_AND_UDS) | h=%u | "
               "fdrFlag=0x%x | frsSecLen=%u | st=%r | DO-NOT-MUTATE\n",
               CmdId, Handle, FdrFlag, FrsSecLen, Status);
      (VOID)FdrFlag; (VOID)FrsSecLen;
      break;
    }

    default:
      /* Unknown cmd — skip; generic qsee line covers raw bytes. */
      break;
  }
}

/* -----------------------------------------------------------
 * mitrustedui cmd-id decoder
 * ----------------------------------------------------------- */

STATIC VOID
XiaomiDecodeMiTrustedUiCmd (
  IN UINT32       CmdId,
  IN UINT32       Handle,
  IN CONST UINT8 *SendBuf,
  IN UINT32       SendLen,
  IN CONST UINT8 *RspBuf,
  IN UINT32       RspLen,
  IN EFI_STATUS   Status
  )
{
  switch (CmdId) {
    case 0x00000004: {
      /* Version query — mirror OplusSec pattern but for mitrustedui. */
      VERBOSE ("xmi-mitru | cmd=0x%02x(GetVersion) | h=%u | sl=%u | rl=%u | st=%r\n",
               CmdId, Handle, SendLen, RspLen, Status);
      break;
    }

    default: {
      VERBOSE ("xmi-mitru | cmd=0x%02x(unknown) | h=%u | sl=%u | rl=%u | st=%r\n",
               CmdId, Handle, SendLen, RspLen, Status);
      break;
    }
  }
}

/* -----------------------------------------------------------
 * Wrapper functions (mirror QseecomHook.c exactly)
 * ----------------------------------------------------------- */

STATIC EFI_STATUS EFIAPI
XiaomiHookedStartApp (
  IN  QCOM_QSEECOM_PROTOCOL *This,
  IN  CHAR8                 *AppName,
  OUT UINT32                *Handle
  )
{
  EFI_STATUS Status;
  BOOLEAN    First;
  UINT32     OutHandle = 0;
  CHAR8      AppNameAscii[QSEE_APPNAME_MAX];

  First = HookEnter (&gXiaomiStartGuard);

  if (gOriginalStartApp == NULL) {
    HookLeave (&gXiaomiStartGuard);
    return EFI_NOT_READY;
  }

  if (!First) {
    Status = gOriginalStartApp (This, AppName, Handle);
    HookLeave (&gXiaomiStartGuard);
    return Status;
  }

  Status = gOriginalStartApp (This, AppName, Handle);
  if (Handle != NULL) {
    OutHandle = *Handle;
  }

  if (XiaomiCopyBoundedAsciiAppName (AppName, AppNameAscii,
                                     sizeof (AppNameAscii))) {
    GBL_INFO ("xmi-start | app=\"%a\" | h=%u | st=%r\n",
              AppNameAscii, OutHandle, Status);
  } else {
    GBL_INFO ("xmi-start | app=<non-ascii-or-unbounded> | h=%u | st=%r\n",
              OutHandle, Status);
  }

  /* Xiaomi's mitrustedui TA identification */
  if (!EFI_ERROR (Status) && IsMiTrustedUiName (AppNameAscii)) {
    gMiTrustedUiHandle = OutHandle;
    GBL_INFO ("xmi-start: tagged %a h=%u as Xiaomi mitrustedui TA\n",
              AppNameAscii, OutHandle);
  }

  HookLeave (&gXiaomiStartGuard);
  return Status;
}

STATIC EFI_STATUS EFIAPI
XiaomiHookedSendCmd (
  IN     QCOM_QSEECOM_PROTOCOL *This,
  IN     UINT32                 Handle,
  IN     UINT8                 *SendBuf,
  IN     UINT32                 SendLen,
  IN OUT UINT8                 *RspBuf,
  IN     UINT32                 RspLen
  )
{
  EFI_STATUS Status;
  BOOLEAN    First;
  UINT32     CmdId = 0;
  CHAR8      SendHex[65];
  CHAR8      RspHex[65];

  First = HookEnter (&gXiaomiSendGuard);

  if (gOriginalSendCmd == NULL) {
    HookLeave (&gXiaomiSendGuard);
    return EFI_NOT_READY;
  }

  if (SendBuf != NULL && SendLen >= sizeof (UINT32)) {
    CopyMem (&CmdId, SendBuf, sizeof (CmdId));
  }

  /* Xiaomi fakelock policy: if mitrustedui handle is known and
     Xiaomi overlay signals a drop, swallow the command.
     Mirrors FakelockOverlay_ShouldDropQseeOplusSec logic. */
  if (gManifest.WantFakelockHook &&
      Handle == gMiTrustedUiHandle && Handle != (UINT32)-1) {
    EFI_STATUS FakeStatus;
    if (XiaomiOverlay_ShouldDropQseeMiTrustedUi (CmdId, &FakeStatus)) {
      HookLeave (&gXiaomiSendGuard);
      return FakeStatus;
    }
  }

  /* Xiaomi profile-spoof policy: rewrite KM send buffers from profile. */
  if (gManifest.WantProfileSpoof && First && SendBuf != NULL) {
    ProfileOverlay_RewriteKmSend (CmdId, SendBuf, SendLen);
  }

  if (!First) {
    Status = gOriginalSendCmd (This, Handle, SendBuf, SendLen, RspBuf, RspLen);
    HookLeave (&gXiaomiSendGuard);
    return Status;
  }

  Status = gOriginalSendCmd (This, Handle, SendBuf, SendLen, RspBuf, RspLen);

  /* Generic qsee summary line (32 B prefix) */
  XiaomiHexN (SendBuf, SendLen, 32, SendHex, sizeof (SendHex));
  XiaomiHexN (RspBuf,  RspLen,  32, RspHex,  sizeof (RspHex));
  VERBOSE ("xmi-qsee | cmd=0x%08x | h=%u | sl=%u | s32=%a | rl=%u | r32=%a | st=%r\n",
           CmdId, Handle, SendLen, SendHex, RspLen, RspHex, Status);

  /* KeyMaster cmd-id structured decoder */
  XiaomiDecodeKnownCmd (CmdId, Handle, SendBuf, SendLen, RspBuf, RspLen, Status);

  /* miTrustedUi TA-specific decoder */
  if (Handle == gMiTrustedUiHandle && Handle != (UINT32)-1) {
    XiaomiDecodeMiTrustedUiCmd (CmdId, Handle,
                                SendBuf, SendLen,
                                RspBuf, RspLen, Status);
  }

  HookLeave (&gXiaomiSendGuard);
  return Status;
}

/* -----------------------------------------------------------
 * Installation
 * ----------------------------------------------------------- */

EFI_STATUS
InstallXiaomiHook (VOID)
{
  EFI_STATUS              Status;
  QCOM_QSEECOM_PROTOCOL  *Qseecom = NULL;

  if (gHookedProtocol != NULL) {
    return EFI_ALREADY_STARTED;
  }

  Status = gBS->LocateProtocol (&gQcomQseecomProtocolGuid, NULL,
                                (VOID **)&Qseecom);
  if (EFI_ERROR (Status) || Qseecom == NULL) {
    Print (L"XiaomiHook: LocateProtocol failed: %r\n", Status);
    return Status;
  }

  if (Qseecom->QseecomSendCmd == NULL || Qseecom->QseecomStartApp == NULL) {
    Print (L"XiaomiHook: SendCmd or StartApp slot is NULL\n");
    return EFI_NOT_READY;
  }

  gOriginalStartApp        = Qseecom->QseecomStartApp;
  gOriginalSendCmd         = Qseecom->QseecomSendCmd;
  Qseecom->QseecomStartApp = XiaomiHookedStartApp;
  Qseecom->QseecomSendCmd  = XiaomiHookedSendCmd;
  gHookedProtocol          = Qseecom;

  GBL_INFO ("XiaomiHook: installed StartApp=%p SendCmd=%p (orig start=%p send=%p)\n",
            XiaomiHookedStartApp, XiaomiHookedSendCmd,
            gOriginalStartApp, gOriginalSendCmd);
  return EFI_SUCCESS;
}
