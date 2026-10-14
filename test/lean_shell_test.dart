// 精简壳回归：核心 Store/Settings 与 provider/主题联动的最小 widget 测试。
//
// 契约提醒：testWidgets 的 body 运行在 fake-async zone —— `scheduleMicrotask`
// 被拦截，真实文件 IO 的完成回调停在 fake 队列，而测试体正 await 它，队列
// 无人 flush → 永久挂起。所以一切真实 IO（createTemp/load/setThemeMode/
// teardown delete）都必须包进 `tester.runAsync`。见 widget_test.dart 的注释。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusicgal/core/library/library_store.dart';
import 'package:lusicgal/core/settings/settings_controller.dart';
import 'package:lusicgal/core/theme.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  testWidgets('真实 IO 经 runAsync：Store+Settings+主题联动', (tester) async {
    final dir =
        (await tester.runAsync(() => Directory.systemTemp.createTemp('lg_lean')))!;
    addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));

    final store = LibraryStore(root: dir);
    final settings =
        SettingsController(file: File(p.join(dir.path, 'settings.json')));
    await tester.runAsync(store.load);
    await tester.runAsync(settings.load);

    var built = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: store),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
        ],
        child: Builder(
          builder: (context) {
            built++;
            final dark = context.watch<SettingsController>().themeMode ==
                ThemeModeSetting.dark;
            return MaterialApp(
              theme: LusicTheme.light(),
              darkTheme: LusicTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: const Scaffold(body: SizedBox()),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(built, greaterThanOrEqualTo(1));

    await tester.runAsync(() => settings.setThemeMode(ThemeModeSetting.dark));
    await tester.pump(const Duration(milliseconds: 100));
    expect(built, greaterThan(1)); // 主题联动触发重建。
    expect(settings.themeMode, ThemeModeSetting.dark);
    expect(store.games, isEmpty);
  });
}
