//! ANativeWindow RGBA blit（仅 Android）：CPU 帧缓冲路径（sena / siglus-fb）
//! 把核心输出的 RGBA8888 直接拷进宿主注入的 ANativeWindow。
//!
//! 该路径不依赖任何上游渲染后端 —— 官方 sena Android 壳同款方式。

#![cfg(target_os = "android")]

use std::ffi::c_void;

pub const WINDOW_FORMAT_RGBA_8888: i32 = 1;

#[repr(C)]
pub struct ANativeWindow_Buffer {
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    pub format: i32,
    pub bits: *mut c_void,
    pub reserved: [u64; 4],
}

unsafe extern "C" {
    // ANativeWindow* 由宿主桥（JNI attachSurface）获取引用后传入；
    // 核心只借用（Acquire/Release 由桥管理）。
    fn ANativeWindow_setBuffersGeometry(
        window: *mut c_void,
        width: i32,
        height: i32,
        format: i32,
    ) -> i32;
    fn ANativeWindow_lock(window: *mut c_void, out_buffer: *mut ANativeWindow_Buffer) -> i32;
    fn ANativeWindow_unlockAndPost(window: *mut c_void) -> i32;
}

/// 把 `rgba`（w*h*4 字节，紧密行）blit 进 `window`。
/// 返回 false = 锁缓冲失败（表面尚不可用，调用方下帧重试）。
pub fn blit_rgba(window: *mut c_void, rgba: &[u8], w: u32, h: u32) -> bool {
    if window.is_null() || rgba.len() < (w as usize) * (h as usize) * 4 {
        return false;
    }
    unsafe {
        if ANativeWindow_setBuffersGeometry(
            window,
            w as i32,
            h as i32,
            WINDOW_FORMAT_RGBA_8888,
        ) != 0
        {
            return false;
        }
        let mut buf = ANativeWindow_Buffer {
            width: 0,
            height: 0,
            stride: 0,
            format: 0,
            bits: std::ptr::null_mut(),
            reserved: [0; 4],
        };
        if ANativeWindow_lock(window, &mut buf) != 0 {
            return false;
        }
        let dst = buf.bits as *mut u8;
        let stride = buf.stride.max(0) as usize;
        let copy_w = (buf.width.max(0) as usize).min(w as usize);
        let copy_h = (buf.height.max(0) as usize).min(h as usize);
        if !dst.is_null() && stride >= copy_w {
            for row in 0..copy_h {
                let src_off = row * (w as usize) * 4;
                let dst_off = row * stride * 4;
                std::ptr::copy_nonoverlapping(
                    rgba.as_ptr().add(src_off),
                    dst.add(dst_off),
                    copy_w * 4,
                );
            }
        }
        ANativeWindow_unlockAndPost(window);
    }
    true
}
