//! LusicGal Sena（SoftPAL）核心壳：lg_sena_engine_* → sena-rs pal-vm C API。
//!
//! 路径：CPU 帧缓冲（sena_host_*）。每帧 step → frame_rgba → blit 进宿主
//! 注入的 ANativeWindow（Android）或留待宿主回读（iOS/桌面）。
//!
//! 上游签名参照 platform/android/app/src/main/cpp/include/sena.h（pin f99db78）：
//!   sena_host_create(game_root, nls, w, h) -> handle
//!   sena_host_step(h, dt_ms) -> 0 运行 / 1 终局 / 2 错误
//!   sena_host_frame_rgba/_width/_height/_generation
//!   sena_host_touch(h, phase, x, y)   0=按下 2/3=松开（move 由坐标携带）
//!   sena_host_key(h, key_utf8, pressed)
//!   sena_host_resize / sena_host_destroy
//!   sena_android_set_surface(h, window, w, h)（Android）

use lg_common::{android, blit, event, input, result, LgEventCb, LG_ABI_VERSION};
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Condvar, Mutex};
use std::time::{Duration, Instant};

unsafe extern "C" {
    fn sena_host_create(
        game_root_utf8: *const c_char,
        nls_utf8: *const c_char,
        width: u32,
        height: u32,
    ) -> *mut c_void;
    fn sena_host_step(handle: *mut c_void, dt_ms: u32) -> i32;
    fn sena_host_resize(handle: *mut c_void, width: u32, height: u32);
    fn sena_host_touch(handle: *mut c_void, phase: i32, x: f64, y: f64);
    fn sena_host_key(handle: *mut c_void, key_utf8: *const c_char, pressed: i32);
    fn sena_host_frame_rgba(handle: *mut c_void) -> *const u8;
    fn sena_host_frame_width(handle: *mut c_void) -> u32;
    fn sena_host_frame_height(handle: *mut c_void) -> u32;
    fn sena_host_frame_generation(handle: *mut c_void) -> u64;
    fn sena_host_destroy(handle: *mut c_void);

    #[cfg(target_os = "android")]
    fn sena_android_init_context(java_vm_ptr: *mut c_void, context_ptr: *mut c_void);
    #[cfg(target_os = "android")]
    fn sena_android_set_surface(
        handle: *mut c_void,
        native_window_ptr: *mut c_void,
        surface_width_px: u32,
        surface_height_px: u32,
    );
}

struct SenaEngine {
    game_root: CString,
    game_id: CString,
    save_path: CString,
    nls: Option<CString>,
    width: u32,
    height: u32,
    host: *mut c_void,
    cb: Mutex<Option<LgEventCb>>,
    running: AtomicBool,
    paused: AtomicBool,
    handle: Mutex<*mut c_void>,
    surface: Mutex<Option<(*mut c_void, u32, u32)>>,
    surface_cv: Condvar,
    thread: Mutex<Option<std::thread::JoinHandle<()>>>,
}

unsafe impl Send for SenaEngine {}
unsafe impl Sync for SenaEngine {}

impl SenaEngine {
    fn emit(&self, json: &str) {
        if let Ok(guard) = self.cb.lock() {
            if let Some(cb) = *guard {
                if let Ok(c) = CString::new(json) {
                    unsafe { cb(self.host, c.as_ptr()) };
                }
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn lg_sena_abi_version() -> u32 {
    LG_ABI_VERSION
}

/// 可选符号（约定见 lg_common::android）：桥在 launch 前调用。
#[no_mangle]
pub unsafe extern "C" fn lg_sena_set_android_context(java_vm: *mut c_void, context: *mut c_void) {
    android::set_android_context(java_vm, context);
    #[cfg(target_os = "android")]
    {
        if android::ready() {
            sena_android_init_context(java_vm, context);
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn lg_sena_engine_create(
    desc: *const lg_engine_desc,
    out: *mut *mut c_void,
) -> i32 {
    if desc.is_null() || out.is_null() {
        return result::INVALID_ARGUMENT;
    }
    let d = &*desc;
    let game_root = CStr::from_ptr(d.game_path).to_owned();
    if game_root.as_bytes().is_empty() {
        return result::INVALID_ARGUMENT;
    }
    let save_path = if d.save_path.is_null() {
        game_root.clone()
    } else {
        CStr::from_ptr(d.save_path).to_owned()
    };
    // 存档目录注入（scripts/patch_sena_rust.sh 打的 LUSICGAL_SAVE_DIR 补丁）。
    if let Ok(p) = save_path.to_str() {
        std::env::set_var("LUSICGAL_SAVE_DIR", p);
    }
    let options = if d.options_json.is_null() {
        serde_json::json!({})
    } else {
        serde_json::from_str(CStr::from_ptr(d.options_json).to_string_lossy().as_ref())
            .unwrap_or_else(|_| serde_json::json!({}))
    };
    let nls = options
        .get("nls")
        .and_then(|v| v.as_str())
        .and_then(|s| CString::new(s).ok());
    let width = options
        .get("width")
        .and_then(|v| v.as_u64())
        .unwrap_or(1280) as u32;
    let height = options
        .get("height")
        .and_then(|v| v.as_u64())
        .unwrap_or(720) as u32;
    let game_id = if d.game_id.is_null() {
        CString::new("").unwrap()
    } else {
        CStr::from_ptr(d.game_id).to_owned()
    };
    *out = Box::into_raw(Box::new(SenaEngine {
        game_root,
        game_id,
        save_path,
        nls,
        width,
        height,
        host: d.host,
        cb: Mutex::new(None),
        running: AtomicBool::new(false),
        paused: AtomicBool::new(false),
        handle: Mutex::new(std::ptr::null_mut()),
        surface: Mutex::new(None),
        surface_cv: Condvar::new(),
        thread: Mutex::new(None),
    })) as *mut c_void;
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_sena_engine_start(engine: *mut c_void, cb: LgEventCb) -> i32 {
    let e = match engine.as_mut() {
        Some(e) => e as *mut SenaEngine as &mut SenaEngine,
        None => return result::INVALID_ARGUMENT,
    };
    if *e.handle.lock().unwrap() != std::ptr::null_mut() || e.running.load(Ordering::Acquire) {
        return result::INVALID_STATE;
    }
    *e.cb.lock().unwrap() = Some(cb);
    e.running.store(true, Ordering::Release);

    let handle = unsafe {
        sena_host_create(
            e.game_root.as_ptr(),
            e.nls.as_ref()
                .map(|n| n.as_ptr())
                .unwrap_or(std::ptr::null()),
            e.width,
            e.height,
        )
    };
    if handle.is_null() {
        e.running.store(false, Ordering::Release);
        event::error(Some(cb), e.host, "sena_host_create 失败");
        return result::CORE;
    }
    *e.handle.lock().unwrap() = handle;
    // 表面若已到（launch 前注入的少数场景），立即挂接。
    if let Some((win, w, h)) = *e.surface.lock().unwrap() {
        #[cfg(target_os = "android")]
        sena_android_set_surface(handle, win, w, h);
        let _ = (win, w, h);
    }

    let joined = std::thread::Builder::new()
        .name("lg_sena_loop".into())
        .spawn(move || run_loop(engine as usize, cb))
        .map(|t| t)
        .map_err(|_| result::IO);
    match joined {
        Ok(t) => {
            *e.thread.lock().unwrap() = Some(t);
            event::state(Some(cb), e.host, "running");
            result::OK
        }
        Err(rc) => rc,
    }
}

fn run_loop(engine_addr: usize, cb: LgEventCb) {
    let e = unsafe { &*(engine_addr as *const SenaEngine) };
    let handle = *e.handle.lock().unwrap();
    let host = e.host;
    let mut frame_gen = 0u64;
    let mut last = Instant::now();
    let frame_budget = Duration::from_millis(16);
    while e.running.load(Ordering::Acquire) {
        if e.paused.load(Ordering::Acquire) {
            std::thread::sleep(Duration::from_millis(40));
            continue;
        }
        let dt = last.elapsed().as_millis().min(u32::MAX as u128) as u32;
        last = Instant::now();
        let rc = unsafe { sena_host_step(handle, dt) };
        if rc == 1 {
            event::exit(Some(cb), host, 0);
            break;
        }
        if rc == 2 {
            event::error(Some(cb), host, "sena_host_step 报告错误");
            event::exit(Some(cb), host, 1);
            break;
        }
        // CPU 帧路径：把最新帧 blit 进宿主表面（无表面则跳过）。
        #[cfg(target_os = "android")]
        {
            if let Some((win, _, _)) = *e.surface.lock().unwrap() {
                let gen = unsafe { sena_host_frame_generation(handle) };
                if gen != frame_gen {
                    frame_gen = gen;
                    let w = unsafe { sena_host_frame_width(handle) };
                    let h = unsafe { sena_host_frame_height(handle) };
                    let ptr = unsafe { sena_host_frame_rgba(handle) };
                    if !ptr.is_null() && w > 0 && h > 0 {
                        let len = (w as usize) * (h as usize) * 4;
                        let rgba = unsafe { std::slice::from_raw_parts(ptr, len) };
                        blit::blit_rgba(win, rgba, w, h);
                    }
                }
            }
        }
        let spent = last.elapsed();
        if spent < frame_budget {
            std::thread::sleep(frame_budget - spent);
        }
    }
    e.running.store(false, Ordering::Release);
}

#[no_mangle]
pub unsafe extern "C" fn lg_sena_engine_set_surface(engine: *mut c_void, surface: *mut c_void) -> i32 {
    let Some(e) = (engine as *mut SenaEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if surface.is_null() {
        return result::INVALID_ARGUMENT;
    }
    let mut guard = e.surface.lock().unwrap();
    *guard = Some((surface, e.width, e.height));
    let handle = *e.handle.lock().unwrap();
    if !handle.is_null() {
        #[cfg(target_os = "android")]
        sena_android_set_surface(handle, surface, e.width, e.height);
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_sena_engine_push_input(engine: *mut c_void, json: *const c_char) -> i32 {
    let Some(e) = (engine as *mut SenaEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if json.is_null() {
        return result::INVALID_ARGUMENT;
    }
    let handle = *e.handle.lock().unwrap();
    if handle.is_null() {
        return result::INVALID_STATE;
    }
    let Ok(text) = CStr::from_ptr(json).to_str() else {
        return result::INVALID_ARGUMENT;
    };
    match input::parse(text) {
        Some(input::LgInput::Point { phase, x, y, .. }) => {
            // sena：0=按下 2/3=松开；坐标换算像素（表面=帧缓冲同尺寸起步）。
            let px = x * (e.width as f64);
            let py = y * (e.height as f64);
            let sena_phase = match phase {
                0 => 0,
                2 | 3 => 2,
                _ => 1,
            };
            unsafe { sena_host_touch(handle, sena_phase, px, py) };
        }
        Some(input::LgInput::Key { name, down }) => {
            // sena_key 吃 UTF-8 字符：ok→'\r'，cancel→ESC(\\x1b)……用基础 ASCII。
            let c = match name.as_str() {
                "ok" | "enter" => "\r",
                "cancel" | "back" => "\x1b",
                "text" | "space" => " ",
                "up" => "\x11",
                "down" => "\x12",
                "left" => "\x13",
                "right" => "\x14",
                other => other,
            };
            if let Ok(cc) = CString::new(c) {
                unsafe { sena_host_key(handle, cc.as_ptr(), if down { 1 } else { 0 }) };
            }
        }
        Some(input::LgInput::Text(t)) => {
            // 逐字符喂（sena 无文本批接口）。
            for ch in t.chars().take(32) {
                if let Ok(cc) = CString::new(ch.to_string()) {
                    unsafe { sena_host_key(handle, cc.as_ptr(), 1) };
                }
            }
        }
        None => {}
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_sena_engine_command_json(engine: *mut c_void, json: *const c_char) -> i32 {
    let Some(e) = (engine as *mut SenaEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if json.is_null() {
        return result::INVALID_ARGUMENT;
    }
    let Ok(text) = CStr::from_ptr(json).to_str() else {
        return result::INVALID_ARGUMENT;
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(text) else {
        return result::INVALID_ARGUMENT;
    };
    match v.get("command").and_then(|c| c.as_str()).unwrap_or("") {
        "stop" | "quit" => {
            e.running.store(false, Ordering::Release);
        }
        "pause" => e.paused.store(true, Ordering::Release),
        "resume" => e.paused.store(false, Ordering::Release),
        // 音量/存读档：sena 游戏内 UI 自管；宿主命令暂不透传（文档已注明）。
        _ => {}
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_sena_engine_surface_size(
    engine: *mut c_void,
    w: i32,
    h: i32,
) -> i32 {
    let Some(e) = (engine as *mut SenaEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if w <= 0 || h <= 0 {
        return result::INVALID_ARGUMENT;
    }
    e.width = w as u32;
    e.height = h as u32;
    let handle = *e.handle.lock().unwrap();
    if !handle.is_null() {
        unsafe { sena_host_resize(handle, w as u32, h as u32) };
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_sena_engine_destroy(engine: *mut c_void) -> i32 {
    let Some(e) = (engine as *mut SenaEngine).as_mut() else {
        return result::OK; // 幂等
    };
    e.running.store(false, Ordering::Release);
    if let Some(t) = e.thread.lock().unwrap().take() {
        let _ = t.join();
    }
    let handle = *e.handle.lock().unwrap();
    if !handle.is_null() {
        unsafe { sena_host_destroy(handle) };
        *e.handle.lock().unwrap() = std::ptr::null_mut();
    }
    // Box 释放（线程已 join，无并发访问）。
    unsafe { drop(Box::from_raw(e)) };
    result::OK
}

/// desc 的 C 镜像（仅本壳需要字段子集；大小与 lg_engine_desc_t 不必一致，
/// 因为本壳直接把 desc 当 opaque 用——字段访问全部经真实头字段偏移，见上）。
#[repr(C)]
pub struct lg_engine_desc {
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
