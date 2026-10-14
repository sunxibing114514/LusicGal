import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 主题模式设置。
enum ThemeModeSetting { system, light, dark }

/// 设置中心：主题 / 分辨率缩放 / 音量 / 按键映射。
class SettingsController extends ChangeNotifier {
  SettingsController({required File file}) : _file = file;

  final File _file;

  ThemeModeSetting themeMode = ThemeModeSetting.system;

  /// 渲染分辨率缩放（0.5 – 2.0，1.0 为原生）。
  double resolutionScale = 1.0;

  /// 四通道音量（0–100）。
  final Map<String, int> volumes = {
    'master': 100,
    'bgm': 100,
    'se': 100,
    'voice': 100,
  };

  /// 按键映射：动作 → 手势（核心以 launch options JSON 接收）。
  final Map<String, String> keyMapping = {
    'confirm': 'tap',
    'cancel': 'longPress',
    'skip': 'doubleTap',
    'fastForward': 'swipeRight',
    'menu': 'swipeUp',
    'save': 'swipeLeft',
    'load': 'swipeDown',
  };

  static const List<String> volumeChannels = ['master', 'bgm', 'se', 'voice'];

  static const List<String> keyActions = [
    'confirm',
    'cancel',
    'skip',
    'fastForward',
    'menu',
    'save',
    'load',
  ];

  static const List<String> gestures = [
    'tap',
    'doubleTap',
    'longPress',
    'swipeLeft',
    'swipeRight',
    'swipeUp',
    'swipeDown',
    'volumeUp',
    'volumeDown',
    'back',
  ];

  Future<void> load() async {
    if (!_file.existsSync()) return;
    try {
      final raw = await _file.readAsString();
      final map = jsonDecode(raw);
      if (map is! Map) return;
      final mode = map['themeMode'];
      if (mode is String) {
        themeMode = ThemeModeSetting.values
            .where((e) => e.name == mode)
            .firstOrElse(ThemeModeSetting.system);
      }
      final scale = map['resolutionScale'];
      if (scale is num) {
        resolutionScale = scale.clamp(0.5, 2.0).toDouble();
      }
      final vols = map['volumes'];
      if (vols is Map) {
        for (final ch in volumeChannels) {
          final v = vols[ch];
          if (v is num) volumes[ch] = v.clamp(0, 100).toInt();
        }
      }
      final keys = map['keyMapping'];
      if (keys is Map) {
        for (final action in keyActions) {
          final v = keys[action];
          if (v is String && gestures.contains(v)) keyMapping[action] = v;
        }
      }
      notifyListeners();
    } on FormatException {
      // 忽略损坏的配置。
    }
  }

  Future<void> _persist() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'themeMode': themeMode.name,
        'resolutionScale': resolutionScale,
        'volumes': volumes,
        'keyMapping': keyMapping,
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  Future<void> setThemeMode(ThemeModeSetting mode) async {
    if (themeMode == mode) return;
    themeMode = mode;
    await _persist();
    notifyListeners();
  }

  Future<void> setResolutionScale(double value) async {
    resolutionScale = value.clamp(0.5, 2.0).toDouble();
    await _persist();
    notifyListeners();
  }

  Future<void> setVolume(String channel, int value) async {
    if (!volumeChannels.contains(channel)) return;
    volumes[channel] = value.clamp(0, 100).toInt();
    await _persist();
    notifyListeners();
  }

  Future<void> setKeyMapping(String action, String gesture) async {
    if (!keyActions.contains(action) || !gestures.contains(gesture)) return;
    keyMapping[action] = gesture;
    await _persist();
    notifyListeners();
  }

  /// 生成传给引擎核心的启动参数（engine_abi.h 的 desc.options_json）。
  Map<String, Object> toLaunchOptions() => {
        'resolutionScale': resolutionScale,
        'volumes': Map<String, int>.from(volumes),
        'keyMapping': Map<String, String>.from(keyMapping),
      };
}

extension<T> on Iterable<T> {
  T firstOrElse(T fallback) {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return fallback;
  }
}
