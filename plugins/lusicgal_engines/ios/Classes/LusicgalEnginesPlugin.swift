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
        // ABI v2 原生核心。
        "kirikiri", "onscripter", "renpy", "siglus",
        "rfvp", "sena", "xsystem35", "artemis",
        // Web 引擎（WKWebView 跑法；iOS 用 loadFileURL 免本地服务器）。
        "tyrano", "rpgmv", "rpgmz",
        // 外板启动平台条目（Android 专属形态；iOS 报不可用）。
        "psp", "pcwinlator", "androidapp",
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

        // ---- Web 引擎：WKWebView 全屏跑法（与 Android WebGameActivity 同语义）。
        if engineId == "tyrano" || engineId == "rpgmv" || engineId == "rpgmz" {
            guard !gamePath.isEmpty else {
                result(["ok": false, "errorCode": "BAD_ARGS", "message": "游戏目录为空"])
                return
            }
            DispatchQueue.main.async {
                WebGameViewController.present(
                    gameDir: gamePath, kind: engineId, saveDir: savePath)
            }
            result(["ok": true, "message": nil])
            return
        }
        // ---- 外板启动条目：Android 专属（PPSSPP/Winlator 无 iOS 版）。
        if engineId == "psp" || engineId == "pcwinlator" || engineId == "androidapp" {
            result(["ok": false,
                    "errorCode": engineId == "psp" ? "PPSSPP_NOT_INSTALLED"
                          : engineId == "pcwinlator" ? "PACKAGE_NOT_INSTALLED"
                          : "APP_NOT_INSTALLED",
                    "message": "该条目形态依赖 Android 外部应用，iOS 不可用"])
            return
        }

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
        // Web 引擎：WKWebView 内置即用（loadFileURL + 脚本注入）。
        if engineId == "tyrano" || engineId == "rpgmv" || engineId == "rpgmz" {
            return ["engineId": engineId, "available": true,
                    "version": "webview", "message": nil]
        }
        // 外板条目：依赖 Android 外部应用，iOS 恒不可用。
        if engineId == "psp" || engineId == "pcwinlator" || engineId == "androidapp" {
            return ["engineId": engineId, "available": false, "version": nil,
                    "message": "该条目形态依赖 Android 外部应用（PPSSPP/Winlator/应用启动），iOS 不可用"]
        }
        if lg_ios_probe(engineId) == 1 {
            let abi = lg_ios_core_abi_version(engineId)
            return ["engineId": engineId, "available": true,
                    "version": String(format: "0x%08x", abi), "message": nil]
        }
        return ["engineId": engineId, "available": false, "version": nil,
                "message": "核心未链接：liblusicgal_\(engineId).a 未并入（构建见 docs/BUILD.md）"]
    }
}

/// Web 引擎运行页（Tyrano / RPG MV / MZ；iOS 形态）。
///
/// 与 Android WebGameActivity 同语义，实现更简：WKWebView 原生支持
/// loadFileURL(allowingReadAccessTo:) 直接加载本地 index.html —— 无需
/// 本地 HTTP 服务；启动 hook（lg_web_boot.js，与 Android 共用资产）经
/// WKUserScript 注入（documentStart，先于引擎脚本）。
/// 注：TyranoBuilder 的 app.asar 解析为 Android 形态专属（iOS 侧
/// 暂不支持，见 docs/ENGINE_NOTES.md 平台条目节）。
class WebGameViewController: UIViewController, WKNavigationDelegate {
    private let gameDir: String
    private let kind: String
    private var webView: WKWebView?

    private init(gameDir: String, kind: String) {
        self.gameDir = gameDir
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    static func present(gameDir: String, kind: String, saveDir: String) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else { return }
        let vc = WebGameViewController(gameDir: gameDir, kind: kind)
        vc.modalPresentationStyle = .fullScreen
        root.present(vc, animated: true)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        // 启动 hook：与 Android 共用的插件资产 lg_web_boot.js
        //（经 podspec resource_bundles 打进 lusicgal_engines.bundle）。
        let hookBundle = Bundle(for: WebGameViewController.self)
            .url(forResource: "lusicgal_engines", withExtension: "bundle")
            .flatMap(Bundle.init(url:))
        if let hookURL = hookBundle?.url(
            forResource: "lg_web_boot", withExtension: "js"),
           let hook = try? String(contentsOf: hookURL, encoding: .utf8) {
            config.userContentController.addUserScript(
                WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let wv = WKWebView(frame: view.bounds, configuration: config)
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.navigationDelegate = self
        view.addSubview(wv)
        webView = wv

        let index = URL(fileURLWithPath: gameDir).appendingPathComponent("index.html")
        wv.loadFileURL(index, allowingReadAccessTo: URL(fileURLWithPath: gameDir))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            // 释放（暂停音频）由 lg_web_boot 的 __lgAudioPause 兜底：
            // WKWebView 销毁即停。
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // 外部 http(s) 转系统浏览器；本地文件放行。
        if let url = navigationAction.request.url,
           url.isFileURL == false,
           url.scheme == "http" || url.scheme == "https" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
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
