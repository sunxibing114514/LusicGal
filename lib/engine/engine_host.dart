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
  ///
  /// [options] 为全局设置项；条目级参数由 [GameEntry.options] 自动合并
  ///（条目值优先）。
  Future<EngineLaunchResult> launchGame({
    required GameEntry game,
    required String savePath,
    Map<String, Object>? options,
  }) {
    final opts = <String, Object?>{...?options, ...game.options};
    // 平台通道编码要求非空值（game.options 反序列化可能带 null）。
    final clean = <String, Object>{};
    opts.forEach((k, v) {
      if (v != null) clean[k] = v;
    });
    return _engines.launch(
      engineId: game.engine.id,
      gameId: game.id,
      gamePath: game.path,
      savePath: savePath,
      options: clean,
    );
  }

  Stream<EngineEvent> events({String? gameId}) =>
      _engines.events(gameId: gameId);

  Future<void> pause() => _engines.sendCommand('pause');

  Future<void> resume() => _engines.sendCommand('resume');

  Future<void> stop() => _engines.sendCommand('stop');

  /// 通用命令（按键注入、读档等由核心自定义的 JSON 命令）。
  Future<void> sendCommand(String name, [Map<String, Object?>? args]) =>
      _engines.sendCommand(name, args);

  /// v2：触摸注入（x/y 为渲染面归一化坐标 0~1；phase: down/move/up/cancel）。
  Future<void> touch(PointPhase phase, double x, double y, {int pointer = 1}) =>
      _engines.pushInput('{"type":"point","phase":"${phase.name}","x":$x,"y":$y,'
          '"pointer":$pointer}');

  /// v2：按键注入（code: ok/cancel/menu/up/down/left/right/speed/auto/skip/
  /// save/load/text；down=false 表示抬起）。
  Future<void> key(String code, {bool down = true, bool repeat = false}) =>
      _engines.pushInput('{"type":"key","code":"$code","state":"'
          '${down ? 'down' : 'up'}","repeat":$repeat}');

  /// v2：软键盘文本提交。
  Future<void> text(String utf8) {
    final encoded = jsonEscape(utf8);
    return _engines.pushInput('{"type":"text","utf8":"$encoded"}');
  }

  /// v2：渲染面尺寸变化（旋转/分屏）。
  Future<void> surfaceSize(int w, int h) async {
    try {
      await _engines.surfaceSize(w, h);
    } on MissingPluginException {
      // 纯 Dart 测试环境无平台实现 —— 忽略。
    }
  }

  /// v2：输入注入底层入口（自定义事件直接给 JSON）。
  Future<void> pushInputJson(String json) async {
    try {
      await _engines.pushInput(json);
    } on MissingPluginException {
      // 纯 Dart 测试环境无平台实现 —— 忽略。
    }
  }

  /// JSON 字符串转义（输入注入用；避免引号破坏事件结构）。
  static String jsonEscape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');

  Future<void> dispose() async {
    try {
      await _engines.stop();
    } on MissingPluginException {
      // 纯 Dart 测试环境无平台实现 —— 忽略。
    }
  }
}

/// 触摸相位（与 engine_abi.h 的 point 事件 phase 对应）。
enum PointPhase { down, move, up, cancel }
