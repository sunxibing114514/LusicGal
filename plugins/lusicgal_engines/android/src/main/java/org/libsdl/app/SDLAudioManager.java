package org.libsdl.app;

import android.content.Context;
import android.media.AudioDeviceCallback;
import android.media.AudioDeviceInfo;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.os.Build;
import android.util.Log;

import java.util.Arrays;
import java.util.ArrayList;

// LusicGal：类与 nativeSetupJNI 提为 public —— 宿主 Kotlin
//（com.lusicgal.engines，LusicgalEnginesPlugin.ensureCore）在核心
// loadLibrary 后显式调用以触发 C 侧回调方法表缓存（SDL2 内嵌流程，
// 无 SDLActivity.onCreate 链）；SDL3 侧语义不变（FindClass/RegisterNatives
// 不受可见性影响）。
public class SDLAudioManager {
    protected static final String TAG = "SDLAudio";

    protected static Context mContext;

    private static AudioDeviceCallback mAudioDeviceCallback;

    // ---- LusicGal：SDL2 兼容音频面（合并进 SDL3 java 后唯一类集） ----
    // 本 APK 同时承载 SDL3（renpy 模块）与 SDL2（onscripter 2.26.3 /
    // xsystem35 2.32.10 内嵌核心）。SDL2 的 register_methods 对签名不匹配
    // 的表项仅记日志不致命（SDL_android.c:506-513），且其 C 实现是可
    // dlsym 的动态符号 —— 故 SDL3 的 nativeSetupJNI()V 声明可同时服务
    // 两族：SDL2 侧由 JVM 回落绑到 Java_org_libsdl_app_SDLAudioManager_
    // nativeSetupJNI 符号，随后按名+签名 GetStaticMethodID 缓存下列方法。
    private static AudioTrack mAudioTrack;
    private static AudioRecord mAudioRecord;
    private static final int[] NO_DEVICES = {};

    /** SDL 2.26.3 签名：(IIII)[I。 */
    public static int[] audioOpen(int sampleRate, int audioFormat, int desiredChannels, int desiredFrames) {
        return open(false, sampleRate, audioFormat, desiredChannels, desiredFrames);
    }

    /** SDL 2.32.10 签名：(IIIII)[I（deviceId 忽略 = 默认设备）。 */
    public static int[] audioOpen(int sampleRate, int audioFormat, int desiredChannels, int desiredFrames, int deviceId) {
        return open(false, sampleRate, audioFormat, desiredChannels, desiredFrames);
    }

    public static void audioWriteFloatBuffer(float[] buffer) {
        AudioTrack track = getTrack();
        if (track == null) return;
        int i = 0;
        while (i < buffer.length) {
            int result = track.write(buffer, i, buffer.length - i, AudioTrack.WRITE_BLOCKING);
            if (result > 0) {
                i += result;
            } else if (result == 0) {
                try { Thread.sleep(1); } catch (InterruptedException e) { return; }
            } else {
                Log.w(TAG, "SDL audio: error return from write(float)");
                return;
            }
        }
    }

    public static void audioWriteShortBuffer(short[] buffer) {
        AudioTrack track = getTrack();
        if (track == null) return;
        int i = 0;
        while (i < buffer.length) {
            int result = track.write(buffer, i, buffer.length - i);
            if (result > 0) {
                i += result;
            } else if (result == 0) {
                try { Thread.sleep(1); } catch (InterruptedException e) { return; }
            } else {
                Log.w(TAG, "SDL audio: error return from write(short)");
                return;
            }
        }
    }

    public static void audioWriteByteBuffer(byte[] buffer) {
        AudioTrack track = getTrack();
        if (track == null) return;
        int i = 0;
        while (i < buffer.length) {
            int result = track.write(buffer, i, buffer.length - i);
            if (result > 0) {
                i += result;
            } else if (result == 0) {
                try { Thread.sleep(1); } catch (InterruptedException e) { return; }
            } else {
                Log.w(TAG, "SDL audio: error return from write(byte)");
                return;
            }
        }
    }

    public static void audioClose() {
        AudioTrack track = getTrack();
        if (track != null) {
            track.stop();
            track.release();
        }
        mAudioTrack = null;
    }

    // ---- SDL2 采集（内嵌核心不采集；安全空实现） ----

    public static int[] captureOpen(int sampleRate, int audioFormat, int desiredChannels, int desiredFrames) {
        return null;
    }

    public static int[] captureOpen(int sampleRate, int audioFormat, int desiredChannels, int desiredFrames, int deviceId) {
        return null;
    }

    public static int captureReadFloatBuffer(float[] buffer, boolean blocking) {
        return 0;
    }

    public static int captureReadShortBuffer(short[] buffer, boolean blocking) {
        return 0;
    }

    public static int captureReadByteBuffer(byte[] buffer, boolean blocking) {
        return 0;
    }

    public static void captureClose() {
        AudioRecord record = mAudioRecord;
        if (record != null) {
            record.stop();
            record.release();
        }
        mAudioRecord = null;
    }

    /** SDL2 签名 (ZI)V。 */
    public static void audioSetThreadPriority(boolean recording, int deviceId) {
        try {
            Thread.currentThread().setName((recording ? "SDLAudioC" : "SDLAudioP") + deviceId);
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO);
        } catch (Exception e) {
            Log.v(TAG, "modify thread properties failed " + e.toString());
        }
    }

    /** SDL2 2.32.10 设备枚举（供 C 侧 GetStaticMethodID 命中）。 */
    public static int[] getAudioOutputDevices() {
        Context ctx = mContext;
        if (ctx == null || Build.VERSION.SDK_INT < 24) return NO_DEVICES;
        AudioManager am = (AudioManager) ctx.getSystemService(Context.AUDIO_SERVICE);
        AudioDeviceInfo[] devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS);
        int[] ids = new int[devices.length];
        for (int i = 0; i < devices.length; i++) ids[i] = devices[i].getId();
        return ids;
    }

    public static int[] getAudioInputDevices() {
        Context ctx = mContext;
        if (ctx == null || Build.VERSION.SDK_INT < 24) return NO_DEVICES;
        AudioManager am = (AudioManager) ctx.getSystemService(Context.AUDIO_SERVICE);
        AudioDeviceInfo[] devices = am.getDevices(AudioManager.GET_DEVICES_INPUTS);
        int[] ids = new int[devices.length];
        for (int i = 0; i < devices.length; i++) ids[i] = devices[i].getId();
        return ids;
    }

    private static AudioTrack getTrack() {
        AudioTrack track = mAudioTrack;
        if (track == null) {
            Log.e(TAG, "Attempted to make audio call with uninitialized audio!");
            return null;
        }
        return track;
    }

    private static int[] open(boolean isCapture, int sampleRate, int audioFormat, int desiredChannels, int desiredFrames) {
        Log.v(TAG, "Opening " + (isCapture ? "capture" : "playback") + ", requested " + desiredFrames + " frames of " + desiredChannels + " channel format=" + audioFormat + " audio at " + sampleRate + " Hz");

        if (isCapture) {
            return null;
        }

        int fmt = audioFormat;
        int channels = desiredChannels;

        if (fmt == AudioFormat.ENCODING_PCM_FLOAT && Build.VERSION.SDK_INT < 21) {
            fmt = AudioFormat.ENCODING_PCM_16BIT;
        }
        if (fmt != AudioFormat.ENCODING_PCM_8BIT &&
            fmt != AudioFormat.ENCODING_PCM_16BIT &&
            fmt != AudioFormat.ENCODING_PCM_FLOAT) {
            Log.v(TAG, "Requested format " + fmt + ", getting ENCODING_PCM_16BIT");
            fmt = AudioFormat.ENCODING_PCM_16BIT;
        }

        int sampleSize;
        if (fmt == AudioFormat.ENCODING_PCM_8BIT) {
            sampleSize = 1;
        } else if (fmt == AudioFormat.ENCODING_PCM_FLOAT) {
            sampleSize = 4;
        } else {
            sampleSize = 2;
        }

        int channelConfig;
        switch (channels) {
        case 1: channelConfig = AudioFormat.CHANNEL_OUT_MONO; break;
        case 2: channelConfig = AudioFormat.CHANNEL_OUT_STEREO; break;
        case 3: channelConfig = AudioFormat.CHANNEL_OUT_STEREO | AudioFormat.CHANNEL_OUT_FRONT_CENTER; break;
        case 4: channelConfig = AudioFormat.CHANNEL_OUT_QUAD; break;
        case 5: channelConfig = AudioFormat.CHANNEL_OUT_QUAD | AudioFormat.CHANNEL_OUT_FRONT_CENTER; break;
        case 6: channelConfig = AudioFormat.CHANNEL_OUT_5POINT1; break;
        case 7: channelConfig = AudioFormat.CHANNEL_OUT_5POINT1 | AudioFormat.CHANNEL_OUT_BACK_CENTER; break;
        case 8:
            if (Build.VERSION.SDK_INT >= 23) {
                channelConfig = AudioFormat.CHANNEL_OUT_7POINT1_SURROUND;
            } else {
                channels = 6;
                channelConfig = AudioFormat.CHANNEL_OUT_5POINT1;
            }
            break;
        default:
            Log.v(TAG, "Requested " + channels + " channels, getting stereo");
            channels = 2;
            channelConfig = AudioFormat.CHANNEL_OUT_STEREO;
            break;
        }
        int frameSize = sampleSize * channels;

        int minBufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, fmt);
        if (minBufferSize <= 0) {
            Log.e(TAG, "getMinBufferSize failed: " + minBufferSize);
            return null;
        }
        int frames = Math.max(desiredFrames, (minBufferSize + frameSize - 1) / frameSize);

        AudioTrack track = new AudioTrack(AudioManager.STREAM_MUSIC, sampleRate, channelConfig, fmt,
                frames * frameSize, AudioTrack.MODE_STREAM);
        if (track.getState() != AudioTrack.STATE_INITIALIZED) {
            Log.e(TAG, "Failed during initialization of AudioTrack");
            track.release();
            return null;
        }
        track.play();
        mAudioTrack = track;

        int[] results = new int[4];
        results[0] = track.getSampleRate();
        results[1] = track.getAudioFormat();
        results[2] = track.getChannelCount();
        results[3] = frames;
        Log.v(TAG, "Opening " + (isCapture ? "capture" : "playback") + ", got " + results[3] + " frames of " + results[2] + " channel format=" + results[1] + " audio at " + results[0] + " Hz");
        return results;
    }

    static void initialize() {
        mAudioDeviceCallback = null;

        if(Build.VERSION.SDK_INT >= 24 /* Android 7.0 (N) */)
        {
            mAudioDeviceCallback = new AudioDeviceCallback() {
                @Override
                public void onAudioDevicesAdded(AudioDeviceInfo[] addedDevices) {
                    for (AudioDeviceInfo deviceInfo : addedDevices) {
                        nativeAddAudioDevice(deviceInfo.isSink(), deviceInfo.getProductName().toString(), deviceInfo.getId());
                    }
                }

                @Override
                public void onAudioDevicesRemoved(AudioDeviceInfo[] removedDevices) {
                    for (AudioDeviceInfo deviceInfo : removedDevices) {
                        nativeRemoveAudioDevice(deviceInfo.isSink(), deviceInfo.getId());
                    }
                }
            };
        }
    }

    static void setContext(Context context) {
        mContext = context;
    }

    static void release(Context context) {
        // no-op atm
    }

    // Audio

    private static AudioDeviceInfo getInputAudioDeviceInfo(int deviceId) {
        if (Build.VERSION.SDK_INT >= 24 /* Android 7.0 (N) */) {
            AudioManager audioManager = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);
            for (AudioDeviceInfo deviceInfo : audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)) {
                if (deviceInfo.getId() == deviceId) {
                    return deviceInfo;
                }
            }
        }
        return null;
    }

    private static AudioDeviceInfo getPlaybackAudioDeviceInfo(int deviceId) {
        if (Build.VERSION.SDK_INT >= 24 /* Android 7.0 (N) */) {
            AudioManager audioManager = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);
            for (AudioDeviceInfo deviceInfo : audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                if (deviceInfo.getId() == deviceId) {
                    return deviceInfo;
                }
            }
        }
        return null;
    }

    static void registerAudioDeviceCallback() {
        if (Build.VERSION.SDK_INT >= 24 /* Android 7.0 (N) */) {
            AudioManager audioManager = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);
            // get an initial list now, before hotplug callbacks fire.
            for (AudioDeviceInfo dev : audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                if (dev.getType() == AudioDeviceInfo.TYPE_TELEPHONY) {
                    continue;  // Device cannot be opened
                }
                nativeAddAudioDevice(dev.isSink(), dev.getProductName().toString(), dev.getId());
            }
            for (AudioDeviceInfo dev : audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)) {
                nativeAddAudioDevice(dev.isSink(), dev.getProductName().toString(), dev.getId());
            }
            audioManager.registerAudioDeviceCallback(mAudioDeviceCallback, null);
        }
    }

    static void unregisterAudioDeviceCallback() {
        if (Build.VERSION.SDK_INT >= 24 /* Android 7.0 (N) */) {
            AudioManager audioManager = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);
            audioManager.unregisterAudioDeviceCallback(mAudioDeviceCallback);
        }
    }

    public static native void nativeSetupJNI();

    static native void nativeRemoveAudioDevice(boolean recording, int deviceId);

    static native void nativeAddAudioDevice(boolean recording, String name, int deviceId);

}
