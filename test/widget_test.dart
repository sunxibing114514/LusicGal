import 'dart:io';

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
/// 平台桥通道缺失（MissingPluginException）必须被吞掉而不是崩溃。
void main() {
  testWidgets('书库空状态 + 四页导航 + 明暗主题切换', (tester) async {
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

    await pump();
    await tester.pumpAndSettle();

    // 空书库引导。
    expect(find.text('书库还是空的'), findsOneWidget);
    // 底部导航（IndexedStack 会构建全部四页，AppBar 标题同名也计入）。
    expect(find.text('存档'), findsWidgets);
    expect(find.text('引擎'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    // 切换深色主题：MaterialApp 重建且不崩溃（设置 → 主题联动）。
    await settings.setThemeMode(ThemeModeSetting.dark);
    await tester.pumpAndSettle();
    expect(find.text('书库还是空的'), findsOneWidget);

    // 切换浅色主题。
    await settings.setThemeMode(ThemeModeSetting.light);
    await tester.pumpAndSettle();
    expect(find.text('书库还是空的'), findsOneWidget);
  });
}
