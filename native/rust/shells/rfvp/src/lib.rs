//! LusicGal Rfvp（FVP）核心壳：lg_rfvp_engine_* → rfvp crate C API。
//!
//! 渲染：wgpu 直渲宿主注入的 ANativeWindow（rfvp_android_create 需要
//! 非空窗口 —— 壳在 owner 线程上等表面到位后再 create）。
//!
//! 上游签名（crates/rfvp/src/android_host.rs，pin 709b6ba）：
//!   rfvp_android_init_context(java_vm, context)          （ndk-context，音频需要）
//!   rfvp_android_create(win, w, h, scale, game_dir, nls) -> handle（null=失败）
//!   rfvp_android_step(h, dt_ms) -> 0 运行 / 1 终局
//!   rfvp_android_set_surface(h, win, w, h)
//!   rfvp_android_touch(h, phase, x_px, y_px)  0=began 1=moved 2=ended 3=cancel
//!   rfvp_android_key(h, vk_code, phase)       phase 0=down 1=up（VK 码）
//!   rfvp_android_resize(h, w, h) / rfvp_android_destroy(h)

use lg_common::{android, event, input, result, LgEventCb, LG_ABI_VERSION};
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};
use std::time::{Duration, Instant};

unsafe extern "C" {
    fn rfvp_android_init_context(java_vm_ptr: *mut c_void, context_ptr: *mut c_void);
    fn rfvp_android_create(
        native_window_ptr: *mut c_void,
        surface_width_px: u32,
        surface_height_px: u32,
        native_scale_factor: f64,
        game_dir_utf8: *const c_char,
        nls_utf8: *const c_char,
    ) -> *mut c_void;
    fn rfvp_android_step(handle: *mut c_void, dt_ms: u32) -> i32;
    fn rfvp_android_resize(handle: *mut c_void, surface_width_px: u32, surface_height_px: u32);
    fn rfvp_android_set_surface(
        handle: *mut c_void,
        native_window_ptr: *mut c_void,
        surface_width_px: u32,
        surface_height_px: u32,
    );
    fn rfvp_android_touch(handle: *mut c_void, phase: i32, x_px: f64, y_px: f64);
    fn rfvp_android_key(handle: *mut c_void, vk_code: i32, phase: i32);
    fn rfvp_android_destroy(handle: *mut c_void);
}

struct RfvpEngine {
    game_dir: CString,
    save_path: CString,
    nls: Option<CString>,
    width: AtomicU32,
    height: AtomicU32,
    scale: f64,
    host: *mut c_void,
    cb: Mutex<Option<LgEventCb>>,
    running: AtomicBool,
    paused: AtomicBool,
    handle: Mutex<*mut c_void>,
    surface: Mutex<Option<(*mut c_void, u32, u32)>>,
    surface_gen: AtomicU64,
    surface_cv: Condvar,
    thread: Mutex<Option<std::thread::JoinHandle<()>>>,
}

unsafe impl Send for RfvpEngine {}
unsafe impl Sync for RfvpEngine {}

#[repr(C)]
struct LgDesc {
    struct_size: u32,
    abi_version: u32,
    engine_id: *const c_char,
    game_id: *const c_char,
    game_path: *const c_char,
    save_path: *const c_char,
    cache_path: *const c_char,
    options_json: *const c_char,
    host: *mut c_void,
    reserved_ptr: [*mut c_void; 8],
    reserved_u64: [u64; 8],
}

#[no_mangle]
pub extern "C" fn lg_rfvp_abi_version() -> u32 {
    LG_ABI_VERSION
}

/// 可选符号：桥在 launch 前调用（音频 kira→cpal→Oboe 需要）。
#[no_mangle]
pub unsafe extern "C" fn lg_rfvp_set_android_context(java_vm: *mut c_void, context: *mut c_void) {
    android::set_android_context(java_vm, context);
    if android::ready() {
        rfvp_android_init_context(java_vm, context);
    }
}

#[no_mangle]
pub unsafe extern "C" fn lg_rfvp_engine_create(desc: *const LgDesc, out: *mut *mut c_void) -> i32 {
    if desc.is_null() || out.is_null() {
        return result::INVALID_ARGUMENT;
    }
    let d = &*desc;
    let game_dir = CStr::from_ptr(d.game_path).to_owned();
    if game_dir.as_bytes().is_empty() {
        return result::INVALID_ARGUMENT;
    }
    let save_path = if d.save_path.is_null() {
        game_dir.clone()
    } else {
        CStr::from_ptr(d.save_path).to_owned()
    };
    if let Ok(p) = save_path.to_str() {
        // scripts/patch_rfvp.sh：desktop_storage 尊重 LUSICGAL_SAVE_DIR。
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
    let width = options.get("width").and_then(|v| v.as_u64()).unwrap_or(1280) as u32;
    let height = options.get("height").and_then(|v| v.as_u64()).unwrap_or(720) as u32;
    let scale = options.get("scale").and_then(|v| v.as_f64()).unwrap_or(1.0);
    *out = Box::into_raw(Box::new(RfvpEngine {
        game_dir,
        save_path,
        nls,
        width: AtomicU32::new(width),
        height: AtomicU32::new(height),
        scale,
        host: d.host,
        cb: Mutex::new(None),
        running: AtomicBool::new(false),
        paused: AtomicBool::new(false),
        handle: Mutex::new(std::ptr::null_mut()),
        surface: Mutex::new(None),
        surface_gen: AtomicU64::new(0),
        surface_cv: Condvar::new(),
        thread: Mutex::new(None),
    })) as *mut c_void;
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_rfvp_engine_start(engine: *mut c_void, cb: LgEventCb) -> i32 {
    let Some(e) = (engine as *mut RfvpEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if e.running.load(Ordering::Acquire) {
        return result::INVALID_STATE;
    }
    *e.cb.lock().unwrap() = Some(cb);
    e.running.store(true, Ordering::Release);
    let t = match std::thread::Builder::new()
        .name("lg_rfvp_loop".into())
        .spawn(move || run_loop(engine as usize, cb))
    {
        Ok(t) => t,
        Err(_) => return result::IO,
    };
    *e.thread.lock().unwrap() = Some(t);
    event::state(Some(cb), e.host, "loading");
    result::OK
}

fn run_loop(engine_addr: usize, cb: LgEventCb) {
    let e = unsafe { &*(engine_addr as *const RfvpEngine) };
    let host = e.host;
    // rfvp_android_create 需要非空 ANativeWindow：等宿主表面（PlatformView
    // surfaceCreated → set_surface）。超时 10s 放弃。
    let (win, w, h) = {
        let guard = e.surface.lock().unwrap();
        let (g, _t) = e
            .surface_cv
            .wait_timeout_while(guard, Duration::from_secs(10), |s| s.is_none())
            .unwrap();
        match *g {
            Some(v) => v,
            None => {
                event::error(Some(cb), host, "等待渲染表面超时（rfvp 需注入 ANativeWindow）");
                event::exit(Some(cb), host, 1);
                e.running.store(false, Ordering::Release);
                return;
            }
        }
    };
    let handle = unsafe {
        rfvp_android_create(
            win,
            w,
            h,
            e.scale,
            e.game_dir.as_ptr(),
            e.nls.as_ref()
                .map(|n| n.as_ptr())
                .unwrap_or(std::ptr::null()),
        )
    };
    if handle.is_null() {
        event::error(Some(cb), host, "rfvp_android_create 失败");
        event::exit(Some(cb), host, 1);
        e.running.store(false, Ordering::Release);
        return;
    }
    *e.handle.lock().unwrap() = handle;
    event::state(Some(cb), host, "running");

    let frame_budget = Duration::from_millis(16);
    let mut last = Instant::now();
    let mut applied_gen = e.surface_gen.load(Ordering::Acquire);
    while e.running.load(Ordering::Acquire) {
        if e.paused.load(Ordering::Acquire) {
            std::thread::sleep(Duration::from_millis(40));
            continue;
        }
        // 换表面（后台恢复/重进前台）仅发生在新代际。
        let gen_now = e.surface_gen.load(Ordering::Acquire);
        if gen_now != applied_gen {
            if let Some((win2, w2, h2)) = *e.surface.lock().unwrap() {
                unsafe { rfvp_android_set_surface(handle, win2, w2, h2) };
            }
            applied_gen = gen_now;
        }
        if e.paused.load(Ordering::Acquire) {
            continue;
        }
        let dt = last.elapsed().as_millis().min(u32::MAX as u128) as u32;
        last = Instant::now();
        let rc = unsafe { rfvp_android_step(handle, dt) };
        if rc != 0 {
            event::exit(Some(cb), host, rc);
            break;
        }
        let spent = last.elapsed();
        if spent < frame_budget {
            std::thread::sleep(frame_budget - spent);
        }
    }
    e.running.store(false, Ordering::Release);
}

#[no_mangle]
pub unsafe extern "C" fn lg_rfvp_engine_set_surface(engine: *mut c_void, surface: *mut c_void) -> i32 {
    let Some(e) = (engine as *mut RfvpEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if surface.is_null() {
        return result::INVALID_ARGUMENT;
    }
    let w = e.width.load(Ordering::Acquire);
    let h = e.height.load(Ordering::Acquire);
    {
        let mut guard = e.surface.lock().unwrap();
        *guard = Some((surface, w, h));
    }
    e.surface_gen.fetch_add(1, Ordering::AcqRel);
    e.surface_cv.notify_all();
    // run_loop 见新代际后统一 set_surface —— 无需在此直调（handle 可能未建）。
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_rfvp_engine_push_input(engine: *mut c_void, json: *const c_char) -> i32 {
    let Some(e) = (engine as *mut RfvpEngine).as_mut() else {
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
            let px = x * (e.width.load(Ordering::Acquire) as f64);
            let py = y * (e.height.load(Ordering::Acquire) as f64);
            // rfvp 相位与 LG ABI 完全一致：0/1/2/3。
            unsafe { rfvp_android_touch(handle, phase as i32, px, py) };
        }
        Some(input::LgInput::Key { name, down }) => {
            let vk = input::vk_code(&name) as i32;
            if vk != 0 {
                unsafe { rfvp_android_key(handle, vk, if down { 0 } else { 1 }) };
            }
        }
        Some(input::LgInput::Text(_)) => { /* rfvp 暂无文本批注入口 */ }
        None => {}
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_rfvp_engine_command_json(engine: *mut c_void, json: *const c_char) -> i32 {
    let Some(e) = (engine as *mut RfvpEngine).as_mut() else {
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
        "stop" | "quit" => e.running.store(false, Ordering::Release),
        "pause" => e.paused.store(true, Ordering::Release),
        "resume" => e.paused.store(false, Ordering::Release),
        _ => {}
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_rfvp_engine_surface_size(engine: *mut c_void, w: i32, h: i32) -> i32 {
    let Some(e) = (engine as *mut RfvpEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if w <= 0 || h <= 0 {
        return result::INVALID_ARGUMENT;
    }
    e.width.store(w as u32, Ordering::Release);
    e.height.store(h as u32, Ordering::Release);
    let handle = *e.handle.lock().unwrap();
    if !handle.is_null() {
        unsafe { rfvp_android_resize(handle, w as u32, h as u32) };
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_rfvp_engine_destroy(engine: *mut c_void) -> i32 {
    let Some(e) = (engine as *mut RfvpEngine).as_mut() else {
        return result::OK;
    };
    e.running.store(false, Ordering::Release);
    e.surface_cv.notify_all(); // 唤醒可能在等表面的 owner 线程
    if let Some(t) = e.thread.lock().unwrap().take() {
        let _ = t.join();
    }
    let handle = *e.handle.lock().unwrap();
    if !handle.is_null() {
        unsafe { rfvp_android_destroy(handle) };
        *e.handle.lock().unwrap() = std::ptr::null_mut();
    }
    unsafe { drop(Box::from_raw(e)) };
    result::OK
}
