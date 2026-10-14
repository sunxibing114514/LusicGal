import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusicgal/app.dart';
import 'package:lusicgal/core/library/import_service.dart';
import 'package:lusicgal/core/library/library_store.dart';
import 'package:lusicgal/core/saves/save_manager.dart';
import 'package:lusicgal/core/settings/settings_controller.dart';
import 'package:lusicgal/engine/engine_host.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// 冒烟测试：完整壳（M3 明暗主题、四页导航、空书库态）在测试环境可渲染。
///
/// 平台通道必须 mock：未 mock 时消息发给真实 messenger，回复 Future 永不
/// 完成（没有引擎进程），引擎页的 FutureBuilder 将停在加载态 →
/// CircularProgressIndicator 无限动画 → pumpAndSettle 永不 settle。
/// mock 返回 null → invokeMethod 抛 MissingPluginException →
/// EngineHost 吞掉并返回空表，这正是"核心未打包"的真实路径。
void main() {
  testWidgets('书库空状态 + 四页导航 + 明暗主题切换', (tester) async {
    const channel = MethodChannel('lusicgal/engines');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    final dir = await Directory.systemTemp.createTemp('lg_app');
    addTearDown(() => dir.delete(recursive: true));

    final store = LibraryStore(root: dir);
    await store.load();
    final settings = SettingsController(file: File(p.join(dir.path, 'settings.json')));
    await settings.load();

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

    // 有界 pump（不依赖 settle）+ 显式超时：任何回归最多 2 分钟内失败，
    // 绝不让 CI 挂 10 分钟。
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
    await settings.setThemeMode(ThemeModeSetting.dark);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('书库还是空的'), findsOneWidget);

    // 切换浅色主题。
    await settings.setThemeMode(ThemeModeSetting.light);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('书库还是空的'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
