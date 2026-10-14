//! Android 上下文缓存：Kotlin → C 桥（JNI，持真 jni.h）→ 壳本 crate。
//!
//! 约定：每个壳额外导出 `lg_<id>_set_android_context(java_vm, context)`
//!（可选符号，不在 LG_CORE_API 八符号集内）；桥在 launch 前按 dlsym 探测
//! 并调用。指针原样透传给上游的 `*_android_init_context`（ndk-context）。
//! Rust 侧不做任何 JNI 调用，避免手写 JNI 接口表偏移。

use std::ffi::c_void;
use std::sync::atomic::{AtomicPtr, Ordering};

static JAVA_VM: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());
static CONTEXT: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());

/// 供 `lg_<id>_set_android_context` 调用（幂等，可重复）。
pub fn set_android_context(java_vm: *mut c_void, context: *mut c_void) {
    if !java_vm.is_null() {
        JAVA_VM.store(java_vm, Ordering::Release);
    }
    if !context.is_null() {
        CONTEXT.store(context, Ordering::Release);
    }
}

pub fn java_vm() -> *mut c_void {
    JAVA_VM.load(Ordering::Acquire)
}

pub fn context() -> *mut c_void {
    CONTEXT.load(Ordering::Acquire)
}

/// 两者齐备才返回 true（上游 init_context 需要非空）。
pub fn ready() -> bool {
    !java_vm().is_null() && !context().is_null()
}
