package org.libsdl.app

import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.os.Build
import android.util.Log
import android.view.Surface

/**
 * SDL2 Android 的最小 Java 胶水（无 SDLActivity 生命周期版本）。
 *
 * SDL2 Android 后端（src/core/android/SDL_android.c）在 JNI_OnLoad 里把
 * org.libsdl.app.SDLAudioManager.nativeSetupJNI 绑定到 C 侧（RegisterNatives，
 * 见 2.26.3 SDL_android.c:224-226）；随后由 Java 侧调用该 native 完成回调
 * 方法表缓存（audioOpen/audioWrite*/…，SDL_android.c:659-694）——音频缓存
 * 只依赖 mAudioManagerClass，不依赖 SDLActivity 类，因此无 Activity 宿主下
 * 也能获得真实 AudioTrack 音频。EngineHost.ensureCore 在 loadLibrary 后调用
 * nativeSetupJNI（见 LusicgalEnginesPlugin.kt）。
 *
 * 取窗路径已被 scripts/patch_sdl_android.sh 覆盖（Android_JNI_GetNativeWindow
 * 直接返回适配器注入的 ANativeWindow），getNativeSurface 仅作兜底。
 *
 * 双版本兼容：SDL 2.26.3（OnscripterYuri 栈）调 audioOpen(IIII)[I；
 * SDL 2.32.10（xsystem35 栈）调 audioOpen(IIIII)[I —— 两个重载都提供，
 * JNI 按签名解析。
 */
@Suppress("unused")
class SDLActivity {
    companion object {
        /** 宿主渲染面（EngineSurfaceView 注入；null = 无表面）。 */
        @JvmStatic
        var nativeSurface: Surface? = null

        /** 宿主 Application context（LusicgalEnginesPlugin 注入；设备枚举用）。 */
        @JvmStatic
        var appContext: android.content.Context? = null

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
        fun getContext(): Any? = appContext

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

/**
 * SDL 音频 Java 侧完整实现（移植自 SDL2-2.32.10 android-project
 * SDLAudioManager.java，2.26.3 子集兼容）：
 * - audioOpen → AudioTrack(MODE_STREAM) 实时输出；
 * - audioWrite{Byte,Short,Float}Buffer → 阻塞写循环；
 * - capture*：核心（ONS/xsystem35）不采集；安全空实现。
 * 音频回调线程由 SDL C 侧创建（audioSetThreadPriority 提权）。
 */
@Suppress("unused")
class SDLAudioManager {
    companion object {
        private const val TAG = "SDLAudio"
        private val NO_DEVICES = IntArray(0)

        @JvmStatic
        private var mAudioTrack: AudioTrack? = null
        @JvmStatic
        private var mAudioRecord: AudioRecord? = null

        /** SDL JNI_OnLoad（RegisterNatives）绑定的初始化入口。 */
        @JvmStatic
        external fun nativeSetupJNI(): Int

        /**
         * SDL 2.32.10 的 RegisterNatives 表包含全部三个符号（SDL_android.c:232-236），
         * 缺一即整表注册失败 → nativeSetupJNI 不可调 → 音频静默失败。
         * 2.26.3 表只有 nativeSetupJNI；这两个声明在 2.26 核心下未绑定但不被
         * 调用（我们从不注册 AudioDeviceCallback —— 不实现 initialize/setContext）。
         */
        @JvmStatic
        external fun addAudioDevice(isCapture: Boolean, deviceId: Int)

        @JvmStatic
        external fun removeAudioDevice(isCapture: Boolean, deviceId: Int)

        // ---- 供 C 侧查询的设备枚举（2.32.10；空 = 走默认设备） ----

        @JvmStatic
        fun getAudioOutputDevices(): IntArray {
            val ctx = SDLActivity.getContext() as? android.content.Context ?: return NO_DEVICES
            if (Build.VERSION.SDK_INT < 24) return NO_DEVICES
            val am = ctx.getSystemService(android.content.Context.AUDIO_SERVICE) as AudioManager
            return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { it.id }.toIntArray()
        }

        @JvmStatic
        fun getAudioInputDevices(): IntArray {
            val ctx = SDLActivity.getContext() as? android.content.Context ?: return NO_DEVICES
            if (Build.VERSION.SDK_INT < 24) return NO_DEVICES
            val am = ctx.getSystemService(android.content.Context.AUDIO_SERVICE) as AudioManager
            return am.getDevices(AudioManager.GET_DEVICES_INPUTS).map { it.id }.toIntArray()
        }

        // ---- 播放 ----

        /** SDL 2.26.3 签名：(IIII)[I。 */
        @JvmStatic
        fun audioOpen(sampleRate: Int, audioFormat: Int, desiredChannels: Int, desiredFrames: Int): IntArray? =
            open(false, sampleRate, audioFormat, desiredChannels, desiredFrames)

        /** SDL 2.32.10 签名：(IIIII)[I（deviceId=0 = 默认设备）。 */
        @JvmStatic
        fun audioOpen(sampleRate: Int, audioFormat: Int, desiredChannels: Int, desiredFrames: Int, deviceId: Int): IntArray? =
            open(false, sampleRate, audioFormat, desiredChannels, desiredFrames)

        @JvmStatic
        fun audioWriteFloatBuffer(buffer: FloatArray) {
            val track = mAudioTrack ?: run {
                Log.e(TAG, "Attempted to make audio call with uninitialized audio!")
                return
            }
            var i = 0
            while (i < buffer.size) {
                val result = track.write(buffer, i, buffer.size - i, AudioTrack.WRITE_BLOCKING)
                if (result > 0) {
                    i += result
                } else if (result == 0) {
                    try { Thread.sleep(1) } catch (_: InterruptedException) {}
                } else {
                    Log.w(TAG, "SDL audio: error return from write(float)")
                    return
                }
            }
        }

        @JvmStatic
        fun audioWriteShortBuffer(buffer: ShortArray) {
            val track = mAudioTrack ?: run {
                Log.e(TAG, "Attempted to make audio call with uninitialized audio!")
                return
            }
            var i = 0
            while (i < buffer.size) {
                val result = track.write(buffer, i, buffer.size - i)
                if (result > 0) {
                    i += result
                } else if (result == 0) {
                    try { Thread.sleep(1) } catch (_: InterruptedException) {}
                } else {
                    Log.w(TAG, "SDL audio: error return from write(short)")
                    return
                }
            }
        }

        @JvmStatic
        fun audioWriteByteBuffer(buffer: ByteArray) {
            val track = mAudioTrack ?: run {
                Log.e(TAG, "Attempted to make audio call with uninitialized audio!")
                return
            }
            var i = 0
            while (i < buffer.size) {
                val result = track.write(buffer, i, buffer.size - i)
                if (result > 0) {
                    i += result
                } else if (result == 0) {
                    try { Thread.sleep(1) } catch (_: InterruptedException) {}
                } else {
                    Log.w(TAG, "SDL audio: error return from write(byte)")
                    return
                }
            }
        }

        @JvmStatic
        fun audioClose() {
            mAudioTrack?.let {
                it.stop()
                it.release()
            }
            mAudioTrack = null
        }

        // ---- 采集（核心不使用；安全空实现，避免 SDL 报缺回调） ----

        /** SDL 2.26.3 签名。 */
        @JvmStatic
        fun captureOpen(sampleRate: Int, audioFormat: Int, desiredChannels: Int, desiredFrames: Int): IntArray? = null

        /** SDL 2.32.10 签名。 */
        @JvmStatic
        fun captureOpen(sampleRate: Int, audioFormat: Int, desiredChannels: Int, desiredFrames: Int, deviceId: Int): IntArray? = null

        @JvmStatic
        fun captureReadFloatBuffer(buffer: FloatArray, blocking: Boolean): Int = 0

        @JvmStatic
        fun captureReadShortBuffer(buffer: ShortArray, blocking: Boolean): Int = 0

        @JvmStatic
        fun captureReadByteBuffer(buffer: ByteArray, blocking: Boolean): Int = 0

        @JvmStatic
        fun captureClose() {
            mAudioRecord?.let {
                it.stop()
                it.release()
            }
            mAudioRecord = null
        }

        /** SDL 签名 (ZI)V：音频回调线程命名 + THREAD_PRIORITY_AUDIO。 */
        @JvmStatic
        fun audioSetThreadPriority(iscapture: Boolean, deviceId: Int) {
            try {
                Thread.currentThread().name = (if (iscapture) "SDLAudioC" else "SDLAudioP") + deviceId
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO)
            } catch (e: Exception) {
                Log.v(TAG, "modify thread properties failed $e")
            }
        }

        // ---- 核心 ----

        @JvmStatic
        private fun open(isCapture: Boolean, sampleRate: Int, audioFormat: Int, desiredChannels: Int, desiredFrames: Int): IntArray? {
            val tag = if (isCapture) "capture" else "playback"
            Log.v(TAG, "Opening $tag, requested $desiredFrames frames of $desiredChannels channel format=$audioFormat audio at $sampleRate Hz")

            if (isCapture) {
                // 核心不采集；直接失败（SDL 侧优雅处理）。
                return null
            }

            var fmt = audioFormat
            var channels = desiredChannels
            if (fmt == AudioFormat.ENCODING_PCM_FLOAT && Build.VERSION.SDK_INT < 21) {
                fmt = AudioFormat.ENCODING_PCM_16BIT
            }
            if (fmt != AudioFormat.ENCODING_PCM_8BIT &&
                fmt != AudioFormat.ENCODING_PCM_16BIT &&
                fmt != AudioFormat.ENCODING_PCM_FLOAT
            ) {
                Log.v(TAG, "Requested format $fmt, getting ENCODING_PCM_16BIT")
                fmt = AudioFormat.ENCODING_PCM_16BIT
            }
            val sampleSize = when (fmt) {
                AudioFormat.ENCODING_PCM_8BIT -> 1
                AudioFormat.ENCODING_PCM_FLOAT -> 4
                else -> 2
            }

            val channelConfig = when (channels) {
                1 -> AudioFormat.CHANNEL_OUT_MONO
                2 -> AudioFormat.CHANNEL_OUT_STEREO
                3 -> AudioFormat.CHANNEL_OUT_STEREO or AudioFormat.CHANNEL_OUT_FRONT_CENTER
                4 -> AudioFormat.CHANNEL_OUT_QUAD
                5 -> AudioFormat.CHANNEL_OUT_QUAD or AudioFormat.CHANNEL_OUT_FRONT_CENTER
                6 -> AudioFormat.CHANNEL_OUT_5POINT1
                7 -> AudioFormat.CHANNEL_OUT_5POINT1 or AudioFormat.CHANNEL_OUT_BACK_CENTER
                8 ->
                    if (Build.VERSION.SDK_INT >= 23) AudioFormat.CHANNEL_OUT_7POINT1_SURROUND
                    else {
                        channels = 6
                        AudioFormat.CHANNEL_OUT_5POINT1
                    }
                else -> {
                    Log.v(TAG, "Requested $channels channels, getting stereo")
                    channels = 2
                    AudioFormat.CHANNEL_OUT_STEREO
                }
            }
            val frameSize = sampleSize * channels

            val minBufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, fmt)
            if (minBufferSize <= 0) {
                Log.e(TAG, "getMinBufferSize failed: $minBufferSize")
                return null
            }
            val frames = maxOf(desiredFrames, (minBufferSize + frameSize - 1) / frameSize)

            val track = AudioTrack(
                AudioManager.STREAM_MUSIC, sampleRate, channelConfig, fmt,
                frames * frameSize, AudioTrack.MODE_STREAM
            )
            if (track.state != AudioTrack.STATE_INITIALIZED) {
                Log.e(TAG, "Failed during initialization of AudioTrack")
                track.release()
                return null
            }
            track.play()
            mAudioTrack = track

            val results = IntArray(4)
            results[0] = track.sampleRate
            results[1] = track.audioFormat
            results[2] = track.channelCount
            results[3] = frames
            Log.v(TAG, "Opening $tag, got ${results[3]} frames of ${results[2]} channel format=${results[1]} audio at ${results[0]} Hz")
            return results
        }
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
