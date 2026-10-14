import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings/settings_controller.dart';
import '../ui_helpers.dart';

/// 设置页：外观（明暗）/ 渲染缩放 / 音量 / 按键映射。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Section(title: '外观'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题模式', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeModeSetting>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeModeSetting.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('跟随系统'),
                      ),
                      ButtonSegment(
                        value: ThemeModeSetting.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('浅色'),
                      ),
                      ButtonSegment(
                        value: ThemeModeSetting.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('深色'),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (selection) =>
                        settings.setThemeMode(selection.first),
                  ),
                ],
              ),
            ),
          ),
          const _Section(title: '渲染'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '分辨率缩放',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text('${(settings.resolutionScale * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                  Slider(
                    value: settings.resolutionScale,
                    min: 0.5,
                    max: 2.0,
                    divisions: 6,
                    label: '${(settings.resolutionScale * 100).toStringAsFixed(0)}%',
                    onChanged: (v) => settings.setResolutionScale(v),
                  ),
                  Text(
                    '低于 100% 可提升低端机性能；高于 100% 提升渲染清晰度（更耗电）。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const _Section(title: '音量'),
          for (final channel in SettingsController.volumeChannels)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            volumeChannelLabels[channel] ?? channel,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Text('${settings.volumes[channel] ?? 100}'),
                      ],
                    ),
                    Slider(
                      value: (settings.volumes[channel] ?? 100).toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: volumeChannelLabels[channel] ?? channel,
                      onChanged: (v) => settings.setVolume(channel, v.round()),
                    ),
                  ],
                ),
              ),
            ),
          const _Section(title: '按键映射'),
          for (final action in SettingsController.keyActions)
            Card(
              child: ListTile(
                title: Text(keyActionLabels[action] ?? action),
                trailing: PopupMenuButton<String>(
                  initialValue: settings.keyMapping[action],
                  tooltip: '选择手势',
                  onSelected: (gesture) =>
                      settings.setKeyMapping(action, gesture),
                  itemBuilder: (context) => [
                    for (final gesture in SettingsController.gestures)
                      PopupMenuItem(
                        value: gesture,
                        child: Text(gestureLabels[gesture] ?? gesture),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          gestureLabels[settings.keyMapping[action]] ??
                              settings.keyMapping[action] ??
                          '',
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const _Section(title: '关于'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LusicGal v0.1.0'),
                  SizedBox(height: 4),
                  Text(
                    '多引擎视觉小说 / ADV 移动端运行器\n'
                    '许可：GPL-3.0 · 引擎核心许可见 docs/LICENSE_NOTES.md\n'
                    '上游选型与 pin 见 docs/ENGINE_NOTES.md',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
