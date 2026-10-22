package com.lusicgal.engines

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
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
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * LusicGal 平台桥（v2）：
 * - MethodChannel `lusicgal/engines`：probeEngines / launch / command / pushInput / surfaceSize / pickGameFolder
 * - EventChannel  `lusicgal/engineEvents`：log / state / exit / core_missing（核心线程 → 主线程）
 * - PlatformView  `lusicgal-engine-view`：核心可用时为 SurfaceView（ANativeWindow 注入），
 *   不可用时为原生占位视图。
 */
class LusicgalEnginesPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, io.flutter.plugin.common.PluginRegistry.ActivityResultListener,
    io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 应用上下文（renpy 外板壳 Activity 启动用）。 */
    private var context: Context? = null

    /** 当前宿主 Activity（pickGameFolder 的 SAF 选择器需要）。 */
    private var currentActivity: Activity? = null

    /** 待回答的文件夹选择结果（一次只允许一个选择器）。 */
    @Volatile
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        EngineHost.appContext = binding.applicationContext
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
        // 装载所有库（用户指令）：后台线程预装载全部核心（带崩溃环护）。
        try {
            EngineHost.preloadAll(binding.applicationContext)
        } catch (_: Throwable) {
            // 预装载失败不影响 App —— 懒装载兜底。
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        context = null
        EngineHost.appContext = null
    }

    // ---- ActivityAware：SAF 文件夹选择器（pickGameFolder）生命周期 ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        currentActivity = null
        // 选择器进行中 Activity 被拆：直接取消，避免悬挂 Result。
        pendingFolderResult?.success(mapOf("ok" to false, "message" to "已取消"))
        pendingFolderResult = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_GAME_FOLDER) return false
        val result = pendingFolderResult ?: return true
        pendingFolderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(mapOf("ok" to false, "message" to "已取消"))
            return true
        }
        // 持久化授权：重启后仍可经 /storage 直路径读取（Android 11+ FUSE 落地）。
        try {
            currentActivity?.contentResolver?.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: SecurityException) {
            // 部分 ROM 不发持久化授权：当次会话仍可用。
        }
        val path = resolveRealPath(uri)
        var readable = false
        if (path != null) {
            val dir = File(path)
            // list()==null 即不可枚举（EACCES），Android 10 直路径受限场景。
            readable = dir.isDirectory && dir.canRead() && dir.list() != null
        }
        val name = folderDisplayName(uri)
        result.success(
            mapOf(
                "ok" to true,
                "uri" to uri.toString(),
                "path" to path,
                "name" to name,
                "readable" to readable,
                "message" to if (readable) null
                else "该文件夹无法直接读取（存储权限未授予或设备限制）。"
            )
        )
        return true
    }

    /**
     * SAF 树 URI → 真实文件系统路径（原生核心与本地 HTTP 服务都需要直路径）。
     * 文档 ID 形如 "primary:Games/Foo" / "XXXX-XXXX:demos"。
     */
    private fun resolveRealPath(treeUri: Uri): String? {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val colon = docId.indexOf(':')
            if (colon <= 0) return null
            val volume = docId.substring(0, colon)
            val rel = docId.substring(colon + 1)
            val base = if (volume == "primary") {
                @Suppress("DEPRECATION")
                Environment.getExternalStorageDirectory().absolutePath
            } else {
                "/storage/$volume"
            }
            if (rel.isBlank()) base else base + "/" + rel
        } catch (_: Throwable) {
            null
        }
    }

    private fun folderDisplayName(treeUri: Uri): String {
        val path = resolveRealPath(treeUri) ?: return "文件夹"
        val segs = path.split('/').filter { it.isNotBlank() }
        return segs.lastOrNull() ?: "文件夹"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probeEngines" -> result.success(mapOf("engines" to EngineHost.probeAll()))
            "launch" -> handleLaunch(call, result)
            "command" -> handleCommand(call, result)
            "pushInput" -> handlePushInput(call, result)
            "surfaceSize" -> handleSurfaceSize(call, result)
            "pickGameFolder" -> handlePickGameFolder(result)
            else -> result.notImplemented()
        }
    }

    /** SAF 选择游戏文件夹：ACTION_OPEN_DOCUMENT_TREE，返回 {uri,path,name,readable}。 */
    private fun handlePickGameFolder(result: MethodChannel.Result) {
        val act = currentActivity
        if (act == null) {
            result.success(mapOf("ok" to false, "message" to "宿主 Activity 未就绪，请稍后再试"))
            return
        }
        if (pendingFolderResult != null) {
            result.success(mapOf("ok" to false, "message" to "已有文件夹选择器进行中"))
            return
        }
        pendingFolderResult = result
        // 外部目录全系统直读（用户指令）：targetSdk 29 + legacy 存储模型下，
        // 共享目录直读需运行时 READ 权限（Android 6+）。申请后无论授予与否
        // 都继续 SAF 选择 —— SAF 流不需要该权限；授予则直路径探测在
        // Android 10 上也能通过（v0.1.2 降级路径就此消除）。
        try {
            if (act.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                act.requestPermissions(
                    arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE),
                    REQUEST_PERM_STORAGE
                )
                return // onRequestPermissionsResult 里接续发选择器。
            }
        } catch (_: Throwable) {
            // 权限 API 异常（极旧 ROM）—— 直接进选择器。
        }
        launchFolderPicker()
    }

    private fun launchFolderPicker() {
        val act = currentActivity ?: run {
            pendingFolderResult?.success(mapOf("ok" to false, "message" to "宿主 Activity 未就绪"))
            pendingFolderResult = null
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            act.startActivityForResult(intent, REQUEST_PICK_GAME_FOLDER)
        } catch (t: Throwable) {
            pendingFolderResult?.success(
                mapOf("ok" to false, "message" to "无法打开系统文件夹选择器：${t.message}")
            )
            pendingFolderResult = null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_PERM_STORAGE) return false
        // 无论授予与否继续选择器流程（SAF 本身不依赖该权限）。
        launchFolderPicker()
        return true
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

        // ---- Web 引擎（Tyrano / RPG MV / MZ）：内置 WebView 跑法 ----
        if (engineId == "tyrano" || engineId == "rpgmv" || engineId == "rpgmz") {
            val appContext = context
            if (appContext == null) {
                result.success(mapOf("ok" to false, "errorCode" to "BAD_STATE", "message" to "无应用上下文"))
                return
            }
            if (gamePath.isBlank()) {
                result.success(mapOf("ok" to false, "errorCode" to "BAD_ARGS", "message" to "游戏目录为空"))
                return
            }
            try {
                com.lusicgal.engines.web.WebGameActivity.start(appContext, gamePath, engineId, savePath)
                result.success(mapOf("ok" to true, "message" to null))
            } catch (t: Throwable) {
                result.success(mapOf("ok" to false, "errorCode" to "LAUNCH_FAILED", "message" to "${t.message}"))
            }
            return
        }

        // 启动时才真正装载（bridge + core + SDL 引导）；
        // 失败全部走 CORE_NOT_BUNDLED 可恢复路径，绝不崩 App。
        val nativeReady = try {
            EngineHost.ensureNative(engineId)
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.w("LusicgalEngines", "装载核心失败（$engineId）：$e")
            false
        } catch (t: Throwable) {
            android.util.Log.w("LusicgalEngines", "装载核心异常（$engineId）：$t")
            false
        }
        if (!nativeReady) {
            postEvent(
                mapOf(
                    "type" to "core_missing",
                    "data" to mapOf("engineId" to engineId, "gameId" to gameId)
                )
            )
            val why = EngineHost.lastLoadError ?: "未知原因"
            result.success(
                mapOf(
                    "ok" to false,
                    "errorCode" to "CORE_NOT_BUNDLED",
                    "message" to "核心库装载失败：$why"
                )
            )
            return
        }
        // 核心已链接：启动参数序列化为 JSON 转交核心 JNI 入口
        // （native/bridge/jni，与 engine_abi.h 的 desc.options_json 对应）。
        val optionsJson = JSONObject(options).toString()
        var code = try {
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
        if (code == -2) {
            // 会话泄漏自愈（v0.1.7 病根修复）：C 侧 g_session 只有 shutdown()
            // 会清 —— 旧版 Dart 从不调它，退出后再启动必 -2。清掉重试一次。
            android.util.Log.w("LusicgalEngines", "launch -2（残留会话），shutdown 后重试")
            try {
                CoreNative.shutdown()
            } catch (_: Throwable) {
            }
            code = try {
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
        }
        if (code == 0) {
            LusicgalEnginesPlugin.engineIdHolder = engineId
        }
        result.success(
            mapOf(
                "ok" to (code == 0),
                "message" to if (code == 0) null else launchErrorLabel(code)
            )
        )
    }

    /** lg_result_t（engine_abi.h）→ 用户可读的失败原因。 */
    private fun launchErrorLabel(code: Int): String {
        val what = when (code) {
            -1 -> "启动参数无效（-1）"
            -2 -> "已有游戏会话未结束（-2，已自动清理仍失败请重启 App）"
            -3 -> "核心不支持该操作（-3）"
            -4 -> "打开游戏文件失败（-4：路径不可读或关键文件缺失）"
            -5 -> "核心内部错误（-5）"
            -6 -> "资源未找到（-6）"
            -7 -> "核心启动超时（-7）"
            else -> "核心返回码 $code"
        }
        return what
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
            if (command == "stop") {
                // stop = 会话终结（v0.1.7 会话泄漏修复）：C 侧 g_session 只有
                // shutdown() 会清 —— Dart 的 stop 走 command 通道从不清会话，
                // 退出后再启动必 -2。stop 后立刻销毁会话（幂等）。
                try {
                    CoreNative.shutdown()
                } catch (_: Throwable) {
                }
                engineIdHolder = null
            }
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

        /** SAF 选游戏文件夹的 startActivityForResult 请求码。 */
        private const val REQUEST_PICK_GAME_FOLDER = 47001

        /** 外部目录 READ 权限的 requestPermissions 请求码。 */
        private const val REQUEST_PERM_STORAGE = 47002

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
    /** 宿主注入的应用上下文（onAttachedToEngine 设置；bootstrapSdl/probe 用）。 */
    @Volatile
    var appContext: Context? = null
    val engineIds = listOf(
        // ABI v2 原生核心（dlsym 桥派发）。
        "kirikiri", "onscripter", "renpy", "siglus",
        "rfvp", "sena", "xsystem35", "artemis",
        // Web 引擎（内置 WebView 跑法）。
        "tyrano", "rpgmv", "rpgmz"
    )

    @Volatile
    private var bridgeLoaded = false

    /** 每核心 .so 装载结果缓存（loadLibrary 只允许成功一次）。 */
    private val coreLoaded = mutableMapOf<String, Boolean>()

    /** 最近一次装载失败的真实原因（dlopen 错误原文；成功为 null）。 */
    @Volatile
    var lastLoadError: String? = null
        private set

    private fun ensureBridge(): Boolean {
        if (bridgeLoaded) return true
        return try {
            System.loadLibrary("lusicgal_bridge")
            bridgeLoaded = true
            true
        } catch (e: UnsatisfiedLinkError) {
            lastLoadError = "bridge: $e"
            android.util.Log.w("LusicgalEngines", "装载 bridge 失败：$e")
            false
        } catch (t: Throwable) {
            lastLoadError = "bridge: $t"
            android.util.Log.w("LusicgalEngines", "装载 bridge 失败：$t")
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
            lastLoadError = "lusicgal_$engineId: $e"
            android.util.Log.w("LusicgalEngines", "装载核心 $engineId 失败：$e")
            false
        } catch (t: Throwable) {
            lastLoadError = "lusicgal_$engineId: $t"
            android.util.Log.w("LusicgalEngines", "装载核心 $engineId 失败：$t")
            false
        }
        if (ok) bootstrapSdl(engineId)
        coreLoaded[engineId] = ok
        writePreloadResult(engineId, ok)
        return ok
    }

    /** 预装载结果落盘（引擎页可见；用户报障时可直接读出真实原因）。 */
    private fun writePreloadResult(engineId: String, ok: Boolean) {
        try {
            val f = File(
                appContext?.applicationContext?.filesDir,
                "lg_preload_$engineId.txt"
            )
            f.writeText(if (ok) "ok" else (lastLoadError ?: "装载失败"))
        } catch (_: Throwable) {
        }
    }

    /**
     * SDL 系核心（onscripter/xsystem35）装载后调用 SDL 的音频 JNI 初始化：
     * JNI_OnLoad 只完成 RegisterNatives（绑定 nativeSetupJNI），回调方法表
     * （audioOpen/audioWrite*…）由该调用在 C 侧缓存（SDL_android.c:659）。
     * 不调用 = 音频静默失败（v1 现象）。核心库不含 SDL 时静默跳过。
     */
    private fun bootstrapSdl(engineId: String) {
        if (engineId != "onscripter" && engineId != "xsystem35") return
        org.libsdl.app.SDLActivity.appContext = appContext?.applicationContext
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
        // Web 引擎：WebView 内置即用。
        if (engineId == "tyrano" || engineId == "rpgmv" || engineId == "rpgmz") {
            return mapOf(
                "engineId" to engineId,
                "available" to true,
                "version" to "webview",
                "message" to null
            )
        }
        // 2026-10-19 打开闪退修复：探测绝不再 System.loadLibrary。
        // 旧实现经 IndexedStack（书库/存档/引擎/设置四页同时构建）在 App 启动即
        // 连环 dlopen 九个核心（engine_api 45MB、双 SDL、Oboe 初始化……），
        // 任何一环在老系统（Android 10 实测）上失败/崩溃 = 整个 App 打开闪退。
        // 改为存在性检查（零链接、零崩溃面）；真正装载只发生在 handleLaunch
        // （用户点"开始游戏"时）与 preloadAll（启动后台线程）。
        if (!coreBundled(engineId)) {
            return unavailable(engineId, "核心库未打包（liblusicgal_$engineId.so 不在包内）")
        }
        // 预装载/最近装载的真实结果（预装载线程或上次启动写入）。
        val loadNote = try {
            File(
                appContext?.applicationContext?.filesDir,
                "lg_preload_$engineId.txt"
            ).takeIf { it.isFile }?.readText()?.trim()
        } catch (_: Throwable) {
            null
        }
        return if (loadNote != null && loadNote != "ok") {
            mapOf(
                "engineId" to engineId,
                "available" to true,
                "version" to "bundled",
                "message" to "已打包，但装载失败：$loadNote"
            )
        } else {
            mapOf(
                "engineId" to engineId,
                "available" to true,
                "version" to if (loadNote == "ok") "loaded" else "bundled",
                "message" to null
            )
        }
    }

    /**
     * 包内核心 .so 是否存在（零链接探测）。
     *
     * v0.1.4 现机实测教训：Flutter release 默认 useLegacyPackaging=false
     * —— .so 不提取到 nativeLibraryDir（System.loadLibrary 由 dlopen
     * 直接吃 APK），单一目录检查让 7 个桥接核心全军误报"未打包"
     * （引擎页只显示 web + renpy）。双探针兜底全形态：
     * 1) nativeLibraryDir 已提取路径（extractNativeLibs=true 变体/ROM）；
     * 2) APK 内 lib/<abi>/ zip 条目（默认形态；ZipFile 只读中央目录索引，
     *    秒回、零链接）。
     */
    private fun coreBundled(engineId: String): Boolean {
        val ctx = appContext ?: return false
        val name = "liblusicgal_$engineId.so"
        val dir = ctx.applicationInfo?.nativeLibraryDir
        if (dir != null && File(dir, name).isFile) return true
        val apk = ctx.applicationInfo?.sourceDir ?: return false
        return try {
            java.util.zip.ZipFile(apk).use { zip ->
                for (abi in android.os.Build.SUPPORTED_ABIS) {
                    if (zip.getEntry("lib/$abi/$name") != null) return true
                }
                false
            }
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * 启动时装载原生核心（bridge + core + SDL 音频 JNI 引导）。
     * 只在 handleLaunch 调用 —— 探测（probe）已改为零装载。
     * 返回 false = 不可用（.so 缺失或链接失败，全部可恢复，不崩 App）。
     */
    fun ensureNative(engineId: String): Boolean {
        if (!coreBundled(engineId)) return false
        if (!ensureBridge()) return false
        return ensureCore(engineId)
    }

    /**
     * 装载所有库（用户指令）：App 启动时后台线程把 7 个桥接核心全部
     * dlopen 完成 —— 游戏点击即启、缺失/损坏提前暴露。
     *
     * 崩溃环护（自愈安全模式）：装载前写 started 标记，全部完成后清除。
     * 若上次运行在中途进程死亡（native 初始化崩溃无法被 try/catch 拦截），
     * 本次启动看到残留标记 → 写 lg_eager_disabled 并从此禁用预装载
     * （懒装载不受影响，游戏仍可玩），杜绝"隔次启动必崩"的环。
     *
     * Ren'Py 外板壳（librenpython.so）不在此列：其生命周期由
     * RenpyGameActivity 全权管理（route-b 架构），进程内由 Activity
     * 首次启动时装载。
     */
    fun preloadAll(context: Context) {
        val files = context.applicationContext.filesDir
        val started = File(files, "lg_eager_started")
        val disabled = File(files, "lg_eager_disabled")
        if (disabled.exists()) return
        if (started.exists()) {
            // 上次预装载中途死亡 —— 关闭预装载（懒装载仍可用）。
            started.delete()
            try { disabled.writeText("1") } catch (_: Throwable) {}
            android.util.Log.w("LusicgalEngines", "检测到上次预装载中断，本轮禁用预装载")
            return
        }
        Thread({
            try { started.writeText("1") } catch (_: Throwable) {}
            for (id in listOf(
                "kirikiri", "onscripter", "siglus", "rfvp",
                "sena", "xsystem35", "artemis"
            )) {
                try {
                    ensureNative(id)
                } catch (t: Throwable) {
                    android.util.Log.w("LusicgalEngines", "预装载 $id 失败：$t")
                }
            }
            started.delete()
            try { File(files, "lg_eager_ok").writeText("1") } catch (_: Throwable) {}
            android.util.Log.i("LusicgalEngines", "预装载完成（所有库已装载）")
        }, "LusicgalPreload").apply {
            isDaemon = true
            start()
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

    /** 会话终结（幂等）：向核心发 stop 命令 + destroy + 清 g_session。 */
    @JvmStatic
    external fun shutdown(): Int
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
