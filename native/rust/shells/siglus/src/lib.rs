//! LusicGal Siglus（KEY 系：SiglusEngine/RealLive/AVG32/UK2）核心壳。
//!
//! 双路径（按 game_probe_json 的 engine 字段自动选择）：
//!  - "siglus"（SiglusEngine）→ siglus_android_*：wgpu 直渲宿主注入表面
//!    （create 需非空 ANativeWindow，owner 线程等表面）。
//!  - "reallive"/"avg32"/"uk2" → game_fb_*：CPU 帧缓冲 + 宿主 blit。
//!
//! 上游签名（crates/game_launcher/src/ffi.rs、crates/siglus_scene_vm/src/android_host.rs，
//! pin 5f358ef）：
//!   game_probe_json(root, nls, cover_dir) -> cstr（game_string_free 释放）
//!   game_fb_open(root, engine, nls, err_out) -> FbHandle*（engine=NULL 自动探测）
//!   game_fb_step(h, dt_ms) -> 0 运行 / 1 终局
//!   game_fb_frame(h, &w, &h) -> *const u8（RGBA8，下个调用前有效）
//!   game_fb_pointer_move(h, x, y) / _pointer_button(h, 0, 1|0) / _key(h, code, 1|0)
//!   game_fb_text(h, utf8) / game_fb_close(h)
//!   siglus_android_init_context(vm, ctx) / _create(win, w, h, scale, game_dir) -> h
//!   siglus_android_step(h, dt_ms) / _set_surface(h, win, w, h) / _resize(h, w, h)
//!   siglus_android_touch(h, phase, x_px, y_px) / _key_down(h, code) / _key_up(h, code)
//!   siglus_android_destroy(h)
//!
//! 存档：reallive 原生支持 REALLIVE_SAVE_DIR 环境变量；siglus 经
//! scripts/patch_siglus_rs.sh（LUSICGAL_SAVE_DIR）注入。

use lg_common::{android, blit, event, input, result, LgEventCb, LG_ABI_VERSION};
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};
use std::time::{Duration, Instant};

unsafe extern "C" {
    fn game_probe_json(
        root: *const c_char,
        nls: *const c_char,
        cover_cache_dir: *const c_char,
    ) -> *mut c_char;
    fn game_string_free(ptr: *mut c_char);

    fn game_fb_open(
        root: *const c_char,
        engine: *const c_char,
        nls: *const c_char,
        error_out: *mut *mut c_char,
    ) -> *mut c_void;
    fn game_fb_step(game: *mut c_void, dt_ms: u32) -> i32;
    fn game_fb_frame(
        game: *mut c_void,
        width: *mut u32,
        height: *mut u32,
    ) -> *const u8;
    fn game_fb_pointer_move(game: *mut c_void, x: i32, y: i32);
    fn game_fb_pointer_button(game: *mut c_void, button: i32, pressed: i32);
    fn game_fb_key(game: *mut c_void, code: u32, pressed: i32);
    fn game_fb_text(game: *mut c_void, text: *const c_char);
    fn game_fb_close(game: *mut c_void);

    fn siglus_android_init_context(java_vm_ptr: *mut c_void, context_ptr: *mut c_void);
    fn siglus_android_create(
        native_window_ptr: *mut c_void,
        surface_width_px: u32,
        surface_height_px: u32,
        native_scale_factor: f64,
        game_dir_utf8: *const c_char,
    ) -> *mut c_void;
    fn siglus_android_step(handle: *mut c_void, dt_ms: u32) -> i32;
    fn siglus_android_resize(handle: *mut c_void, surface_width_px: u32, surface_height_px: u32);
    fn siglus_android_set_surface(
        handle: *mut c_void,
        native_window_ptr: *mut c_void,
        surface_width_px: u32,
        surface_height_px: u32,
    );
    fn siglus_android_touch(handle: *mut c_void, phase: i32, x_px: f64, y_px: f64);
    fn siglus_android_key_down(handle: *mut c_void, key_code: i32);
    fn siglus_android_key_up(handle: *mut c_void, key_code: i32);
    fn siglus_android_destroy(handle: *mut c_void);
}

/// 运行路径。
#[derive(Clone, Copy, PartialEq)]
enum Path {
    Fb,      // avg32 / reallive / uk2（CPU 帧缓冲）
    Android, // siglus（wgpu 直渲表面）
}

struct SiglusEngine {
    game_root: CString,
    save_path: CString,
    nls: Option<CString>,
    width: AtomicU32,
    height: AtomicU32,
    scale: f64,
    host: *mut c_void,
    cb: Mutex<Option<LgEventCb>>,
    running: AtomicBool,
    paused: AtomicBool,
    path: Mutex<Option<Path>>,
    handle: Mutex<*mut c_void>,     // FbHandle* 或 SiglusHost*
    surface: Mutex<Option<(*mut c_void, u32, u32)>>,
    surface_gen: AtomicU64,
    surface_cv: Condvar,
    thread: Mutex<Option<std::thread::JoinHandle<()>>>,
}

unsafe impl Send for SiglusEngine {}
unsafe impl Sync for SiglusEngine {}

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
pub extern "C" fn lg_siglus_abi_version() -> u32 {
    LG_ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn lg_siglus_set_android_context(java_vm: *mut c_void, context: *mut c_void) {
    android::set_android_context(java_vm, context);
    if android::ready() {
        siglus_android_init_context(java_vm, context);
    }
}

#[no_mangle]
pub unsafe extern "C" fn lg_siglus_engine_create(desc: *const LgDesc, out: *mut *mut c_void) -> i32 {
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
    if let Ok(p) = save_path.to_str() {
        // reallive 原生 REALLIVE_SAVE_DIR；siglus/其余经 patch 用 LUSICGAL_SAVE_DIR。
        std::env::set_var("REALLIVE_SAVE_DIR", p);
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
    *out = Box::into_raw(Box::new(SiglusEngine {
        game_root,
        save_path,
        nls,
        width: AtomicU32::new(width),
        height: AtomicU32::new(height),
        scale,
        host: d.host,
        cb: Mutex::new(None),
        running: AtomicBool::new(false),
        paused: AtomicBool::new(false),
        path: Mutex::new(None),
        handle: Mutex::new(std::ptr::null_mut()),
        surface: Mutex::new(None),
        surface_gen: AtomicU64::new(0),
        surface_cv: Condvar::new(),
        thread: Mutex::new(None),
    })) as *mut c_void;
    result::OK
}

/// 用 game_probe_json 探测引擎子类（"siglus" → Android 路径）。
fn detect_path(e: &SiglusEngine) -> Path {
    let probe = unsafe {
        game_probe_json(
            e.game_root.as_ptr(),
            e.nls.as_ref()
                .map(|n| n.as_ptr())
                .unwrap_or(std::ptr::null()),
            std::ptr::null(),
        )
    };
    if probe.is_null() {
        return Path::Fb; // 探测失败：fb 路径 open 时报错
    }
    let json = unsafe { CStr::from_ptr(probe) }.to_string_lossy().into_owned();
    unsafe { game_string_free(probe) };
    let kind = serde_json::from_str::<serde_json::Value>(&json)
        .ok()
        .and_then(|v| {
            v.get("engine")
                .and_then(|e| e.as_str())
                .map(|s| s.to_owned())
        })
        .unwrap_or_default();
    if kind == "siglus" {
        Path::Android
    } else {
        Path::Fb
    }
}

#[no_mangle]
pub unsafe extern "C" fn lg_siglus_engine_start(engine: *mut c_void, cb: LgEventCb) -> i32 {
    let Some(e) = (engine as *mut SiglusEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if e.running.load(Ordering::Acquire) {
        return result::INVALID_STATE;
    }
    *e.cb.lock().unwrap() = Some(cb);
    let path = detect_path(e);
    *e.path.lock().unwrap() = Some(path);
    e.running.store(true, Ordering::Release);
    let t = match std::thread::Builder::new()
        .name("lg_siglus_loop".into())
        .spawn(move || run_loop(engine as usize, cb, path))
    {
        Ok(t) => t,
        Err(_) => return result::IO,
    };
    *e.thread.lock().unwrap() = Some(t);
    event::state(Some(cb), e.host, "loading");
    result::OK
}

fn run_loop(engine_addr: usize, cb: LgEventCb, path: Path) {
    let e = unsafe { &*(engine_addr as *const SiglusEngine) };
    let host = e.host;
    let frame_budget = Duration::from_millis(16);
    let mut last = Instant::now();
    match path {
        Path::Android => {
            // siglus：wgpu 直渲 —— 等宿主表面（10s 超时）。
            let (win, w, h) = {
                let guard = e.surface.lock().unwrap();
                let (g, _t) = e
                    .surface_cv
                    .wait_timeout_while(guard, Duration::from_secs(10), |s| s.is_none())
                    .unwrap();
                match *g {
                    Some(v) => v,
                    None => {
                        event::error(Some(cb), host, "等待渲染表面超时（siglus 需注入 ANativeWindow）");
                        event::exit(Some(cb), host, 1);
                        e.running.store(false, Ordering::Release);
                        return;
                    }
                }
            };
            let handle = unsafe {
                siglus_android_create(win, w, h, e.scale, e.game_root.as_ptr())
            };
            if handle.is_null() {
                event::error(Some(cb), host, "siglus_android_create 失败");
                event::exit(Some(cb), host, 1);
                e.running.store(false, Ordering::Release);
                return;
            }
            *e.handle.lock().unwrap() = handle;
            event::state(Some(cb), host, "running");
            let mut applied_gen = e.surface_gen.load(Ordering::Acquire);
            while e.running.load(Ordering::Acquire) {
                if e.paused.load(Ordering::Acquire) {
                    std::thread::sleep(Duration::from_millis(40));
                    continue;
                }
                let gen_now = e.surface_gen.load(Ordering::Acquire);
                if gen_now != applied_gen {
                    if let Some((win2, w2, h2)) = *e.surface.lock().unwrap() {
                        unsafe { siglus_android_set_surface(handle, win2, w2, h2) };
                    }
                    applied_gen = gen_now;
                }
                let dt = last.elapsed().as_millis().min(u32::MAX as u128) as u32;
                last = Instant::now();
                let rc = unsafe { siglus_android_step(handle, dt) };
                if rc != 0 {
                    event::exit(Some(cb), host, rc);
                    break;
                }
                let spent = last.elapsed();
                if spent < frame_budget {
                    std::thread::sleep(frame_budget - spent);
                }
            }
        }
        Path::Fb => {
            // avg32 / reallive / uk2：CPU 帧缓冲。
            let mut err: *mut c_char = std::ptr::null_mut();
            let handle = unsafe {
                game_fb_open(
                    e.game_root.as_ptr(),
                    std::ptr::null(), // 自动探测
                    e.nls.as_ref()
                        .map(|n| n.as_ptr())
                        .unwrap_or(std::ptr::null()),
                    &mut err,
                )
            };
            if handle.is_null() {
                let msg = if err.is_null() {
                    "game_fb_open 失败".to_owned()
                } else {
                    unsafe { CStr::from_ptr(err) }.to_string_lossy().into_owned()
                };
                if !err.is_null() {
                    unsafe { game_string_free(err) };
                }
                event::error(Some(cb), host, &msg);
                event::exit(Some(cb), host, 1);
                e.running.store(false, Ordering::Release);
                return;
            }
            *e.handle.lock().unwrap() = handle;
            event::state(Some(cb), host, "running");
            while e.running.load(Ordering::Acquire) {
                if e.paused.load(Ordering::Acquire) {
                    std::thread::sleep(Duration::from_millis(40));
                    continue;
                }
                let dt = last.elapsed().as_millis().min(u32::MAX as u128) as u32;
                last = Instant::now();
                let rc = unsafe { game_fb_step(handle, dt) };
                if rc != 0 {
                    event::exit(Some(cb), host, 0);
                    break;
                }
                #[cfg(target_os = "android")]
                {
                    if let Some((win, _, _)) = *e.surface.lock().unwrap() {
                        let mut w = 0u32;
                        let mut h = 0u32;
                        let ptr = unsafe { game_fb_frame(handle, &mut w, &mut h) };
                        if !ptr.is_null() && w > 0 && h > 0 {
                            let len = (w as usize) * (h as usize) * 4;
                            let rgba = unsafe { std::slice::from_raw_parts(ptr, len) };
                            blit::blit_rgba(win, rgba, w, h);
                        }
                    }
                }
                let spent = last.elapsed();
                if spent < frame_budget {
                    std::thread::sleep(frame_budget - spent);
                }
            }
            unsafe { game_fb_close(handle) };
            *e.handle.lock().unwrap() = std::ptr::null_mut();
        }
    }
    e.running.store(false, Ordering::Release);
}

#[no_mangle]
pub unsafe extern "C" fn lg_siglus_engine_set_surface(engine: *mut c_void, surface: *mut c_void) -> i32 {
    let Some(e) = (engine as *mut SiglusEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if surface.is_null() {
        return result::INVALID_ARGUMENT;
    }
    {
        let mut guard = e.surface.lock().unwrap();
        *guard = Some((surface, e.width.load(Ordering::Acquire), e.height.load(Ordering::Acquire)));
    }
    e.surface_gen.fetch_add(1, Ordering::AcqRel);
    e.surface_cv.notify_all();
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_siglus_engine_push_input(engine: *mut c_void, json: *const c_char) -> i32 {
    let Some(e) = (engine as *mut SiglusEngine).as_mut() else {
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
    let path = *e.path.lock().unwrap();
    match input::parse(text) {
        Some(input::LgInput::Point { phase, x, y, .. }) => {
            let px = x * (e.width.load(Ordering::Acquire) as f64);
            let py = y * (e.height.load(Ordering::Acquire) as f64);
            match path {
                Some(Path::Android) => unsafe {
                    // siglus_android_touch 相位同 LG ABI（0/1/2/3）。
                    siglus_android_touch(handle, phase as i32, px, py)
                },
                _ => unsafe {
                    game_fb_pointer_move(handle, px as i32, py as i32);
                    match phase {
                        0 => game_fb_pointer_button(handle, 0, 1),
                        2 | 3 => game_fb_pointer_button(handle, 0, 0),
                        _ => {}
                    }
                },
            }
        }
        Some(input::LgInput::Key { name, down }) => match path {
            Some(Path::Android) => {
                let code = input::akeycode(&name);
                if code != 0 {
                    unsafe {
                        if down {
                            siglus_android_key_down(handle, code);
                        } else {
                            siglus_android_key_up(handle, code);
                        }
                    }
                }
            }
            _ => {
                let code = input::vk_code(&name);
                if code != 0 {
                    unsafe { game_fb_key(handle, code, if down { 1 } else { 0 }) };
                }
            }
        },
        Some(input::LgInput::Text(t)) => {
            if let Some(Path::Fb) | None = path {
                if let Ok(c) = CString::new(t) {
                    unsafe { game_fb_text(handle, c.as_ptr()) };
                }
            }
        }
        None => {}
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_siglus_engine_command_json(engine: *mut c_void, json: *const c_char) -> i32 {
    let Some(e) = (engine as *mut SiglusEngine).as_mut() else {
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
pub unsafe extern "C" fn lg_siglus_engine_surface_size(engine: *mut c_void, w: i32, h: i32) -> i32 {
    let Some(e) = (engine as *mut SiglusEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if w <= 0 || h <= 0 {
        return result::INVALID_ARGUMENT;
    }
    e.width.store(w as u32, Ordering::Release);
    e.height.store(h as u32, Ordering::Release);
    let handle = *e.handle.lock().unwrap();
    if !handle.is_null() {
        match *e.path.lock().unwrap() {
            Some(Path::Android) => unsafe { siglus_android_resize(handle, w as u32, h as u32) },
            _ => { /* fb 路径：帧缓冲尺寸由核心自管 */ }
        }
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_siglus_engine_destroy(engine: *mut c_void) -> i32 {
    let Some(e) = (engine as *mut SiglusEngine).as_mut() else {
        return result::OK;
    };
    e.running.store(false, Ordering::Release);
    e.surface_cv.notify_all();
    if let Some(t) = e.thread.lock().unwrap().take() {
        let _ = t.join();
    }
    let handle = *e.handle.lock().unwrap();
    if !handle.is_null() {
        match *e.path.lock().unwrap() {
            Some(Path::Android) => unsafe { siglus_android_destroy(handle) },
            _ => unsafe { game_fb_close(handle) },
        }
        *e.handle.lock().unwrap() = std::ptr::null_mut();
    }
    unsafe { drop(Box::from_raw(e)) };
    result::OK
}
