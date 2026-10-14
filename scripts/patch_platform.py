#!/usr/bin/env python3
"""flutter create 之后对平台壳打增量补丁（CI 与本地同流程）：

- iOS Runner/Info.plist：CFBundleDisplayName=LusicGal、UIFileSharingEnabled、
  LSSupportsOpeningDocumentsInPlace（"文件"App 可直接投放游戏/取走导出）。
- Android AndroidManifest.xml：application.largeHeap=true（引擎核心吃内存）。

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


if __name__ == '__main__':
    project_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    patch_ios(project_root)
    patch_android(project_root)
    patch_android_gradle(project_root)
