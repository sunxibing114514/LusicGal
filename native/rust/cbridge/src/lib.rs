//! LusicGal Rust FFI 门面（v2）。
//!
//! v2 起核心以独立 `liblusicgal_<id>.so` 分发（Android dlsym 派发），
//! 本 crate 不再捆绑核心符号 —— 它是 ABI 契约的 Rust 侧门禁：
//!  - 复用 `lg_common`（ABI 常量 / 输入解析 / 事件 JSON）保证与
//!    native/rust/shells/* 一致的类型与行为；
//!  - CI 在此跑 cargo check + test，先于重依赖核心捕获契约漂移。
//!
//! 真实核心：native/rust/shells/{sena,rfvp,siglus,artemis}（见 docs/BUILD.md）。

use std::os::raw::{c_char, c_int, c_void};

use lg_common::{LgEventCb, LG_ABI_VERSION};

pub const LG_OK: c_int = 0;
pub const LG_ERR_NOT_SUPPORTED: c_int = -3;

/// 与 engine_abi.h `lg_engine_desc_t` 二进制兼容（契约测试用）。
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

/// 桥自身探活（dlsym 目标，验证 Rust 门面已链接）。
#[no_mangle]
pub extern "C" fn lg_cbridge_probe() -> *const c_char {
    b"{\"core\":\"lusicgal-cbridge\",\"abi\":2,\"engines\":\
      [\"sena\",\"rfvp\",\"siglus\",\"artemis\"]}\0"
        .as_ptr() as *const c_char
}

macro_rules! core_stub {
    ($create:ident, $start:ident, $cmd:ident, $surface:ident,
     $input:ident, $size:ident, $destroy:ident, $abi:ident) => {
        #[no_mangle]
        pub extern "C" fn $abi() -> u32 {
            LG_ABI_VERSION
        }
        #[no_mangle]
        pub extern "C" fn $create(_d: *const LgEngineDesc, _o: *mut *mut LgEngine) -> c_int {
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
        pub extern "C" fn $input(_e: *mut LgEngine, _json: *const c_char) -> c_int {
            LG_ERR_NOT_SUPPORTED
        }
        #[no_mangle]
        pub extern "C" fn $size(_e: *mut LgEngine, _w: c_int, _h: c_int) -> c_int {
            LG_ERR_NOT_SUPPORTED
        }
        #[no_mangle]
        pub extern "C" fn $destroy(_e: *mut LgEngine) -> c_int {
            LG_OK
        }
    };
}

// 契约桩（不参与分发 —— 真核心为独立 .so；此处验证 8 符号集合的形状）。
core_stub!(
    lg_rfvp_engine_create, lg_rfvp_engine_start, lg_rfvp_engine_command_json,
    lg_rfvp_engine_set_surface, lg_rfvp_engine_push_input,
    lg_rfvp_engine_surface_size, lg_rfvp_engine_destroy, lg_rfvp_abi_version
);
core_stub!(
    lg_siglus_engine_create, lg_siglus_engine_start, lg_siglus_engine_command_json,
    lg_siglus_engine_set_surface, lg_siglus_engine_push_input,
    lg_siglus_engine_surface_size, lg_siglus_engine_destroy, lg_siglus_abi_version
);
core_stub!(
    lg_sena_engine_create, lg_sena_engine_start, lg_sena_engine_command_json,
    lg_sena_engine_set_surface, lg_sena_engine_push_input,
    lg_sena_engine_surface_size, lg_sena_engine_destroy, lg_sena_abi_version
);
core_stub!(
    lg_artemis_engine_create, lg_artemis_engine_start, lg_artemis_engine_command_json,
    lg_artemis_engine_set_surface, lg_artemis_engine_push_input,
    lg_artemis_engine_surface_size, lg_artemis_engine_destroy, lg_artemis_abi_version
);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_matches_header() {
        assert_eq!(LG_ABI_VERSION, 0x0002_0000);
        assert_eq!(lg_rfvp_abi_version(), LG_ABI_VERSION);
    }

    #[test]
    fn stubs_report_not_supported() {
        assert_eq!(
            lg_sena_engine_create(std::ptr::null(), std::ptr::null_mut()),
            LG_ERR_NOT_SUPPORTED
        );
        assert_eq!(
            lg_artemis_engine_push_input(std::ptr::null_mut(), std::ptr::null()),
            LG_ERR_NOT_SUPPORTED
        );
        assert_eq!(lg_siglus_engine_destroy(std::ptr::null_mut()), LG_OK);
    }

    #[test]
    fn input_json_parses_from_common() {
        // v2 输入契约经 lg_common —— 点/键事件形状稳定。
        let point = lg_common::input::parse(
            r#"{"type":"point","phase":"down","x":0.5,"y":0.25,"pointer":1}"#,
        )
        .expect("point 事件必须可解析");
        assert!(matches!(
            point,
            lg_common::input::LgInput::Point { phase, x, y, pointer }
                if phase == 0 && (x - 0.5).abs() < 1e-9 && (y - 0.25).abs() < 1e-9 && pointer == 1
        ));
        let key = lg_common::input::parse(
            r#"{"type":"key","code":"ok","state":"down","repeat":false}"#,
        )
        .expect("key 事件必须可解析");
        assert!(matches!(
            key,
            lg_common::input::LgInput::Key { name, down } if name == "ok" && down
        ));
        // VK 基准映射存在且稳定（ok=13 / cancel=27）。
        assert_eq!(lg_common::input::vk_code("ok"), 13);
        assert_eq!(lg_common::input::vk_code("cancel"), 27);
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
