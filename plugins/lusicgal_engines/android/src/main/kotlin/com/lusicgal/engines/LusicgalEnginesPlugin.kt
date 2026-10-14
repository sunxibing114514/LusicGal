package com.lusicgal.engines

import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.TextView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONArray
import org.json.JSONObject

/**
 * LusicGal 平台桥（v2）：
 * - MethodChannel `lusicgal/engines`：probeEngines / launch / command / pushInput / surfaceSize
 * - EventChannel  `lusicgal/engineEvents`：log / state / exit / core_missing（核心线程 → 主线程）
 * - PlatformView  `lusicgal-engine-view`：核心可用时为 SurfaceView（ANativeWindow 注入），
 *   不可用时为原生占位视图。
 */
class LusicgalEnginesPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 应用上下文（renpy 外板壳 Activity 启动用）。 */
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
        binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, EngineViewFactory())
        // 事件回流：核心线程 → C emit_event → JNI onEvent → 主线程 → EventChannel。
        try {
            CoreNative.setEventSink(CoreEventSink { json ->
                mainHandler.post {
                    // EventChannel 的 sink 只能在主线程调用。
                    eventSink?.success(jsonToDart(JSONObject(json)))
                }
            })
        } catch (_: UnsatisfiedLinkError) {
            // 桥库未打包（核心全缺）：静默 —— 与"核心未打包"路径一致。
        }
        // v2：注入 JVM/应用上下文给核心（kira→cpal→Oboe 音频初始化需要）。
        try {
            CoreNative.initAndroid(binding.applicationContext)
        } catch (_: UnsatisfiedLinkError) {
            // 桥缺失时跳过（核心加载各自的 init_context 由壳自行兜底）。
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probeEngines" -> result.success(mapOf("engines" to EngineHost.probeAll()))
            "launch" -> handleLaunch(call, result)
            "command" -> handleCommand(call, result)
            "pushInput" -> handlePushInput(call, result)
            "surfaceSize" -> handleSurfaceSize(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleLaunch(call: MethodCall, result: MethodChannel.Result) {
        val engineId = call.argument<String>("engineId") ?: "unknown"
        val gameId = call.argument<String>("gameId") ?: ""
        val gamePath = call.argument<String>("gamePath") ?: ""
        val savePath = call.argument<String>("savePath") ?: ""
        @Suppress("UNCHECKED_CAST")
        val options = call.argument<Map<String, Any?>>("options") ?: emptyMap<String, Any?>()

        // Ren'Py Route B：外板壳 Activity（librenpython.so 不经 ABI 桥）。
        if (engineId == "renpy") {
            val appContext = context
            if (appContext == null) {
                result.success(
                    mapOf("ok" to false, "errorCode" to "BAD_STATE", "message" to "无应用上下文")
                )
                return
            }
            val code = RenpyLauncher.launch(appContext, engineId, gameId, gamePath, savePath)
            if (code == null) {
                result.success(mapOf("ok" to true, "message" to null))
            } else {
                postEvent(
                    mapOf(
                        "type" to "core_missing",
                        "data" to mapOf("engineId" to engineId, "gameId" to gameId)
                    )
                )
                result.success(
                    mapOf(
                        "ok" to false,
                        "errorCode" to code,
                        "message" to "Ren'Py 外板壳模块（com.lusicgal.renpy）未安装"
                    )
                )
            }
            return
        }

        val probe = EngineHost.probe(engineId)
        if (probe["available"] != true) {
            postEvent(
                mapOf(
                    "type" to "core_missing",
                    "data" to mapOf("engineId" to engineId, "gameId" to gameId)
                )
            )
            result.success(
                mapOf(
                    "ok" to false,
                    "errorCode" to "CORE_NOT_BUNDLED",
                    "message" to (probe["message"] ?: "核心未打包")
                )
            )
            return
        }
        // 核心已链接：启动参数序列化为 JSON 转交核心 JNI 入口
        // （native/bridge/jni，与 engine_abi.h 的 desc.options_json 对应）。
        val optionsJson = JSONObject(options).toString()
        val code = try {
            CoreNative.launch(engineId, gameId, gamePath, savePath, optionsJson)
        } catch (e: UnsatisfiedLinkError) {
            result.success(
                mapOf(
                    "ok" to false,
                    "errorCode" to "CORE_ENTRY_MISSING",
                    "message" to "核心库已加载但入口符号缺失：${e.message}"
                )
            )
            return
        }
        if (code == 0) {
            LusicgalEnginesPlugin.engineIdHolder = engineId
        }
        result.success(
            mapOf(
                "ok" to (code == 0),
                "message" to if (code == 0) null else "核心返回码 $code"
            )
        )
    }

    private fun handleCommand(call: MethodCall, result: MethodChannel.Result) {
        val command = call.argument<String>("command") ?: return result.error(
            "BAD_ARGS", "command 为空", null
        )
        @Suppress("UNCHECKED_CAST")
        val args = call.argument<Map<String, Any?>>("args") ?: emptyMap<String, Any?>()
        val argsJson = JSONObject(args).toString()
        try {
            CoreNative.command(engineIdHolder ?: "unknown", command, argsJson)
            result.success(null)
        } catch (e: UnsatisfiedLinkError) {
            // 没有活动会话（核心未打包 / 未启动）—— 静默忽略，命令幂等。
            result.success(null)
        }
    }

    /** v2：输入事件注入（JSON 见 engine_abi.h：point/key/text）。 */
    private fun handlePushInput(call: MethodCall, result: MethodChannel.Result) {
        val json = call.argument<String>("json")
            ?: return result.error("BAD_ARGS", "json 为空", null)
        try {
            result.success(CoreNative.pushInput(json))
        } catch (e: UnsatisfiedLinkError) {
            result.success(-2) // LG_ERR_INVALID_STATE
        }
    }

    /** v2：渲染面尺寸变化（旋转/分屏）。 */
    private fun handleSurfaceSize(call: MethodCall, result: MethodChannel.Result) {
        val w = call.argument<Int>("w") ?: 0
        val h = call.argument<Int>("h") ?: 0
        try {
            result.success(CoreNative.surfaceSize(w, h))
        } catch (e: UnsatisfiedLinkError) {
            result.success(-2)
        }
    }

    private fun postEvent(event: Map<String, Any?>) {
        // 供 Dart 侧触发的宿主事件（core_missing 等）走主线程 sink。
        mainHandler.post { eventSink?.success(event) }
    }

    /** org.json → StandardMessageCodec 可编码的 Map/List（递归展开）。 */
    private fun jsonToDart(o: Any?): Any? = when (o) {
        is JSONObject -> {
            val map = mutableMapOf<String, Any?>()
            for (k in o.keys()) map[k] = jsonToDart(o.get(k))
            map
        }
        is JSONArray -> {
            val list = mutableListOf<Any?>()
            for (i in 0 until o.length()) list.add(jsonToDart(o.get(i)))
            list
        }
        JSONObject.NULL -> null
        else -> o
    }

    companion object {
        const val METHOD_CHANNEL = "lusicgal/engines"
        const val EVENT_CHANNEL = "lusicgal/engineEvents"
        const val VIEW_TYPE = "lusicgal-engine-view"

        /** 当前活动会话的引擎 id（由 launch 设置；命令/输入路由用）。 */
        @Volatile
        var engineIdHolder: String? = null
    }
}

/** 事件下沉对象：C 端 emit_event 经 JNI 调用 onEvent(String)（核心线程）。 */
class CoreEventSink(private val emit: (String) -> Unit) {
    fun onEvent(json: String) = emit(json)
}

/**
 * 核心探测/装载（v2 dlsym 模型）：
 * 1. 桥库 liblusicgal_bridge.so 一次性加载（JNI 入口 + 事件回流都在桥）。
 * 2. 每个核心是独立 liblusicgal_<id>.so：先 System.loadLibrary 装载，
 *    再经桥 probeCore 用 dlsym(RTLD_DEFAULT, "lg_<id>_abi_version") 探测。
 * 3. launch 时桥把 JVM/Context 经 lg_<id>_set_android_context 注入核心。
 * 桥或核心缺失不影响 App 其余功能（全部 UnsatisfiedLinkError 容错）。
 */
object EngineHost {
    val engineIds = listOf(
        "kirikiri", "onscripter", "renpy", "siglus",
        "rfvp", "sena", "xsystem35", "artemis"
    )

    @Volatile
    private var bridgeLoaded = false

    /** 每核心 .so 装载结果缓存（loadLibrary 只允许成功一次）。 */
    private val coreLoaded = mutableMapOf<String, Boolean>()

    private fun ensureBridge(): Boolean {
        if (bridgeLoaded) return true
        return try {
            System.loadLibrary("lusicgal_bridge")
            bridgeLoaded = true
            true
        } catch (e: UnsatisfiedLinkError) {
            false
        }
    }

    /** 装载核心库（存在与否都记结果；不存在则后续探测按 0 处理）。 */
    private fun ensureCore(engineId: String): Boolean {
        coreLoaded[engineId]?.let { return it }
        val ok = try {
            System.loadLibrary("lusicgal_$engineId")
            true
        } catch (e: UnsatisfiedLinkError) {
            false
        }
        if (ok) bootstrapSdl(engineId)
        coreLoaded[engineId] = ok
        return ok
    }

    /**
     * SDL 系核心（onscripter/xsystem35）装载后调用 SDL 的音频 JNI 初始化：
     * JNI_OnLoad 只完成 RegisterNatives（绑定 nativeSetupJNI），回调方法表
     * （audioOpen/audioWrite*…）由该调用在 C 侧缓存（SDL_android.c:659）。
     * 不调用 = 音频静默失败（v1 现象）。核心库不含 SDL 时静默跳过。
     */
    private fun bootstrapSdl(engineId: String) {
        if (engineId != "onscripter" && engineId != "xsystem35") return
        org.libsdl.app.SDLActivity.appContext = context?.applicationContext
        try {
            org.libsdl.app.SDLAudioManager.nativeSetupJNI()
        } catch (e: Throwable) {
            android.util.Log.w("LusicgalEngines", "SDL audio JNI bootstrap 失败（${engineId}）：$e")
        }
    }

    fun probeAll(): List<Map<String, Any?>> = engineIds.map { probe(it) }

    fun probe(engineId: String): Map<String, Any?> {
        // Ren'Py Route B：可用性 = 外板壳模块类并入构建（非 loadLibrary）。
        if (engineId == "renpy") {
            return try {
                Class.forName("com.lusicgal.renpy.RenpyGameActivity")
                mapOf(
                    "engineId" to engineId,
                    "available" to true,
                    "version" to "route-b",
                    "message" to null
                )
            } catch (_: ClassNotFoundException) {
                unavailable(engineId, "Ren'Py 外板壳模块未并入构建（modules/renpy/build_android.sh staging）")
            }
        }
        if (!ensureBridge()) {
            return unavailable(engineId, "桥库 liblusicgal_bridge.so 未打包（该 ABI 未构建）")
        }
        ensureCore(engineId)
        return try {
            val abi = CoreNative.coreAbiVersion(engineId)
            if (CoreNative.probeCore(engineId) == 1 && abi > 0) {
                mapOf(
                    "engineId" to engineId,
                    "available" to true,
                    "version" to "0x%08x".format(abi),
                    "message" to null
                )
            } else {
                unavailable(engineId, "核心库未装载（liblusicgal_$engineId.so 未打包进 APK）")
            }
        } catch (e: UnsatisfiedLinkError) {
            unavailable(engineId, "桥库入口缺失：${e.message}")
        }
    }

    private fun unavailable(engineId: String, message: String): Map<String, Any?> = mapOf(
        "engineId" to engineId,
        "available" to false,
        "version" to null,
        "message" to message
    )
}

/** 核心 JNI 入口（native/bridge/jni/lusicgal_jni.c 提供；桥缺失时抛 UnsatisfiedLinkError）。 */
internal object CoreNative {
    @JvmStatic
    external fun launch(
        engineId: String,
        gameId: String,
        gamePath: String,
        savePath: String,
        optionsJson: String
    ): Int

    @JvmStatic
    external fun command(engineId: String, command: String, argsJson: String): Int

    /** v2：探测核心是否链入 bridge（1=在）。 */
    @JvmStatic
    external fun probeCore(engineId: String): Int

    /** v2：核心 ABI 版本（0=缺失）。 */
    @JvmStatic
    external fun coreAbiVersion(engineId: String): Int

    /** v2：输入事件注入（JSON）。 */
    @JvmStatic
    external fun pushInput(json: String): Int

    /** v2：渲染面尺寸（旋转/分屏）。 */
    @JvmStatic
    external fun surfaceSize(w: Int, h: Int): Int

    /** v2：把 Surface（PlatformView 提供）转 ANativeWindow 注入核心。 */
    @JvmStatic
    external fun attachSurface(surface: Any): Int

    /** v2：注册事件下沉对象（onEvent(String)）。 */
    @JvmStatic
    external fun setEventSink(sink: Any?)

    /** v2：注册应用上下文（音频栈初始化用；onAttachedToEngine 调一次）。 */
    @JvmStatic
    external fun initAndroid(context: Any)
}

/**
 * 渲染面工厂：核心可用 → SurfaceView（真实游戏画面）；
 * 不可用 → 占位视图（CORE_NOT_BUNDLED 提示）。
 */
class EngineViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        val engineId = params?.get("engineId") as? String ?: "unknown"
        val gameId = params?.get("gameId") as? String ?: ""
        return if (EngineHost.probe(engineId)["available"] == true) {
            EngineSurfaceView(context)
        } else {
            EnginePlaceholderView(context, engineId, gameId)
        }
    }
}

/** 真实渲染面：SurfaceView → ANativeWindow → lg_<id>_engine_set_surface。 */
internal class EngineSurfaceView(context: Context) : PlatformView, SurfaceHolder.Callback {
    private val surfaceView = SurfaceView(context).apply {
        holder.addCallback(this@EngineSurfaceView)
        // 游戏画面通常不透明；避免额外合成层。
        holder.setKeepScreenOn(true)
        // 触摸 → JSON（归一化坐标）→ JNI pushInput → 核心 push_input。
        // 每次触摸一个 JNI 调用（v2 输入热路径；60Hz 下 JSON 组装开销可忽略）。
        setOnTouchListener { v, ev ->
            val phase = when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> "down"
                MotionEvent.ACTION_MOVE -> "move"
                MotionEvent.ACTION_UP -> "up"
                MotionEvent.ACTION_CANCEL -> "cancel"
                else -> return@setOnTouchListener false
            }
            val w = (v.width.coerceAtLeast(1)).toDouble()
            val h = (v.height.coerceAtLeast(1)).toDouble()
            val json = "{\"type\":\"point\",\"phase\":\"$phase\"," +
                "\"x\":${ev.x / w},\"y\":${ev.y / h},\"pointer\":1}"
            try {
                CoreNative.pushInput(json)
            } catch (_: UnsatisfiedLinkError) {
            }
            true
        }
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        surfaceView.holder.removeCallback(this)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        // SDL 系核心（onscripter/xsystem35）经最小胶水读取宿主面。
        org.libsdl.app.SDLActivity.nativeSurface = holder.surface
        try {
            CoreNative.attachSurface(holder.surface)
        } catch (_: UnsatisfiedLinkError) {
            // 桥缺失：不渲染。
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        org.libsdl.app.SDLActivity.nativeSurface = holder.surface
        try {
            CoreNative.attachSurface(holder.surface)
            CoreNative.surfaceSize(width, height)
        } catch (_: UnsatisfiedLinkError) {
        }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        org.libsdl.app.SDLActivity.nativeSurface = null
        // 核心自行处理面失效（下个 surfaceCreated 重新注入）。
    }
}

/** 核心未打包时的原生占位视图。 */
internal class EnginePlaceholderView(
    context: Context,
    private val engineId: String,
    private val gameId: String
) : PlatformView {
    private val textView = TextView(context).apply {
        setBackgroundColor(Color.rgb(14, 11, 30))
        setTextColor(Color.rgb(185, 168, 255))
        text = "LusicGal 引擎占位渲染面\n\nengine = $engineId\ngame = $gameId\n\n" +
            "核心未打包：该引擎的可执行核心尚未链入（构建开关 LG_ENG_$engineId）。"
        gravity = Gravity.CENTER
        setPadding(48, 48, 48, 48)
    }

    override fun getView(): View = textView

    override fun dispose() {}
}
