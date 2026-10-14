import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusicgal/core/settings/settings_controller.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lg_settings');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('默认值', () async {
    final c = SettingsController(file: File('${tmp.path}/settings.json'));
    expect(c.themeMode, ThemeModeSetting.system);
    expect(c.resolutionScale, 1.0);
    expect(c.volumes['master'], 100);
    expect(c.keyMapping['confirm'], 'tap');
    expect(c.toLaunchOptions()['resolutionScale'], 1.0);
  });

  test('修改 + 持久化 + 重载', () async {
    final file = File('${tmp.path}/settings.json');
    final c = SettingsController(file: file);
    await c.setThemeMode(ThemeModeSetting.dark);
    await c.setResolutionScale(1.5);
    await c.setVolume('bgm', 55);
    await c.setKeyMapping('confirm', 'longPress');

    final reloaded = SettingsController(file: file);
    await reloaded.load();
    expect(reloaded.themeMode, ThemeModeSetting.dark);
    expect(reloaded.resolutionScale, 1.5);
    expect(reloaded.volumes['bgm'], 55);
    expect(reloaded.keyMapping['confirm'], 'longPress');

    final options = reloaded.toLaunchOptions();
    expect((options['volumes'] as Map)['bgm'], 55);
    expect((options['keyMapping'] as Map)['confirm'], 'longPress');
  });

  test('数值夹取与非法输入拒绝', () async {
    final c = SettingsController(file: File('${tmp.path}/settings.json'));
    await c.setVolume('master', 500);
    expect(c.volumes['master'], 100);
    await c.setVolume('voice', -20);
    expect(c.volumes['voice'], 0);
    await c.setResolutionScale(9.0);
    expect(c.resolutionScale, 2.0);
    await c.setResolutionScale(0.1);
    expect(c.resolutionScale, 0.5);

    // 不存在的通道与手势应被忽略
    await c.setVolume('hoge', 50);
    expect(c.volumes.containsKey('hoge'), isFalse);
    await c.setKeyMapping('confirm', 'nukeGesture');
    expect(c.keyMapping['confirm'], 'tap');
  });

  test('损坏的 JSON 退化为默认值', () async {
    final file = File('${tmp.path}/settings.json');
    await file.writeAsString('{{{ broken');
    final c = SettingsController(file: file);
    await c.load();
    expect(c.themeMode, ThemeModeSetting.system);
  });
}
