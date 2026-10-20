import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusicgal/app.dart';
import 'package:lusicgal/core/library/import_service.dart';
import 'package:lusicgal/core/library/library_store.dart';
import 'package:lusicgal/core/saves/save_manager.dart';
import 'package:lusicgal/core/settings/settings_controller.dart';
import 'package:lusicgal/engine/engine_host.dart';
import 'package:lusicgal/ui/library/library_screen.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// 冒烟测试：完整壳（M3 明暗主题、四页导航、空书库态）在测试环境可渲染。
///
/// ## 两条 flutter_test 契约（违反即死锁）：
///
/// 1. **真实 IO 必须 `tester.runAsync` 包裹**。testWidgets 的 body 运行在
///    fake-async zone：`scheduleMicrotask` 被拦截进 fake 队列，真实文件 IO
///    的完成回调进的是这个队列；而测试体正 await 该 Future —— 队列无人
///    flush → 永久挂起（表现为 `_RawReceivePort._handleMessage` 堆栈 +
///    超时）。26 个纯 Dart 测试（无 fake zone）不受影响。
/// 2. **平台通道必须 mock**（或确保调用方吞掉 MissingPluginException）。
///    未 mock 时消息发给真实 messenger，回复 Future 永不完成。mock 返回
///    null → invokeMethod 抛 MissingPluginException → EngineHost 吞掉并
///    返回空表，这正是"核心未打包"的真实路径。
///
/// 泵送使用有界 pump（不依赖 settle）+ 显式超时：任何回归最多 2 分钟内
/// 失败，绝不让 CI 挂 10 分钟。
void main() {
  testWidgets('书库空状态 + 四页导航 + 明暗主题切换', (tester) async {
    const channel = MethodChannel('lusicgal/engines');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final dir =
        (await tester.runAsync(() => Directory.systemTemp.createTemp('lg_app')))!;
    addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));

    final store = LibraryStore(root: dir);
    await tester.runAsync(store.load);
    final settings =
        SettingsController(file: File(p.join(dir.path, 'settings.json')));
    await tester.runAsync(settings.load);

    Future<void> pump() => tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<LibraryStore>.value(value: store),
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              Provider<ImportService>.value(
                value: ImportService(store: store, importRoots: [dir]),
              ),
              Provider<SaveManager>.value(value: SaveManager(root: dir)),
              Provider<EngineHost>.value(value: EngineHost()),
            ],
            child: const LusicGalApp(),
          ),
        );

    await pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // 空书库引导。
    expect(find.text('书库还是空的'), findsOneWidget);
    // 底部导航（IndexedStack 会构建全部四页，AppBar 标题同名也计入）。
    expect(find.text('存档'), findsWidgets);
    expect(find.text('引擎'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    // 切换深色主题：MaterialApp 重建且不崩溃（设置 → 主题联动）。
    await tester
        .runAsync(() => settings.setThemeMode(ThemeModeSetting.dark));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('书库还是空的'), findsOneWidget);

    // 切换浅色主题。
    await tester
        .runAsync(() => settings.setThemeMode(ThemeModeSetting.light));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('书库还是空的'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('导入面板：选择游戏文件夹主按钮接线', (tester) async {
    final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lg_sheet')))!;
    addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));

    final store = LibraryStore(root: dir);
    await tester.runAsync(store.load);
    final settings =
        SettingsController(file: File(p.join(dir.path, 'settings.json')));
    await tester.runAsync(settings.load);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: store),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          Provider<ImportService>.value(
            value: ImportService(store: store, importRoots: [dir]),
          ),
          Provider<SaveManager>.value(value: SaveManager(root: dir)),
          Provider<EngineHost>.value(value: EngineHost()),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // 打开导入面板。
    await tester.tap(find.byTooltip('导入游戏'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // 即选即用主按钮 + 降级说明 + 扫描通道标题都在。
    expect(find.text('选择游戏文件夹（不复制，即选即玩）'), findsOneWidget);
    expect(find.text('或从 App 专属目录扫描'), findsOneWidget);
    expect(find.text('重新扫描'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
