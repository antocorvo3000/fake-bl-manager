/** @file InstallAll.c -- universal + capability-gated hook dispatcher.

    Returns EFI_SUCCESS only if all required slot wrappers installed.
    Required-status for VerifiedBoot, Qseecom, and SPSS is derived from
    the runtime gManifest capability bits (WantFakelockHook,
    WantProfileSpoof). On required errors, caller must abort chain-load
    and fall through to FastbootLib; optional observation-only hooks may
    fail open.

    SCM and BlockIo are always required (safety baseline: SCM provides
    TZ_BLOW_SW_FUSE drop, BlockIo provides oplusreserve preservation).
    Universal-baseline policies live in the slot wrappers themselves.

    EbsHook is declared in HookCommon.h but not yet implemented; it is not
    called here until its source file lands.
**/
#include <Uefi/UefiGpt.h>
#include <Protocol/BlockIo.h>

#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/DebugLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/GblLog.h>
#include <Library/GblPayloadLib.h>

#include <Library/ProtocolHookLib.h>
#include <Library/DeviceInfo.h>

extern EFI_GUID  gEfiPartitionRecordGuid;

#include "HookCommon.h"
#include "XiaomiOverlay.h"

/** Probe BlockIo partition names for a Xiaomi-style GPT layout.
    If a "devinfo" partition exists, treat this device as Xiaomi/popsicle
    and force the OEM discriminant so downstream overlays are selected. **/
STATIC BOOLEAN
DetectXiaomiDevice (VOID)
{
  EFI_STATUS           Status;
  EFI_HANDLE          *Handles;
  UINTN                HandleCount;
  UINTN                Index;
  EFI_PARTITION_ENTRY *PartEntry;

  Status = gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid,
                                    NULL, &HandleCount, &Handles);
  if (EFI_ERROR (Status) || Handles == NULL) {
    return FALSE;
  }

  for (Index = 0; Index < HandleCount; Index++) {
    PartEntry = NULL;
    Status = gBS->HandleProtocol (Handles[Index], &gEfiPartitionRecordGuid,
                                  (VOID **)&PartEntry);
    if (EFI_ERROR (Status) || PartEntry == NULL) {
      continue;
    }
    if (HookCommonPartitionNameMatches (PartEntry->PartitionName, L"devinfo")) {
      gBS->FreePool (Handles);
      return TRUE;
    }
  }

  gBS->FreePool (Handles);
  return FALSE;
}

EFI_STATUS
EFIAPI
ProtocolHook_InstallAll (
  OUT HOOK_INSTALL_RESULT  *Result
  )
{
  EFI_STATUS Status;

  if (Result == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  ZeroMem (Result, sizeof (*Result));

  /* Detect Xiaomi early so VerifiedBoot/BlockIo overlays can route to the
     correct OEM policy before any hooks are installed. */
  if (DetectXiaomiDevice ()) {
    gManifest.Oem = GBL_OEM_XIAOMI;
    GBL_INFO ("ProtocolHookLib: detected Xiaomi device (devinfo present)\n");
  }

  /* 1. VerifiedBoot -- required iff fakelock-hook cap is set
        (fakelock/persistence overlay needs the VB slot mutators);
        otherwise optional observation-only wrapper. */
  Status = InstallVerifiedBootHook ();
  if (EFI_ERROR (Status)) {
    if (gManifest.WantFakelockHook) {
      Print (L"ProtocolHookLib: FATAL — VerifiedBoot install failed (%r), aborting chain-load\n",
             Status);
      return Status;
    }
    Print (L"ProtocolHookLib: VerifiedBoot install failed (%r) - continuing (observation-only)\n",
           Status);
    Result->VbInstalledSlots = 0;
  } else {
    Result->VbInstalledSlots = 1;
  }
  Result->VbExpectedSlots  = 1;

  /* 2. SCM -- required.  Universal TZ_BLOW_SW_FUSE drop. */
  Status = InstallScmHook ();
  if (EFI_ERROR (Status)) {
    Print (L"ProtocolHookLib: FATAL — SCM install failed (%r), aborting chain-load\n",
           Status);
    return Status;
  }
  Result->ScmInstalledSlots = 1;
  Result->ScmExpectedSlots  = 1;

  /* 3. Qseecom -- required iff either fakelock (OplusSec suppression) or
        profile-spoof (KM attestation overlay) cap is set; otherwise
        optional observation-only wrapper. */
  Status = InstallQseecomHook ();
  if (EFI_ERROR (Status)) {
    if (gManifest.WantFakelockHook || gManifest.WantProfileSpoof) {
      Print (L"ProtocolHookLib: FATAL — Qseecom install failed (%r), aborting chain-load\n",
             Status);
      return Status;
    }
    Print (L"ProtocolHookLib: Qseecom install failed (%r) - continuing (observation-only)\n",
           Status);
    Result->QseecomInstalledSlots = 0;
  } else {
    Result->QseecomInstalledSlots = 1;
  }
  Result->QseecomExpectedSlots  = 1;

  /* 4. SPSS -- required iff profile-spoof cap is set (KM/SPSS attestation
        overlay needs the ShareKeyMintInfo mutator); otherwise optional
        observation-only. */
  Status = InstallSpssHook ();
  if (EFI_ERROR (Status)) {
    if (gManifest.WantProfileSpoof) {
      Print (L"ProtocolHookLib: FATAL — SPSS install failed (%r), aborting chain-load\n",
             Status);
      return Status;
    }
    Print (L"ProtocolHookLib: SPSS install failed (%r) - continuing (observation-only)\n",
           Status);
    Result->SpssInstalledSlots = 0;
  } else {
    Result->SpssInstalledSlots = 1;
  }
  Result->SpssExpectedSlots = 1;

  /* 5. BlockIo -- required for Oplus reserve preservation.  This hook
        observes partition reads/writes and swallows oplusreserve1 writes. */
  Status = InstallBlockIoHook ();
  if (EFI_ERROR (Status)) {
    Print (L"ProtocolHookLib: FATAL — BlockIo install failed (%r), aborting chain-load\n",
           Status);
    return Status;
  }
  Result->BlockIoInstalledSlots = 1;
  Result->BlockIoExpectedSlots  = 1;

  /* 6. Xiaomi (popsicle) -- capability-gated hooks for Xiaomi devices.
        Detects Xiaomi by checking for mitrustedui service or popsicle
        ro.product.name. Installs Xiaomi-specific overlays on top of
        standard baseline hooks. Activated when fakelock or profile-spoof
        caps are set AND device is detected as Xiaomi. */
  {
    BOOLEAN IsXiaomi = FALSE;

    /* Check ro.product.name via HII / or check for mitrustedui service.
     * In EDK2 environment, we probe via gBS->LocateProtocol for Xiaomi-
     * specific indicators, or use device tree compatible string.
     * For now, we rely on gManifest.Oem discriminant set at build time. */
    if (gManifest.Oem == GBL_OEM_XIAOMI) {
      IsXiaomi = TRUE;
    }

    if (IsXiaomi && (gManifest.WantFakelockHook || gManifest.WantProfileSpoof)) {
      Status = InstallXiaomiHook ();
      if (EFI_ERROR (Status)) {
        if (gManifest.WantFakelockHook) {
          Print (L"ProtocolHookLib: FATAL — XiaomiHook install failed (%r), aborting chain-load\n",
                 Status);
          return Status;
        }
        Print (L"ProtocolHookLib: XiaomiHook install failed (%r) - continuing (observation-only)\n",
               Status);
      } else {
        Result->XiaomiInstalledSlots = 1;
        /* Initialize Xiaomi-specific protocol hooks */
        XiaomiInitProtocolHooks ();
      }
    }
    Result->XiaomiExpectedSlots = IsXiaomi ? 1 : 0;
  }

  /* Aggregate -- all required hooks must be installed. */
  Result->UniversalRequiredOk =
    (Result->ScmInstalledSlots   > 0 &&
     Result->BlockIoInstalledSlots > 0);

  if (!Result->UniversalRequiredOk) {
    Print (L"ProtocolHookLib: FATAL — universal baseline incomplete, aborting chain-load\n");
    return EFI_NOT_READY;
  }

  Result->ModeOverlayOk = TRUE;   /* Mode-specific overlays are inline/opt-in. */

  GBL_INFO (
    "ProtocolHookLib: installed (fakelock=%u profile_spoof=%u,"
    " vb=%u/%u scm=%u/%u qsee=%u/%u spss=%u/%u blockio=%u/%u xiaomi=%u/%u)\n",
    (UINT32)gManifest.WantFakelockHook,
    (UINT32)gManifest.WantProfileSpoof,
    Result->VbInstalledSlots,      Result->VbExpectedSlots,
    Result->ScmInstalledSlots,     Result->ScmExpectedSlots,
    Result->QseecomInstalledSlots, Result->QseecomExpectedSlots,
    Result->SpssInstalledSlots,    Result->SpssExpectedSlots,
    Result->BlockIoInstalledSlots, Result->BlockIoExpectedSlots,
    Result->XiaomiInstalledSlots,  Result->XiaomiExpectedSlots
    );
  return EFI_SUCCESS;
}
