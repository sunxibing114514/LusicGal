//! LusicGal 引擎壳共享工具（native/rust/lg_common）。
//!
//! 五个 Rust 核心（siglus / rfvp / sena / artemis + 未来 krkr-rs）的 FFI 壳
//! 共用：输入 JSON 解析、Android 上下文缓存、RGBA blit、事件发射。
//! 依赖刻意保持最小（仅 serde_json）。

pub mod android;
pub mod blit;
pub mod event;
pub mod input;

use std::ffi::c_void;

/// engine_abi.h 的 lg_event_cb_t。
pub type LgEventCb = unsafe extern "C" fn(*mut c_void, *const std::ffi::c_char);

/// engine_abi.h 的 LG_ABI_VERSION。
pub const LG_ABI_VERSION: u32 = 0x0002_0000;

/// lg_result_t（与 engine_abi.h 数值一致）。
pub mod result {
    pub const OK: i32 = 0;
    pub const INVALID_ARGUMENT: i32 = -1;
    pub const INVALID_STATE: i32 = -2;
    pub const NOT_SUPPORTED: i32 = -3;
    pub const IO: i32 = -4;
    pub const CORE: i32 = -5;
    pub const NOT_FOUND: i32 = -6;
    pub const TIMEOUT: i32 = -7;
}
