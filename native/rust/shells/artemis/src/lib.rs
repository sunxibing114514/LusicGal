//! LusicGal Artemis 核心壳：lg_artemis_engine_* → art3m1s-core C ABI v1。
//!
//! 上游：Alphaly2K/art3m1s-core（Rust 重写，MPL-2.0），Android 默认 Vulkan
//! 后端 + 外部 ANativeWindow。宿主职责：表面、输入、资源挂载、存档目录、
//! 每帧一个 advance；媒体（音频/视频）由 core 发 host-event 命令、宿主执行
//! （v1 壳先把事件原样转 JSON 给宿主 —— 媒体桥是 v2 工作，见
//! native/engines/artemis/README.md）。
//!
//! 版本安全：Art3m1sApiV1 为前缀稳定表（struct_size/abi_version/magic 校验；
//! 新版本只追加字段）。壳镜像全表按序对齐。

use lg_common::{event, input, result, LgEventCb, LG_ABI_VERSION};
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};
use std::time::{Duration, Instant};

pub const ART3M1S_API_ABI_VERSION: u32 = 1;
pub const ART3M1S_API_ABI_MAGIC: u64 = 0x415254334D314150; // "ART3M1AP"

type HostEventsCreateFn = unsafe extern "C" fn() -> *mut c_void;
type HostEventsDestroyFn = unsafe extern "C" fn(*mut c_void);
type HostEventsEnableFn = unsafe extern "C" fn(*mut c_void, i32);
type HostEventsNextFn = unsafe extern "C" fn(*mut c_void) -> usize;
type PollEventsFn =
    unsafe extern "C" fn(*mut c_void, *mut u8, usize, *mut u32) -> usize;
type ResourcesCreateFn = unsafe extern "C" fn() -> *mut c_void;
type ResourcesDestroyFn = unsafe extern "C" fn(*mut c_void);
type ResourcesMountDirectoryFn = unsafe extern "C" fn(*mut c_void, *const c_char) -> i32;
type ResourcesMountPfsFn = unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char) -> i32;
type ResourcesSetSaveDirFn = unsafe extern "C" fn(*mut c_void, *const c_char) -> i32;
type RuntimeCreateFn = unsafe extern "C" fn(u32, u32, i32) -> *mut c_void;
type RuntimeDestroyFn = unsafe extern "C" fn(*mut c_void);
type RuntimeSetResourcesFn = unsafe extern "C" fn(*mut c_void, *mut c_void) -> i32;
type RuntimeAdvanceFn = unsafe extern "C" fn(*mut c_void, u32) -> i32;
type RuntimeStageFn = unsafe extern "C" fn(*const c_void) -> u32;
type RuntimeLoadProjectFn = unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char) -> i32;
type RuntimeSetExternalSurfaceFn =
    unsafe extern "C" fn(*mut c_void, i32, *mut c_void, u32, u32) -> i32;
type RuntimeClearExternalSurfaceFn = unsafe extern "C" fn(*mut c_void);
type RuntimeFeedTouchFn = unsafe extern "C" fn(*mut c_void, u32, u8, i32, i32);
type RuntimeFeedKeyFn = unsafe extern "C" fn(*mut c_void, u32, i32);
type RuntimeSetReportedOsFn = unsafe extern "C" fn(*mut c_void, *const c_char);
type RuntimeSetVolumeFn = unsafe extern "C" fn(*mut c_void, *const c_char, f32);
type RuntimeNotifyLifecycleFn = unsafe extern "C" fn(*mut c_void, i32);
type RuntimeIsExitRequestedFn = unsafe extern "C" fn(*const c_void) -> i32;
type RuntimeConfigureSpatialUpscaleFn = unsafe extern "C" fn(*mut c_void, f32, f32) -> i32;
type RuntimeSetRenderQualityPresetFn = unsafe extern "C" fn(*mut c_void, i32) -> i32;

/// art3m1s-core 的 Art3m1sApiV1 镜像（字段序/类型逐一对齐；新增字段只会
/// 追加在尾部，前缀兼容）。
#[repr(C)]
struct Art3m1sApiV1 {
    struct_size: u32,
    abi_version: u32,
    magic: u64,
    host_events_create: Option<HostEventsCreateFn>,
    host_events_destroy: Option<HostEventsDestroyFn>,
    host_events_enable: Option<HostEventsEnableFn>,
    host_events_next: Option<HostEventsNextFn>,
    poll_events: Option<PollEventsFn>,
    _set_font_list: Option<unsafe extern "C" fn(*mut c_void, i32, i32, *const u8, usize) -> i32>,
    _set_window_state: Option<unsafe extern "C" fn(*mut c_void, i32)>,
    _set_text_replacements: Option<unsafe extern "C" fn(*mut c_void, *const u8, usize) -> i32>,
    _set_text_translation_enabled: Option<unsafe extern "C" fn(*mut c_void, i32)>,
    _clear_host_state: Option<unsafe extern "C" fn(*mut c_void)>,
    resources_create: Option<ResourcesCreateFn>,
    resources_destroy: Option<ResourcesDestroyFn>,
    _resources_clear: Option<unsafe extern "C" fn(*mut c_void)>,
    resources_mount_directory: Option<ResourcesMountDirectoryFn>,
    resources_mount_pfs: Option<ResourcesMountPfsFn>,
    resources_set_save_dir: Option<ResourcesSetSaveDirFn>,
    _resources_set_override:
        Option<unsafe extern "C" fn(*mut c_void, *const c_char, *const u8, usize) -> i32>,
    _resources_clear_overrides: Option<unsafe extern "C" fn(*mut c_void)>,
    runtime_create: Option<RuntimeCreateFn>,
    runtime_destroy: Option<RuntimeDestroyFn>,
    runtime_set_resources: Option<RuntimeSetResourcesFn>,
    _runtime_set_runtime_media_enabled: Option<unsafe extern "C" fn(*mut c_void, i32)>,
    runtime_advance_and_present: Option<RuntimeAdvanceFn>,
    _runtime_advance_without_render: Option<RuntimeAdvanceFn>,
    runtime_stage_width: Option<RuntimeStageFn>,
    runtime_stage_height: Option<RuntimeStageFn>,
    runtime_load_project: Option<RuntimeLoadProjectFn>,
    _runtime_load_project_bytes:
        Option<unsafe extern "C" fn(*mut c_void, *const u8, usize, *const c_char) -> i32>,
    _runtime_pixel_buffer_size: Option<unsafe extern "C" fn(*const c_void) -> u32>,
    _runtime_advance_and_render:
        Option<unsafe extern "C" fn(*mut c_void, u32, *mut u8, u32) -> u32>,
    runtime_set_external_surface: Option<RuntimeSetExternalSurfaceFn>,
    runtime_clear_external_surface: Option<RuntimeClearExternalSurfaceFn>,
    _runtime_feed_mouse: Option<unsafe extern "C" fn(*mut c_void, i32, i32)>,
    _runtime_feed_click: Option<unsafe extern "C" fn(*mut c_void)>,
    _runtime_feed_mouse_button: Option<unsafe extern "C" fn(*mut c_void, u32, i32)>,
    runtime_feed_touch: Option<RuntimeFeedTouchFn>,
    runtime_feed_key: Option<RuntimeFeedKeyFn>,
    _runtime_submit_dialog: Option<unsafe extern "C" fn(*mut c_void, i32, *const c_char) -> i32>,
    _runtime_submit_text_translation:
        Option<unsafe extern "C" fn(*mut c_void, u64, *const c_char) -> i32>,
    runtime_set_reported_os: Option<RuntimeSetReportedOsFn>,
    runtime_configure_spatial_upscale: Option<RuntimeConfigureSpatialUpscaleFn>,
    runtime_set_render_quality_preset: Option<RuntimeSetRenderQualityPresetFn>,
    _runtime_set_profiler_enabled: Option<unsafe extern "C" fn(*const c_void, i32)>,
    _runtime_profiler_snapshot:
        Option<unsafe extern "C" fn(*const c_void, *mut u8, u32) -> i32>,
    runtime_set_volume: Option<RuntimeSetVolumeFn>,
    _runtime_notify_video_finished: Option<unsafe extern "C" fn(*mut c_void, *const c_char)>,
    _runtime_notify_sound_finished: Option<unsafe extern "C" fn(*mut c_void, *const c_char)>,
    runtime_notify_lifecycle: Option<RuntimeNotifyLifecycleFn>,
    runtime_is_exit_requested: Option<RuntimeIsExitRequestedFn>,
    _runtime_backend_capabilities: Option<unsafe extern "C" fn(*const c_void) -> u64>,
    _runtime_submit_http_result:
        Option<unsafe extern "C" fn(*mut c_void, i32, *const u8, i32) -> i32>,
    _runtime_set_string_variable:
        Option<unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char)>,
    _probe_caption:
        Option<unsafe extern "C" fn(*mut c_void, *const u8, usize, *const c_char, *mut u8, i32) -> i32>,
    _set_angle_path: Option<unsafe extern "C" fn(*const c_char)>,
    _set_debug: Option<unsafe extern "C" fn(i32)>,
    _set_damage_visualization: Option<unsafe extern "C" fn(i32)>,
    _set_font_override: Option<unsafe extern "C" fn(*const u8, i32) -> i32>,
    _clear_font_override: Option<unsafe extern "C" fn()>,
    _runtime_upload_video_layer_frame:
        Option<unsafe extern "C" fn(*mut c_void, *const c_char, u32, u32, *const u8, usize) -> i32>,
}

extern "C" {
    fn art3m1s_get_api_v1(out_size: *mut usize) -> *const Art3m1sApiV1;
}

/// host-event 线格式（src/host/events.rs：24B 头，小端）。
const EVENT_HEADER_SIZE: usize = 24;
const EVENT_KIND_LOG: u32 = 1;
const EVENT_KIND_MEDIA: u32 = 2;
const EVENT_KIND_UI: u32 = 3;

struct ArtemisEngine {
    game_path: CString, // 目录或 .pfs 封包
    save_path: CString,
    platform: CString,
    width: AtomicU32,
    height: AtomicU32,
    host: *mut c_void,
    cb: Mutex<Option<LgEventCb>>,
    running: AtomicBool,
    paused: AtomicBool,
    api: &'static Art3m1sApiV1,
    events: *mut c_void,
    resources: *mut c_void,
    runtime: *mut c_void,
    surface: Mutex<Option<(*mut c_void, u32, u32)>>,
    surface_gen: AtomicU64,
    surface_cv: Condvar,
    thread: Mutex<Option<std::thread::JoinHandle<()>>>,
}

unsafe impl Send for ArtemisEngine {}
unsafe impl Sync for ArtemisEngine {}

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

fn api_table() -> Option<&'static Art3m1sApiV1> {
    unsafe {
        let mut size = 0usize;
        let api = art3m1s_get_api_v1(&mut size);
        if api.is_null() || size < std::mem::size_of::<Art3m1sApiV1>() {
            return None;
        }
        let api = &*api;
        if api.abi_version != ART3M1S_API_ABI_VERSION || api.magic != ART3M1S_API_ABI_MAGIC {
            return None;
        }
        if api.struct_size as usize > size {
            return None;
        }
        Some(api)
    }
}

#[no_mangle]
pub extern "C" fn lg_artemis_abi_version() -> u32 {
    LG_ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn lg_artemis_engine_create(desc: *const LgDesc, out: *mut *mut c_void) -> i32 {
    if desc.is_null() || out.is_null() {
        return result::INVALID_ARGUMENT;
    }
    let d = &*desc;
    let game_path = CStr::from_ptr(d.game_path).to_owned();
    if game_path.as_bytes().is_empty() {
        return result::INVALID_ARGUMENT;
    }
    let Some(api) = api_table() else {
        return result::CORE;
    };
    if api.host_events_create.is_none() || api.runtime_create.is_none() {
        return result::CORE;
    }
    let options = if d.options_json.is_null() {
        serde_json::json!({})
    } else {
        serde_json::from_str(CStr::from_ptr(d.options_json).to_string_lossy().as_ref())
            .unwrap_or_else(|_| serde_json::json!({}))
    };
    // 平台伪装（资源分支）：默认 windows（兼容面最广，同 Vita 宿主策略）。
    let platform = CString::new(
        options
            .get("platform")
            .and_then(|v| v.as_str())
            .unwrap_or("windows"),
    )
    .unwrap_or_else(|_| CString::new("windows").unwrap());
    let save_path = if d.save_path.is_null() {
        game_path.clone()
    } else {
        CStr::from_ptr(d.save_path).to_owned()
    };

    let events = unsafe { (api.host_events_create.unwrap())() };
    if events.is_null() {
        return result::CORE;
    }
    if let Some(enable) = api.host_events_enable {
        unsafe { enable(events, 1) };
    }
    let resources = unsafe { (api.resources_create.unwrap())() };
    if resources.is_null() {
        unsafe { (api.host_events_destroy.unwrap())(events) };
        return result::CORE;
    }
    // 挂载：目录 或 .pfs（pf8 加密封装）。
    let path_str = game_path.to_string_lossy();
    let mounted = if path_str.to_lowercase().ends_with(".pfs") {
        let enc = CString::new("pf8").unwrap();
        match api.resources_mount_pfs {
            Some(f) => unsafe { f(resources, game_path.as_ptr(), enc.as_ptr()) },
            None => -1,
        }
    } else {
        match api.resources_mount_directory {
            Some(f) => unsafe { f(resources, game_path.as_ptr()) },
            None => -1,
        }
    };
    if mounted != 0 {
        // pfs 失败回退目录（可能是已解包布局）。
        let ok = match api.resources_mount_directory {
            Some(f) => unsafe { f(resources, game_path.as_ptr()) },
            None => -1,
        };
        if ok != 0 {
            unsafe {
                (api.resources_destroy.unwrap())(resources);
                (api.host_events_destroy.unwrap())(events);
            }
            return result::NOT_FOUND;
        }
    }
    if let Some(set_save) = api.resources_set_save_dir {
        unsafe { set_save(resources, save_path.as_ptr()) };
    }
    let width = options.get("width").and_then(|v| v.as_u64()).unwrap_or(1280) as u32;
    let height = options.get("height").and_then(|v| v.as_u64()).unwrap_or(720) as u32;
    let runtime = unsafe { (api.runtime_create.unwrap())(width, height, 0) };
    if runtime.is_null() {
        unsafe {
            (api.resources_destroy.unwrap())(resources);
            (api.host_events_destroy.unwrap())(events);
        }
        return result::CORE;
    }
    if let Some(set_res) = api.runtime_set_resources {
        unsafe { set_res(runtime, resources) };
    }
    if let Some(set_os) = api.runtime_set_reported_os {
        unsafe { set_os(runtime, platform.as_ptr()) };
    }
    *out = Box::into_raw(Box::new(ArtemisEngine {
        game_path,
        save_path,
        platform,
        width: AtomicU32::new(width),
        height: AtomicU32::new(height),
        host: d.host,
        cb: Mutex::new(None),
        running: AtomicBool::new(false),
        paused: AtomicBool::new(false),
        api,
        events,
        resources,
        runtime,
        surface: Mutex::new(None),
        surface_gen: AtomicU64::new(0),
        surface_cv: Condvar::new(),
        thread: Mutex::new(None),
    })) as *mut c_void;
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_artemis_engine_start(engine: *mut c_void, cb: LgEventCb) -> i32 {
    let Some(e) = (engine as *mut ArtemisEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if e.running.load(Ordering::Acquire) {
        return result::INVALID_STATE;
    }
    *e.cb.lock().unwrap() = Some(cb);
    e.running.store(true, Ordering::Release);
    let t = match std::thread::Builder::new()
        .name("lg_artemis_loop".into())
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
    let e = unsafe { &*(engine_addr as *const ArtemisEngine) };
    let api = e.api;
    let host = e.host;
    let rt = e.runtime;
    // Vulkan present 需要外部表面：等宿主注入（10s 超时）。
    let (win, w, h) = {
        let guard = e.surface.lock().unwrap();
        let (g, _t) = e
            .surface_cv
            .wait_timeout_while(guard, Duration::from_secs(10), |s| s.is_none())
            .unwrap();
        match *g {
            Some(v) => v,
            None => {
                event::error(Some(cb), host, "等待渲染表面超时（artemis Vulkan 需注入 ANativeWindow）");
                event::exit(Some(cb), host, 1);
                e.running.store(false, Ordering::Release);
                return;
            }
        }
    };
    if let Some(set_surf) = api.runtime_set_external_surface {
        unsafe { set_surf(rt, 1 /* ANativeWindow */, win, w, h) };
    }
    // 载入工程（system.ini 由 core 从挂载资源里解析）。
    if let Some(load) = api.runtime_load_project {
        let rc = unsafe { load(rt, e.game_path.as_ptr(), e.platform.as_ptr()) };
        if rc != 0 {
            event::error(Some(cb), host, &format!("runtime_load_project 失败：{rc}"));
            event::exit(Some(cb), host, 1);
            e.running.store(false, Ordering::Release);
            return;
        }
    }
    event::state(Some(cb), host, "running");

    let frame_budget = Duration::from_millis(16);
    let mut last = Instant::now();
    let mut applied_gen = e.surface_gen.load(Ordering::Acquire);
    let mut ev_buf = vec![0u8; 64 * 1024];
    while e.running.load(Ordering::Acquire) {
        if e.paused.load(Ordering::Acquire) {
            std::thread::sleep(Duration::from_millis(40));
            continue;
        }
        let gen_now = e.surface_gen.load(Ordering::Acquire);
        if gen_now != applied_gen {
            if let Some((win2, w2, h2)) = *e.surface.lock().unwrap() {
                if let Some(set_surf) = api.runtime_set_external_surface {
                    unsafe { set_surf(rt, 1, win2, w2, h2) };
                }
            }
            applied_gen = gen_now;
        }
        let dt = last.elapsed().as_millis().min(u32::MAX as u128) as u32;
        last = Instant::now();
        if let Some(advance) = api.runtime_advance_and_present {
            let rc = unsafe { advance(rt, dt) };
            if rc != 0 {
                event::exit(Some(cb), host, rc);
                break;
            }
        }
        // host-events 泵 → JSON 事件（log/media/ui，媒体桥 v2 处理）。
        pump_events(e, cb, &mut ev_buf);
        if let Some(is_exit) = api.runtime_is_exit_requested {
            if unsafe { is_exit(rt) } != 0 {
                event::exit(Some(cb), host, 0);
                break;
            }
        }
        let spent = last.elapsed();
        if spent < frame_budget {
            std::thread::sleep(frame_budget - spent);
        }
    }
    e.running.store(false, Ordering::Release);
}

/// 解析 24B 头事件流并转发宿主：
///   {"type":"artemis_log|artemis_media|artemis_ui","payload":"<utf-8 或 hex>"}
fn pump_events(e: &ArtemisEngine, cb: LgEventCb, buf: &mut [u8]) {
    let Some(poll) = e.api.poll_events else { return };
    let mut count = 0u32;
    let written = unsafe { poll(e.events, buf.as_mut_ptr(), buf.len(), &mut count) };
    if written == 0 || count == 0 {
        return;
    }
    let mut off = 0usize;
    let mut jsons = Vec::with_capacity(count as usize);
    for _ in 0..count {
        if off + EVENT_HEADER_SIZE > written {
            break;
        }
        let kind = u32::from_le_bytes(buf[off + 4..off + 8].try_into().unwrap());
        let payload_len =
            u32::from_le_bytes(buf[off + 16..off + 20].try_into().unwrap()) as usize;
        let aux = u32::from_le_bytes(buf[off + 20..off + 24].try_into().unwrap());
        off += EVENT_HEADER_SIZE;
        if off + payload_len > written {
            break;
        }
        let payload = &buf[off..off + payload_len];
        off += payload_len;
        let type_name = match kind {
            EVENT_KIND_LOG => "artemis_log",
            EVENT_KIND_MEDIA => "artemis_media",
            EVENT_KIND_UI => "artemis_ui",
            _ => continue,
        };
        let payload_str = String::from_utf8_lossy(payload);
        if let Ok(p) = serde_json::to_string(payload_str.as_ref()) {
            jsons.push(format!(
                "{{\"type\":\"{type_name}\",\"aux\":{aux},\"payload\":{p}}}"
            ));
        }
    }
    for j in jsons {
        event::emit(Some(cb), e.host, &j);
    }
}

#[no_mangle]
pub unsafe extern "C" fn lg_artemis_engine_set_surface(engine: *mut c_void, surface: *mut c_void) -> i32 {
    let Some(e) = (engine as *mut ArtemisEngine).as_mut() else {
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
pub unsafe extern "C" fn lg_artemis_engine_push_input(engine: *mut c_void, json: *const c_char) -> i32 {
    let Some(e) = (engine as *mut ArtemisEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if json.is_null() {
        return result::INVALID_ARGUMENT;
    }
    let rt = e.runtime;
    if rt.is_null() {
        return result::INVALID_STATE;
    }
    let Ok(text) = CStr::from_ptr(json).to_str() else {
        return result::INVALID_ARGUMENT;
    };
    match input::parse(text) {
        Some(input::LgInput::Point { phase, x, y, pointer }) => {
            if let Some(feed) = e.api.runtime_feed_touch {
                let px = (x * (e.width.load(Ordering::Acquire) as f64)) as i32;
                let py = (y * (e.height.load(Ordering::Acquire) as f64)) as i32;
                unsafe { feed(rt, pointer, phase, px, py) };
            }
        }
        Some(input::LgInput::Key { name, down }) => {
            let vk = input::vk_code(&name);
            if vk != 0 {
                if let Some(feed) = e.api.runtime_feed_key {
                    unsafe { feed(rt, vk, if down { 1 } else { 0 }) };
                }
            }
        }
        Some(input::LgInput::Text(_)) => { /* 对话框文本提交：v2（submit_dialog 需对话 id）*/ }
        None => {}
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_artemis_engine_command_json(engine: *mut c_void, json: *const c_char) -> i32 {
    let Some(e) = (engine as *mut ArtemisEngine).as_mut() else {
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
    let rt = e.runtime;
    match v.get("command").and_then(|c| c.as_str()).unwrap_or("") {
        "stop" | "quit" => e.running.store(false, Ordering::Release),
        "pause" => {
            e.paused.store(true, Ordering::Release);
            if let Some(n) = e.api.runtime_notify_lifecycle {
                unsafe { n(rt, 1) };
            }
        }
        "resume" => {
            e.paused.store(false, Ordering::Release);
            if let Some(n) = e.api.runtime_notify_lifecycle {
                unsafe { n(rt, 0) };
            }
        }
        "set_volume" => {
            if let (Some(set_vol), Some(channel), Some(value)) = (
                e.api.runtime_set_volume,
                v.get("channel").and_then(|c| c.as_str()),
                v.get("value").and_then(|c| c.as_f64()),
            ) {
                if let Ok(cc) = CString::new(channel) {
                    unsafe { set_vol(rt, cc.as_ptr(), value as f32) };
                }
            }
        }
        _ => {}
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_artemis_engine_surface_size(engine: *mut c_void, w: i32, h: i32) -> i32 {
    let Some(e) = (engine as *mut ArtemisEngine).as_mut() else {
        return result::INVALID_ARGUMENT;
    };
    if w <= 0 || h <= 0 {
        return result::INVALID_ARGUMENT;
    }
    e.width.store(w as u32, Ordering::Release);
    e.height.store(h as u32, Ordering::Release);
    // 舞台分辨率由 core 决定；呈现面尺寸变化经 set_external_surface 通告。
    if let Some((win, _, _)) = *e.surface.lock().unwrap() {
        if let Some(set_surf) = e.api.runtime_set_external_surface {
            unsafe { set_surf(e.runtime, 1, win, w as u32, h as u32) };
        }
    }
    result::OK
}

#[no_mangle]
pub unsafe extern "C" fn lg_artemis_engine_destroy(engine: *mut c_void) -> i32 {
    let Some(e) = (engine as *mut ArtemisEngine).as_mut() else {
        return result::OK;
    };
    e.running.store(false, Ordering::Release);
    e.surface_cv.notify_all();
    if let Some(t) = e.thread.lock().unwrap().take() {
        let _ = t.join();
    }
    let api = e.api;
    unsafe {
        if let Some(clear) = api.runtime_clear_external_surface {
            clear(e.runtime);
        }
        if let Some(destroy) = api.runtime_destroy {
            destroy(e.runtime);
        }
        if let Some(destroy) = api.resources_destroy {
            destroy(e.resources);
        }
        if let Some(destroy) = api.host_events_destroy {
            destroy(e.events);
        }
    }
    unsafe { drop(Box::from_raw(e)) };
    result::OK
}
