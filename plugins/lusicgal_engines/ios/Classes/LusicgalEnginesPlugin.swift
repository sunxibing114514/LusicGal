import Darwin
import Flutter
import UIKit

/// LusicGal 平台桥（iOS v2）：
/// - MethodChannel `lusicgal/engines`：probeEngines / launch / command /
///   pushInput / surfaceSize
/// - EventChannel  `lusicgal/engineEvents`（核心线程 → 主队列 → Dart）
/// - PlatformView  `lusicgal-engine-view`
///
/// 派发经 native/bridge/ios 的 lg_ios_*（dlsym 静态符号 + 弱 stub 兜底）。
/// 注：FlutterStreamHandler 的可选协议方法必须在类型声明处实现
/// （extension 中的 @objc 可选方法运行期不可见）。
public class LusicgalEnginesPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    /// 事件中继：C 回调闭包不能捕获上下文（@convention(c)），
    /// 经静态单例转发到活动实例。
    static weak var shared: LusicgalEnginesPlugin?

    private let engineIds = [
        "kirikiri", "onscripter", "renpy", "siglus",
        "rfvp", "sena", "xsystem35", "artemis",
    ]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "lusicgal/engines", binaryMessenger: registrar.messenger())
        let instance = LusicgalEnginesPlugin()
        LusicgalEnginesPlugin.shared = instance
        registrar.addMethodCallDelegate(instance, channel: channel)

        let events = FlutterEventChannel(
            name: "lusicgal/engineEvents", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)

        registrar.register(
            EngineViewFactory(messenger: registrar.messenger()),
            withId: "lusicgal-engine-view")

        // 事件回流：核心线程 → C 回调（无捕获）→ 主队列 → 解析 → EventChannel。
        lg_ios_set_event_callback { json in
            guard let json = json else { return }
            let text = String(cString: json)
            DispatchQueue.main.async {
                guard let shared = LusicgalEnginesPlugin.shared else { return }
                let data = Data(text.utf8)
                let decoded = try? JSONSerialization.jsonObject(with: data)
                shared.eventSink?(decoded ?? ["type": "engine", "payload": text])
            }
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "probeEngines":
            result(["engines": engineIds.map { probe($0) }])
        case "launch":
            handleLaunch(call, result: result)
        case "command":
            handleCommand(call, result: result)
        case "pushInput":
            handlePushInput(call, result: result)
        case "surfaceSize":
            handleSurfaceSize(call, result: result)
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
        let gamePath = args["gamePath"] as? String ?? ""
        let savePath = args["savePath"] as? String ?? ""
        let options = args["options"] as? [String: Any] ?? [:]
        guard let optionsJson = try? String(
            data: JSONSerialization.data(withJSONObject: options),
            encoding: .utf8) else {
            result(["ok": false, "errorCode": "BAD_ARGS", "message": "options 序列化失败"])
            return
        }
        let info = probe(engineId)
        if info["available"] as? Bool != true {
            eventSink?([
                "type": "core_missing",
                "data": ["engineId": engineId, "gameId": gameId],
            ])
            result([
                "ok": false,
                "errorCode": "CORE_NOT_BUNDLED",
                "message": (info["message"] as? String) ?? "核心未打包",
            ])
            return
        }
        let rc = lg_ios_launch(
            engineId, gameId, gamePath, savePath, optionsJson)
        result(rc == 0 ? ["ok": true, "message": nil]
                      : ["ok": false, "message": "核心返回码 \(rc)"])
    }

    private func handleCommand(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let command = call.argument<String>("command") else {
            result(FlutterMethodNotImplemented)
            return
        }
        let argsJson = (call.arguments as? [String: Any])?["args"] as? [String: Any] ?? [:]
        guard let json = try? String(
            data: JSONSerialization.data(withJSONObject: argsJson),
            encoding: .utf8) else {
            result(nil)
            return
        }
        let full = "{\"command\":\"\(command)\",\"args\":\(json)}"
        _ = lg_ios_command(full)
        // 无活动会话/核心不支持时静默（命令幂等）。
        result(nil)
    }

    private func handlePushInput(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let json = call.argument<String>("json") else {
            result(FlutterMethodNotImplemented)
            return
        }
        result(Int(lg_ios_push_input(json)))
    }

    private func handleSurfaceSize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let w = call.argument<Int>("w"), let h = call.argument<Int>("h") else {
            result(FlutterMethodNotImplemented)
            return
        }
        result(Int(lg_ios_surface_size(Int32(w), Int32(h))))
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func probe(_ engineId: String) -> [String: Any?] {
        if lg_ios_probe(engineId) == 1 {
            let abi = lg_ios_core_abi_version(engineId)
            return ["engineId": engineId, "available": true,
                    "version": String(format: "0x%08x", abi), "message": nil]
        }
        return ["engineId": engineId, "available": false, "version": nil,
                "message": "核心未链接：liblusicgal_\(engineId).a 未并入（构建见 docs/BUILD.md）"]
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

        核心未链接：该引擎的静态库尚未并入（docs/BUILD.md）。
        """
    }

    func view() -> UIView {
        label
    }
}
