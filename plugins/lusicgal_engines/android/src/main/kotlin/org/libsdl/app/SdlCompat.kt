package org.libsdl.app

import android.view.Surface

/**
 * SDL2 Android 的最小 Java 胶水（无 SDLActivity 生命周期版本）。
 *
 * SDL2 Android 后端（src/video/android/SDL_android.c 等）在 JNI 初始化与
 * 运行期会回调 org.libsdl.app.SDLActivity / SDLAudioManager 的若干静态方法；
 * LusicGal 不使用 SDLActivity 宿主，故由本文件提供等价静态实现。
 * 取窗路径已被 scripts/patch_sdl_android.sh 覆盖（Android_JNI_GetNativeWindow
 * 直接返回适配器注入的 ANativeWindow），getNativeSurface 仅作兜底。
 *
 * 音频：audioInit 返回失败 → SDL_OpenAudio 失败 → 核心静音运行（v1 约定，
 * 详见 docs/ENGINE_NOTES.md 的 SDL 音频路线图）。
 */
@Suppress("unused")
class SDLActivity {
    companion object {
        /** 宿主渲染面（EngineSurfaceView 注入；null = 无表面）。 */
        @JvmStatic
        var nativeSurface: Surface? = null

        /** SDL JNI 查询的当前表面。 */
        @JvmStatic
        fun getNativeSurface(): Surface? = nativeSurface

        @JvmStatic
        fun setOrientation(w: Int, h: Int, resizable: Boolean, hint: String?) {
            // 由宿主 Flutter 布局决定；SDL 侧忽略。
        }

        @JvmStatic
        fun isChromebook(): Boolean = false

        @JvmStatic
        fun isDeXMode(): Boolean = false

        @JvmStatic
        fun isTablet(): Boolean = false

        @JvmStatic
        fun getManifestEnvironmentVariables(): Boolean = true

        @JvmStatic
        fun getScreenDpi(): Float = 400f

        /** SDL 消息（surface 事件等）—— 无 Activity，忽略。 */
        @JvmStatic
        fun sendMessage(command: Int, param: Int): Boolean = true

        @JvmStatic
        fun getContext(): Any? = null

        @JvmStatic
        fun getStorageDirectory(): String? = null

        /** 剪贴板（未接线）。 */
        @JvmStatic
        fun clipboardGetText(): String? = null

        @JvmStatic
        fun clipboardHasText(): Boolean = false

        @JvmStatic
        fun clipboardSetText(text: String?) {}
    }
}

/** SDL 音频 Java 侧最小实现：初始化即失败（静音运行）。 */
@Suppress("unused")
class SDLAudioManager {
    companion object {
        /** SDL C 侧调用；返回 0 = 失败 → SDL_OpenAudio 报错但不致命。 */
        @JvmStatic
        fun audioInit(sampleRate: Int, is16Bit: Boolean, channelCount: Int): Int = 0

        @JvmStatic
        fun audioSetThreadPriority(threadId: Int, priority: Int) {}

        @JvmStatic
        fun audioWriteShort(buffer: ShortArray?): Int = 0

        @JvmStatic
        fun audioWriteByte(buffer: ByteArray?): Int = 0

        @JvmStatic
        fun audioQuit() {}
    }
}

/** SDL 手柄管理（未接线：核心触摸/键盘已够 v1）。 */
@Suppress("unused")
class SDLControllerManager {
    companion object {
        @JvmStatic
        fun getControllerDeviceIds(): IntArray = IntArray(0)
    }
}
