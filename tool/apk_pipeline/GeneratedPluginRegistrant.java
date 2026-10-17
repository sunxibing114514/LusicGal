// 手工 APK 管线：插件注册表（平时由 flutter gradle 插件生成；
// 本管线手写 —— FlutterEngineConnectionRegistry 反射本类完成注册）。
package io.flutter.plugins;

/** 注册 LusicGal 平台插件（lusicgal/engines 通道 + 引擎事件流）。 */
public final class GeneratedPluginRegistrant {
    public static void registerWith(io.flutter.embedding.engine.FlutterEngine engine) {
        try {
            engine.getPlugins().add(new com.lusicgal.engines.LusicgalEnginesPlugin());
        } catch (Throwable t) {
            // 插件失败不阻断引擎启动（探测走 core_missing 语义）。
            System.getLogger("LusicGal").log(System.Logger.Level.WARNING,
                    "plugin register failed", t);
        }
    }

    private GeneratedPluginRegistrant() {}
}
