//! patch7 — orange-screen / unlock-warning / 5-second boot-delay gate (Xiaomi / popsicle).
//!
//! Xiaomi variant: the ABL uses the string pair
//! `"Your device is corrupt. It can't be trusted to run any applications."`
//! + `"orange"` as the corruption-warning anchor, replacing the Oplus
//! `"Your device has been unlocked and can't be trusted"` anchor.
//!
//! The CBZ gating the warning block is found by walking backward from the
//! ADRP+ADD pair that loads the corrupt string. Window and patch logic
//! are identical to the Oplus port.
//!
//! Confirmed on popsicle 17 Pro Max (Xiaomi Snapdragon 8 Gen 5).
//!
//! Non-mandatory — cosmetic only.

use crate::internal::arm64_decode::{decode_branch, find_adrp_add_targeting, Arm64InsnKind};
use crate::internal::encode::{read_instr_u32, rewrite_b_uncond};
use crate::internal::scan::{scan_for, ScanResult};
use crate::PatchOutcome;

/// Patch7 anchor — the corruption warning text in Xiaomi ABL.
pub const PATCH7_WARN_STR_XIAOMI: &[u8] =
    b"Your device is corrupt. It can't be trusted to run any applications.";

/// Backward-scan window (bytes) from the warning-string ADRP to the guard CBZ.
pub const PATCH7_BACK_SCAN_WINDOW: u32 = 0x40;

/// Xiaomi patch7 apply function.
pub fn apply(buf: &mut [u8], size: u32) -> PatchOutcome {
    let active = &mut buf[..size as usize];

    // 1. Locate the warning string. Absent → clean MISS (non-Xiaomi ABL).
    let (r, str_off) = scan_for(active, PATCH7_WARN_STR_XIAOMI, None);
    match r {
        ScanResult::Found => {}
        ScanResult::Ambiguous => return PatchOutcome::Ambiguous,
        _ => return PatchOutcome::Miss,
    }

    // 2. Resolve the unique ADRP+ADD pair targeting the warning string.
    let (r, adrp_off) = find_adrp_add_targeting(active, str_off, true);
    match r {
        ScanResult::Found => {}
        ScanResult::Ambiguous => return PatchOutcome::Ambiguous,
        _ => return PatchOutcome::Miss,
    }
    if adrp_off < 4 {
        return PatchOutcome::Miss;
    }

    // 3. Walk backward to the lock-state guard.
    //    CBZ Wn               → rewrite to unconditional B (skip warning)
    //    forward unconditional B → already patched (idempotent)
    let lo = if adrp_off > PATCH7_BACK_SCAN_WINDOW {
        adrp_off - PATCH7_BACK_SCAN_WINDOW
    } else {
        4
    };
    let mut probe = adrp_off - 4;
    loop {
        if probe < lo {
            break;
        }
        let word = read_instr_u32(active, probe);
        if let Some(decoded) = decode_branch(word, probe) {
            if decoded.kind == Arm64InsnKind::CbzW {
                rewrite_b_uncond(active, probe, decoded.target_off);
                return PatchOutcome::Ok;
            }
            if decoded.kind == Arm64InsnKind::B && decoded.target_off > probe {
                // Guard already rewritten — idempotent OK.
                return PatchOutcome::Ok;
            }
        }
        if probe < 4 {
            break;
        }
        probe -= 4;
    }

    PatchOutcome::Miss
}
