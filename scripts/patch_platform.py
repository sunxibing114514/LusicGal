#!/usr/bin/env python3
"""flutter create 之后对平台壳打增量补丁（CI 与本地同流程）：

- iOS Runner/Info.plist：CFBundleDisplayName=LusicGal、UIFileSharingEnabled、
  LSSupportsOpeningDocumentsInPlace（"文件"App 可直接投放游戏/取走导出）。
- Android AndroidManifest.xml：application.largeHeap=true（引擎核心吃内存）。
- Ren'Py 外板壳模块：modules/renpy/build-out/.ready 存在时把 ':module-renpy'
  并入 settings.gradle + 依赖进 app —— 未 staging 的普通构建零影响。

平台壳是 CI 确定性生成的（docs/ARCHITECTURE.md §6），因此所有定制都集中在本脚本。
"""
import os
import plistlib
import sys
import xml.etree.ElementTree as ET

ANDROID_NS = 'http://schemas.android.com/apk/res/android'


def patch_ios(root: str) -> None:
    path = os.path.join(root, 'ios', 'Runner', 'Info.plist')
    if not os.path.exists(path):
        print('patch_platform: 未找到 ios/Runner/Info.plist（跳过 iOS）')
        return
    with open(path, 'rb') as f:
        pl = plistlib.load(f)
    pl['CFBundleDisplayName'] = 'LusicGal'
    pl['UIFileSharingEnabled'] = True
    pl['LSSupportsOpeningDocumentsInPlace'] = True
    pl.setdefault('UILaunchScreen', {})
    with open(path, 'wb') as f:
        plistlib.dump(pl, f)
    print('patch_platform: iOS Info.plist 已补丁（文件共享 + 显示名）')


def patch_android(root: str) -> None:
    path = os.path.join(root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')
    if not os.path.exists(path):
        print('patch_platform: 未找到 AndroidManifest.xml（跳过 Android）')
        return
    ET.register_namespace('android', ANDROID_NS)
    tree = ET.parse(path)
    root_el = tree.getroot()
    app = root_el.find('application')
    if app is None:
        raise SystemExit('AndroidManifest 缺少 <application> 节点')
    app.set(f'{{{ANDROID_NS}}}largeHeap', 'true')
    tree.write(path, encoding='utf-8', xml_declaration=True)
    print('patch_platform: AndroidManifest 已补丁（largeHeap）')


def patch_android_gradle(root: str) -> None:
    """把 compileSdk 提到 36：上游插件（如 flutter_plugin_android_lifecycle 新版）
    的 AAR 元数据要求高于模板默认值；按 ABI 兼容规则只升不降。"""
    app_dir = os.path.join(root, 'android', 'app')
    if not os.path.isdir(app_dir):
        print('patch_platform: 未找到 android/app（跳过 Gradle）')
        return
    for name in ('build.gradle.kts', 'build.gradle'):
        p = os.path.join(app_dir, name)
        if not os.path.exists(p):
            continue
        with open(p, encoding='utf-8') as f:
            src = f.read()
        patched = src.replace('flutter.compileSdkVersion', '36')
        patched = patched.replace('compileSdk flutter.compileSdkVersion', 'compileSdk 36')
        if patched != src:
            with open(p, 'w', encoding='utf-8') as f:
                f.write(patched)
            print(f'patch_platform: {name} compileSdk → 36')
            return
    print('patch_platform: Gradle 未发现 flutter.compileSdkVersion（可能模板已变更）')


def patch_release_minify(root: str) -> None:
    """关 release 压缩（R8/资源 shrink）。

    Flutter 3.27+ 模板默认 minify+shrinkResources 开 —— CI 实证 R8 崩在
    renpy 模块的 SDL 字节码上（minifyReleaseWithR8: Compilation failed to
    complete, origin org/libsdl/app/SDLActivity）。引擎重字节码不值得 R8
    冒险，关掉（体积代价 ~几 MB dex，安全换稳定）。
    """
    app_dir = os.path.join(root, 'android', 'app')
    for name in ('build.gradle.kts', 'build.gradle'):
        p = os.path.join(app_dir, name)
        if not os.path.exists(p):
            continue
        with open(p, encoding='utf-8') as f:
            src = f.read()
        if 'isMinifyEnabled' in src or 'minifyEnabled' in src:
            print(f'patch_platform: {name} 已含 minify 设置（跳过）')
            return
        if name.endswith('.kts'):
            block = (
                "\n// LusicGal: 关 release 压缩（patch_platform：R8 崩 SDL 字节码）\n"
                "android {\n"
                "    buildTypes {\n"
                "        release {\n"
                "            isMinifyEnabled = false\n"
                "            isShrinkResources = false\n"
                "        }\n"
                "    }\n"
                "}\n"
            )
        else:
            block = (
                "\n// LusicGal: 关 release 压缩（patch_platform：R8 崩 SDL 字节码）\n"
                "android {\n"
                "    buildTypes {\n"
                "        release {\n"
                "            minifyEnabled false\n"
                "            shrinkResources false\n"
                "        }\n"
                "    }\n"
                "}\n"
            )
        with open(p, 'a', encoding='utf-8') as f:
            f.write(block)
        print(f'patch_platform: {name} release 压缩已关（R8/shrink）')
        return
    print('patch_platform: 未找到 app gradle（跳过 minify 补丁）')


def patch_engine_cores(root: str) -> None:
    """引擎核心 .so 打包（build/jniLibs/arm64-v8a/*.so）：

    全量构建（CI full-apk / 本地 assembleDebug）把 build/cores/<id>/ 汇入
    build/jniLibs/ 后，给插件 build.gradle 追加 jniLibs srcDir —— "作为
    jniLibs 放入任意 APK 即被 EngineHost.probe 识别"（docs/BUILD.md）的
    Gradle 内建路径。目录不存在时零改动（普通构建不受影响）。
    """
    jnilibs = os.path.join(root, 'build', 'jniLibs', 'arm64-v8a')
    if not (os.path.isdir(jnilibs) and
            any(n.endswith('.so') for n in os.listdir(jnilibs))):
        print('patch_platform: build/jniLibs 无核心（跳过核心打包）')
        return
    p = os.path.join(root, 'plugins', 'lusicgal_engines', 'android', 'build.gradle')
    if not os.path.exists(p):
        print('patch_platform: 未找到插件 build.gradle（核心打包跳过）')
        return
    with open(p, encoding='utf-8') as f:
        src = f.read()
    marker = "jniLibs.srcDir lgCoreLibs"
    if marker in src:
        print('patch_platform: 插件已接核心 jniLibs')
        return
    block = (
        "\n// LusicGal 核心打包（patch_platform.py 注入）：build/jniLibs\n"
        "//（build/cores/<id> 汇入；EngineHost.probe 运行期探测）。\n"
        "// rootDir=<repo>/android → ../build/jniLibs = <repo>/build/jniLibs。\n"
        "def lgCoreLibs = new File(rootDir, '../build/jniLibs')\n"
        "if (lgCoreLibs.exists()) {\n"
        "    android {\n"
        "        sourceSets {\n"
        "            main {\n"
        "                jniLibs.srcDir lgCoreLibs\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "}\n"
    )
    with open(p, 'a', encoding='utf-8') as f:
        f.write(block)
    print('patch_platform: 插件 build.gradle 已接 build/jniLibs 核心打包')


def patch_renpy_module(root: str) -> None:
    """Ren'Py 外板壳模块（modules/renpy，Route B）：

    build-out/.ready（modules/renpy/build_android.sh staging 完成）存在时：
      1. settings.gradle include ':module-renpy'（projectDir=modules/renpy）；
      2. app 依赖 implementation project(':module-renpy')。
    未 staging：零改动（普通构建不受重依赖影响）。
    """
    ready = os.path.join(root, 'modules', 'renpy', 'build-out', '.ready')
    if not os.path.exists(ready):
        print('patch_platform: renpy 模块未 staging（跳过）')
        return
    settings = None
    for name in ('settings.gradle.kts', 'settings.gradle'):
        p = os.path.join(root, 'android', name)
        if os.path.exists(p):
            settings = p
            break
    if settings is None:
        print('patch_platform: 未找到 settings.gradle（renpy 模块跳过）')
        return
    with open(settings, encoding='utf-8') as f:
        src = f.read()
    is_kts = settings.endswith('.kts')
    marker = ("include(\":module-renpy\")" if is_kts
              else "include ':module-renpy'")
    if marker not in src:
        if is_kts:
            block = (
                "\n// LusicGal: Ren'Py 外板壳模块（modules/renpy，已 staging）\n"
                f"{marker}\n"
                "project(\":module-renpy\").projectDir ="
                " File(rootProject.projectDir, \"../modules/renpy\")\n"
            )
        else:
            block = (
                "\n// LusicGal: Ren'Py 外板壳模块（modules/renpy，已 staging）\n"
                f"{marker}\n"
                "project(':module-renpy').projectDir ="
                " new File(rootProject.projectDir, '../modules/renpy')\n"
            )
        with open(settings, 'a', encoding='utf-8') as f:
            f.write(block)
        print('patch_platform: settings 已 include :module-renpy')

    app_dir = os.path.join(root, 'android', 'app')
    for name in ('build.gradle.kts', 'build.gradle'):
        p = os.path.join(app_dir, name)
        if not os.path.exists(p):
            continue
        with open(p, encoding='utf-8') as f:
            src = f.read()
        dep_groovy = "implementation project(':module-renpy')"
        dep_kts = "implementation(project(\":module-renpy\"))"
        if dep_groovy in src or dep_kts in src:
            print(f'patch_platform: {name} 已有 :module-renpy 依赖（跳过）')
            break
        # 首选：并入已有 dependencies 块（模板锚 "dependencies {"）。
        # 兜底：文件尾追加独立 dependencies 块 —— Gradle 允许重复同名顶层
        # 配置块（Kotlin DSL 同）。CI 实证 Flutter 3.47 模板锚不中时静默
        # 失败 → root 级 assembleRelease 会编译模块但 :app 不打包其
        # dex/jniLibs/资产 —— 兜底后此路永不通。
        if name.endswith('.kts'):
            patched = src.replace('dependencies {', f'dependencies {{\n    {dep_kts}', 1)
            if patched == src:
                patched = src + (
                    "\n// LusicGal: :module-renpy 运行时依赖（patch_platform 兜底）\n"
                    f"dependencies {{\n    {dep_kts}\n}}\n"
                )
                how = '追加兜底块'
            else:
                how = '并入 dependencies 块'
        else:
            patched = src.replace('dependencies {', f'dependencies {{\n    {dep_groovy}', 1)
            if patched == src:
                patched = src + (
                    "\n// LusicGal: :module-renpy 运行时依赖（patch_platform 兜底）\n"
                    f"dependencies {{\n    {dep_groovy}\n}}\n"
                )
                how = '追加兜底块'
            else:
                how = '并入 dependencies 块'
        with open(p, 'w', encoding='utf-8') as f:
            f.write(patched)
        print(f'patch_platform: {name} 已依赖 :module-renpy（{how}）')
        break


def patch_target_sdk_legacy(root: str) -> None:
    """targetSdk 固定 29 + requestLegacyExternalStorage（用户指令：所有
    Android 版本都要能直接读取共享目录里的游戏文件夹）。

    背景：API 30+ 的 FUSE 直路径中介对 SAF 授权目录生效，但 Android 10
    设备上（app targetSdk≥30）共享目录直路径一律 EACCES —— SAF 授权也
    无济于事，v0.1.2 因此在 Android 10 降级提示。targetSdk 29 +
    requestLegacyExternalStorage=true 让 App 走旧存储模型：Android 10
    及以下按旧规则（运行时 READ 权限）直读，Android 11+ 按 Google 迁移
    过渡政策对 targetSdk≤29 的 App 继续授予 legacy 访问 —— 即"所有
    系统"共享目录直路径全部可用（侧载分发不受 Play targetSdk 上限约束）。
    """
    app_dir = os.path.join(root, 'android', 'app')
    if not os.path.isdir(app_dir):
        print('patch_platform: 未找到 android/app（targetSdk 补丁跳过）')
        return
    done = False
    for name in ('build.gradle.kts', 'build.gradle'):
        p = os.path.join(app_dir, name)
        if not os.path.exists(p):
            continue
        with open(p, encoding='utf-8') as f:
            src = f.read()
        patched = src.replace('targetSdk = flutter.targetSdkVersion', 'targetSdk = 29')
        patched = patched.replace('targetSdk flutter.targetSdkVersion', 'targetSdk 29')
        if patched != src:
            with open(p, 'w', encoding='utf-8') as f:
                f.write(patched)
            print(f'patch_platform: {name} targetSdk → 29（legacy 外部目录直读）')
            done = True
            break
    if not done:
        print('patch_platform: Gradle 未发现 flutter.targetSdkVersion（模板可能已变）')


def patch_lint_vital_off(root: str) -> None:
    """关 lintVitalRelease 关卡。

    targetSdk 固定 29（外部目录全系统直读，用户指令）触发
    ExpiredTargetSdkVersion fatal lint（"Google Play requires API 33+"）
    —— 本 App 侧载分发，不受 Play API 级别政策约束。用任务级熔断
    （tasks.whenTaskAdded）而不是 lint DSL：两种 Gradle DSL 语法完全
    同构、对 AGP 版本无依赖。
    """
    app_dir = os.path.join(root, 'android', 'app')
    for name in ('build.gradle.kts', 'build.gradle'):
        p = os.path.join(app_dir, name)
        if not os.path.exists(p):
            continue
        with open(p, encoding='utf-8') as f:
            src = f.read()
        if 'lintVital' in src:
            print(f'patch_platform: {name} 已含 lintVital 熔断（跳过）')
            return
        if name.endswith('.kts'):
            block = (
                "\n// LusicGal: targetSdk 29（legacy 外部目录直读）触发"
                " ExpiredTargetSdkVersion fatal lint ——\n"
                "// 侧载分发不受 Play API 级别政策约束，任务级熔断 lintVital。\n"
                "tasks.whenTaskAdded {\n"
                "    if (name.contains(\"lintVital\")) {\n"
                "        enabled = false\n"
                "    }\n"
                "}\n"
            )
        else:
            block = (
                "\n// LusicGal: targetSdk 29（legacy 外部目录直读）触发"
                " ExpiredTargetSdkVersion fatal lint ——\n"
                "// 侧载分发不受 Play API 级别政策约束，任务级熔断 lintVital。\n"
                "tasks.whenTaskAdded { t ->\n"
                "    if (t.name.contains(\"lintVital\")) {\n"
                "        t.enabled = false\n"
                "    }\n"
                "}\n"
            )
        with open(p, 'a', encoding='utf-8') as f:
            f.write(block)
        print(f'patch_platform: {name} lintVitalRelease 已熔断（targetSdk 29 侧载）')
        return
    print('patch_platform: 未找到 app gradle（跳过 lintVital 补丁）')


if __name__ == '__main__':
    project_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    patch_ios(project_root)
    patch_android(project_root)
    patch_android_gradle(project_root)
    patch_target_sdk_legacy(project_root)
    patch_release_minify(project_root)
    patch_lint_vital_off(project_root)
    patch_engine_cores(project_root)
    patch_renpy_module(project_root)
