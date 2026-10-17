// LusicGal 构建管线引导内核（pipeline bootstrap kernel）。
//
// 用途：本容器 cgroup 余量（~520MB）装不下 flutter 框架冷编
//（frontend_server 9 次 kernel OOM 实证，见 docs/BUILD.md「内核边界」），
// 故以纯 dart:ui 极小闭包编译出 kernel_blob.bin 驱动 APK 全管线
//（gradle+AGP+cmake+签名）——产物可安装、可启动、显示本提示页。
//
// 真内核恢复：任何 ≥1GB 空闲内存的机器上
//   flutter assemble ... -dTargetFile=lib/main.dart debug_android_application
// 把产物 flutter_assets/kernel_blob.bin 替换进 APK assets 再重签即可
//（单文件热换，不需重新构建；见 docs/BUILD.md）。
import 'dart:ui';

const _notice = [
  'LusicGal 运行器壳已装配',
  '',
  '此 APK 携带「引导内核」：',
  '构建管线（Gradle/AGP/CMake 桥/签名）全部实证，',
  'Web 引擎与核心宿主 Kotlin 代码均已打包。',
  '',
  '应用内核（kernel_blob.bin）在本容器编译为资源边界',
  '（frontend_server 冷编 flutter 框架需 >520MB 空闲），',
  '由 CI 或任一 ≥1GB 空闲内存的机器产出后',
  '单文件热换 assets/flutter_assets/kernel_blob.bin 并重签。',
  '',
  '详见仓库 docs/BUILD.md「内核边界与热换」。',
];

void main() {
  PlatformDispatcher.instance.onBeginFrame = (_) {
    final d = PlatformDispatcher.instance.views.first;
    final size = d.physicalSize / d.devicePixelRatio;
    final rec = PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF101418));
    final tp = ParagraphBuilder(
      ParagraphStyle(textAlign: TextAlign.left, fontSize: 16),
    )
      ..pushStyle(TextStyle(color: const Color(0xFFE6EDF3), fontSize: 16))
      ..addText(_notice.join('\n'));
    final para = tp.build()..layout(ParagraphConstraints(width: size.width - 48));
    canvas.drawParagraph(para, const Offset(24, 32));
    final sb = SceneBuilder();
    sb.addPicture(Offset.zero, rec.endRecording());
    d.render(sb.build());
  };
  PlatformDispatcher.instance.scheduleFrame();
}
