import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lusicgal_engines/lusicgal_engines.dart';

import '../core/models/game_entry.dart';

/// 引擎门面：把平台桥插件的能力包装为面向业务的会话 API。
///
/// 平台桥协议见 plugins/lusicgal_engines；核心缺失时 [launchGame] 返回
/// `ok=false, errorCode=CORE_NOT_BUNDLED`，UI 据此给出指引而不是崩溃。
class EngineHost {
  final LusicgalEngines _engines = LusicgalEngines();

  /// 探测所有引擎核心的打包状态（Android: System.loadLibrary；
  /// iOS: dlsym）。平台通道不可用时（测试环境）返回空表。
  Future<Map<String, EngineProbe>> probeEngines() async {
    try {
      final list = await _engines.probeEngines();
      return {for (final e in list) e.engineId: e};
    } on MissingPluginException {
      return {};
    } on PlatformException {
      return {};
    }
  }

  /// 启动一个游戏的核心会话。
  Future<EngineLaunchResult> launchGame({
    required GameEntry game,
    required String savePath,
    Map<String, Object>? options,
  }) =>
      _engines.launch(
        engineId: game.engine.id,
        gameId: game.id,
        gamePath: game.path,
        savePath: savePath,
        options: options,
      );

  Stream<EngineEvent> get events => _engines.events();

  Future<void> pause() => _engines.sendCommand('pause');

  Future<void> resume() => _engines.sendCommand('resume');

  Future<void> stop() => _engines.sendCommand('stop');

  /// 通用命令（按键注入、读档等由核心自定义的 JSON 命令）。
  Future<void> sendCommand(String name, [Map<String, Object?>? args]) =>
      _engines.sendCommand(name, args);

  Future<void> dispose() async {
    try {
      await _engines.stop();
    } on MissingPluginException {
      // 纯 Dart 测试环境无平台实现 —— 忽略。
    }
  }
}
