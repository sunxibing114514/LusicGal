import Darwin
import Flutter
import UIKit

/// LusicGal 平台桥（iOS）：
/// - MethodChannel `lusicgal/engines`：probeEngines / launch / command
/// - EventChannel  `lusicgal/engineEvents`
/// - PlatformView  `lusicgal-engine-view`
///
/// 核心探测用 dlsym 检查静态链接符号 `lg_<engine>_engine_create`（engine_abi.h）。
/// 注：FlutterStreamHandler 的可选协议方法必须在类型声明处实现
/// （extension 中的 @objc 可选方法运行期不可见）。
public class LusicgalEnginesPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    /// RTLD_DEFAULT：dlsym 在全局符号表检索。
    private static let rtldDefault: UnsafeMutableRawPointer? =
        UnsafeMutableRawPointer(bitPattern: -2)

    private var eventSink: FlutterEventSink?

    private let engineIds = [
        "kirikiri", "onscripter", "renpy", "siglus",
        "rfvp", "sena", "xsystem35", "artemis",
    ]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "lusicgal/engines", binaryMessenger: registrar.messenger())
        let instance = LusicgalEnginesPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        let events = FlutterEventChannel(
            name: "lusicgal/engineEvents", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)

        registrar.register(
            EngineViewFactory(messenger: registrar.messenger()),
            withId: "lusicgal-engine-view")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "probeEngines":
            result(["engines": engineIds.map { probe($0) }])
        case "launch":
            handleLaunch(call, result: result)
        case "command":
            // 无活动核心会话时静默成功（命令幂等）。
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleLaunch(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let engineId = args["engineId"] as? String else {
            result(["ok": false, "errorCode": "BAD_ARGS", "message": "缺少 engineId"])
            return
        }
        let gameId = args["gameId"] as? String ?? ""
        let info = probe(engineId)
        if info["available"] as? Bool == true {
            // 核心已链接：调用 ABI 入口（v1 尚无核心，此分支为接入预留）。
            result(["ok": false, "errorCode": "CORE_ENTRY_NOT_IMPLEMENTED",
                    "message": "核心入口尚未接线（见 native/bridge 与 docs/ROADMAP.md）"])
            return
        }
        eventSink?([
            "type": "core_missing",
            "data": ["engineId": engineId, "gameId": gameId],
        ])
        result([
            "ok": false,
            "errorCode": "CORE_NOT_BUNDLED",
            "message": (info["message"] as? String) ?? "核心未打包",
        ])
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) {
        eventSink = events
    }

    public func onCancel(withArguments arguments: Any?) {
        eventSink = nil
    }

    private func probe(_ engineId: String) -> [String: Any?] {
        let symbol = "lg_\(engineId)_engine_create"
        if dlsym(LusicgalEnginesPlugin.rtldDefault, symbol) != nil {
            return ["engineId": engineId, "available": true,
                    "version": nil, "message": nil]
        }
        return ["engineId": engineId, "available": false, "version": nil,
                "message": "核心未打包：静态符号 \(symbol) 未链接（构建见 docs/BUILD.md 与 .github/workflows/engines.yml）"]
    }
}

/// 占位渲染面工厂（核心接入后替换为真实引擎视图）。
class EngineViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let params = args as? [String: Any]
        return EnginePlaceholderView(
            frame: frame,
            engineId: params?["engineId"] as? String ?? "unknown",
            gameId: params?["gameId"] as? String ?? "")
    }

    func createArgsCodec() -> FlutterMessageCodec {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// 核心未打包时的原生占位视图：与未来引擎视图使用同一 PlatformView 通道。
class EnginePlaceholderView: NSObject, FlutterPlatformView {
    private let label = UILabel()

    init(frame: CGRect, engineId: String, gameId: String) {
        super.init()
        label.frame = frame
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.backgroundColor = UIColor(red: 14 / 255, green: 11 / 255, blue: 30 / 255, alpha: 1)
        label.textColor = UIColor(red: 185 / 255, green: 168 / 255, blue: 1, alpha: 1)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = """
        LusicGal 引擎占位渲染面

        engine = \(engineId)
        game = \(gameId)

        核心接入后，此处将由引擎视图渲染游戏画面。
        """
    }

    func view() -> UIView {
        label
    }
}
