//! 事件发射：核心线程 → lg_event_cb_t(JSON)。
//! JSON 约定（engine_abi.h）：
//!   {"type":"log","level":"info|warn|error","message":"…"}
//!   {"type":"state","state":"running|paused|loading|exited"}
//!   {"type":"exit","code":0}
//!   {"type":"error","message":"…"}

use crate::LgEventCb;
use std::ffi::c_void;

/// 安全发射 JSON 事件（cb/host 为空则丢弃）。
pub fn emit(cb: Option<LgEventCb>, host: *mut c_void, json: &str) {
    if let Some(cb) = cb {
        if let Ok(c) = std::ffi::CString::new(json) {
            unsafe { cb(host, c.as_ptr()) };
        }
    }
}

pub fn log(cb: Option<LgEventCb>, host: *mut c_void, level: &str, message: &str) {
    let m = serde_json::to_string(message).unwrap_or_else(|_| "\"?\"".into());
    emit(cb, host, &format!("{{\"type\":\"log\",\"level\":\"{level}\",\"message\":{m}}}"));
}

pub fn state(cb: Option<LgEventCb>, host: *mut c_void, state: &str) {
    emit(cb, host, &format!("{{\"type\":\"state\",\"state\":\"{state}\"}}"));
}

pub fn exit(cb: Option<LgEventCb>, host: *mut c_void, code: i32) {
    emit(cb, host, &format!("{{\"type\":\"exit\",\"code\":{code}}}"));
}

pub fn error(cb: Option<LgEventCb>, host: *mut c_void, message: &str) {
    let m = serde_json::to_string(message).unwrap_or_else(|_| "\"?\"".into());
    emit(cb, host, &format!("{{\"type\":\"error\",\"message\":{m}}}"));
}
