package com.lusicgal.engines

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.TextView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject

/**
 * LusicGal 平台桥：
 * - MethodChannel `lusicgal/engines`：probeEngines / launch / command
 * - EventChannel  `lusicgal/engineEvents`：log / state / exit / core_missing
 * - PlatformView  `lusicgal-engine-view`：引擎渲染面（核心未打包时为原生占位）
 */
class LusicgalEnginesPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probeEngines" -> result.success(mapOf("engines" to EngineHost.probeAll()))
            "launch" -> handleLaunch(call, result)
            "command" -> handleCommand(call, result)
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
        // 核心已加载：把启动参数序列化为 JSON 转交核心 JNI 入口
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

    private fun postEvent(event: Map<String, Any?>) {
        eventSink?.success(event)
    }

    companion object {
        const val METHOD_CHANNEL = "lusicgal/engines"
        const val EVENT_CHANNEL = "lusicgal/engineEvents"
        const val VIEW_TYPE = "lusicgal-engine-view"

        /** 当前活动会话的引擎 id（由 launch 设置，v1 仅为命令路由占位）。 */
        @Volatile
        var engineIdHolder: String? = null
    }
}

/**
 * 核心探测/装载：核心以可选模块（liblusicgal_<engine>.so）发布，
 * 缺失任意核心不影响 App —— 这是"引擎可选化"许可与体积策略的基础。
 */
object EngineHost {
    val engineIds = listOf(
        "kirikiri", "onscripter", "renpy", "siglus",
        "rfvp", "sena", "xsystem35", "artemis"
    )

    fun probeAll(): List<Map<String, Any?>> = engineIds.map { probe(it) }

    fun probe(engineId: String): Map<String, Any?> {
        val lib = "lusicgal_$engineId"
        return try {
            System.loadLibrary(lib)
            LusicgalEnginesPlugin.engineIdHolder = engineId
            mapOf(
                "engineId" to engineId,
                "available" to true,
                "version" to null,
                "message" to null
            )
        } catch (e: UnsatisfiedLinkError) {
            mapOf(
                "engineId" to engineId,
                "available" to false,
                "version" to null,
                "message" to "核心未打包：lib$lib.so 缺失（构建见 docs/BUILD.md 与 .github/workflows/engines.yml）"
            )
        }
    }
}

/** 核心 JNI 入口声明（由 native/bridge/jni 提供实现；核心未打包时调用抛 UnsatisfiedLinkError）。 */
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
}

/** 占位渲染面工厂（核心接入后由各核心的真实 Surface 视图替换）。 */
class EngineViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        return EnginePlaceholderView(
            context,
            params?.get("engineId") as? String ?: "unknown",
            params?.get("gameId") as? String ?: ""
        )
    }
}

/** 核心未打包时的原生占位视图：与未来引擎 Surface 使用同一 PlatformView 通道。 */
internal class EnginePlaceholderView(
    context: Context,
    private val engineId: String,
    private val gameId: String
) : PlatformView {
    private val textView = TextView(context).apply {
        setBackgroundColor(Color.rgb(14, 11, 30))
        setTextColor(Color.rgb(185, 168, 255))
        text = "LusicGal 引擎占位渲染面\n\nengine = $engineId\ngame = $gameId\n\n" +
            "核心接入后，此处将由引擎 Surface 渲染游戏画面。"
        gravity = Gravity.CENTER
        setPadding(48, 48, 48, 48)
    }

    override fun getView(): View = textView

    override fun dispose() {}
}
