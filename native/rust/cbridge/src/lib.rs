//! LusicGal Rust FFI 门面。
//!
//! rfvp / siglus_rs / sena-rs（均 MPL-2.0，文件级许可）以 `staticlib` 接入时，
//! 经由此 crate 导出 `native/include/lusicgal/engine_abi.h` 约定的
//! `lg_<id>_*` 符号（iOS 静态链接必须前缀去重；Android 用 cdylib）。
//!
//! 当前为核心占位（返回 NOT_SUPPORTED）—— 真实核心接线见 docs/ROADMAP.md v0.4。

use std::os::raw::{c_char, c_int, c_void};

pub const LG_OK: c_int = 0;
pub const LG_ERR_INVALID_ARGUMENT: c_int = -1;
pub const LG_ERR_NOT_SUPPORTED: c_int = -3;
pub const LG_ABI_VERSION: u32 = 0x0001_0000;

/// 与 engine_abi.h `lg_engine_desc_t` 二进制兼容。
#[repr(C)]
pub struct LgEngineDesc {
    pub struct_size: u32,
    pub abi_version: u32,
    pub engine_id: *const c_char,
    pub game_id: *const c_char,
    pub game_path: *const c_char,
    pub save_path: *const c_char,
    pub cache_path: *const c_char,
    pub options_json: *const c_char,
    pub host: *mut c_void,
    pub reserved_ptr: [*mut c_void; 8],
    pub reserved_u64: [u64; 8],
}

pub type LgEngine = c_void;
pub type LgEventCb = extern "C" fn(host: *mut c_void, json: *const c_char);

#[no_mangle]
pub extern "C" fn lg_abi_version() -> u32 {
    LG_ABI_VERSION
}

/// 桥自身探活（dlsym 目标，验证 Rust 门面已链接）。
#[no_mangle]
pub extern "C" fn lg_cbridge_probe() -> *const c_char {
    b"{\"core\":\"lusicgal-cbridge\",\"engines\":[\"rfvp\",\"siglus\",\"sena\"]}\0"
        .as_ptr() as *const c_char
}

macro_rules! core_stub {
    ($create:ident, $start:ident, $cmd:ident, $surface:ident, $destroy:ident, $abi:ident) => {
        #[no_mangle]
        pub extern "C" fn $abi() -> u32 {
            LG_ABI_VERSION
        }
        #[no_mangle]
        pub extern "C" fn $create(_desc: *const LgEngineDesc, _out: *mut *mut LgEngine) -> c_int {
            LG_ERR_NOT_SUPPORTED
        }
        #[no_mangle]
        pub extern "C" fn $start(_e: *mut LgEngine, _cb: Option<LgEventCb>) -> c_int {
            LG_ERR_NOT_SUPPORTED
        }
        #[no_mangle]
        pub extern "C" fn $cmd(_e: *mut LgEngine, _json: *const c_char) -> c_int {
            LG_ERR_NOT_SUPPORTED
        }
        #[no_mangle]
        pub extern "C" fn $surface(_e: *mut LgEngine, _s: *mut c_void) -> c_int {
            LG_ERR_NOT_SUPPORTED
        }
        #[no_mangle]
        pub extern "C" fn $destroy(_e: *mut LgEngine) -> c_int {
            LG_OK
        }
    };
}

// rfvp（FVP 引擎）
core_stub!(
    lg_rfvp_engine_create,
    lg_rfvp_engine_start,
    lg_rfvp_engine_command_json,
    lg_rfvp_engine_set_surface,
    lg_rfvp_engine_destroy,
    lg_rfvp_abi_version
);
// siglus（KEY 系）
core_stub!(
    lg_siglus_engine_create,
    lg_siglus_engine_start,
    lg_siglus_engine_command_json,
    lg_siglus_engine_set_surface,
    lg_siglus_engine_destroy,
    lg_siglus_abi_version
);
// sena（SoftPAL）
core_stub!(
    lg_sena_engine_create,
    lg_sena_engine_start,
    lg_sena_engine_command_json,
    lg_sena_engine_set_surface,
    lg_sena_engine_destroy,
    lg_sena_abi_version
);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_matches_header() {
        assert_eq!(LG_ABI_VERSION, 0x0001_0000);
        assert_eq!(lg_abi_version(), LG_ABI_VERSION);
    }

    #[test]
    fn stubs_report_not_supported() {
        assert_eq!(lg_rfvp_engine_create(std::ptr::null(), std::ptr::null_mut()), LG_ERR_NOT_SUPPORTED);
        assert_eq!(lg_sena_engine_destroy(std::ptr::null_mut()), LG_OK);
    }

    #[test]
    fn probe_json_is_nul_terminated() {
        let c = lg_cbridge_probe();
        unsafe {
            let mut len = 0usize;
            while *c.add(len) != 0 {
                len += 1;
            }
            assert!(len > 0);
        }
    }
}
