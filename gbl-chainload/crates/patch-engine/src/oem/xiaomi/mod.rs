//! Xiaomi (popsicle) family OEM patches.
//!
//! Port for Xiaomi Snapdragon 8 Gen 5 devices. Currently holds patch7
//! (orange-screen / corruption-warning gate) using the Xiaomi-specific
//! anchor string. Selected at host build time by `abl-patcher --oem xiaomi`.

pub mod bypass_warning;

use crate::{PatchDesc, PatchScope};

/// All Xiaomi-family OEM patches.
pub const OEM_XIAOMI_PATCHES: &[PatchDesc] = &[
    PatchDesc {
        name: "patch7-orange-screen-xiaomi",
        scope: PatchScope::OemXiaomi,
        mandatory: false,
        apply: bypass_warning::apply,
    },
];
