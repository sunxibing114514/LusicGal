import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 单个引擎核心的探测结果。
@immutable
class EngineProbe {
  const EngineProbe({
    required this.engineId,
    required this.available,
    this.version,
    this.message,
  });

  factory EngineProbe.fromMap(Map<Object?, Object?> map) => EngineProbe(
        engineId: map['engineId']! as String,
        available: map['available'] == true,
        version: map['version'] as String?,
        message: map['message'] as String?,
      );

  final String engineId;
  final bool available;
  final String? version;

  /// 不可用原因 / 附注（如"核心未打包：见 engines.yml 构建"）。
  final String? message;
}

/// 启动结果。
@immutable
class EngineLaunchResult {
  const EngineLaunchResult({
    required this.ok,
    this.errorCode,
    this.message,
  });

  factory EngineLaunchResult.fromMap(Map<Object?, Object?> map) =>
      EngineLaunchResult(
        ok: map['ok'] == true,
        errorCode: map['errorCode'] as String?,
        message: map['message'] as String?,
      );

  /// 核心未随包发布（所有 v1 引擎均如此，直到引擎核心接入）。
  bool get coreMissing => errorCode == 'CORE_NOT_BUNDLED';

  final bool ok;
  final String? errorCode;
  final String? message;
}

/// 平台桥推送的引擎事件。
@immutable
class EngineEvent {
  const EngineEvent({required this.type, required this.data});

  factory EngineEvent.fromMap(Map<Object?, Object?> map) => EngineEvent(
        type: map['type']! as String,
        data: map['data'] as Map<Object?, Object?>? ?? const {},
      );

  /// log / state / exit / core_missing。
  final String type;
  final Map<Object?, Object?> data;
}

/// 文件夹选择结果（SAF ACTION_OPEN_DOCUMENT_TREE）。
///
/// [readable] 表示解析出的直路径当前可被 dart:io / 原生核心直接读取
/// （Android 10 共享目录受限时为 false，此时无法即选即用）。
@immutable
class FolderPickResult {
  const FolderPickResult({
    required this.ok,
    this.uri,
    this.path,
    this.name,
    this.readable = false,
    this.message,
  });

  factory FolderPickResult.fromMap(Map<Object?, Object?> map) => FolderPickResult(
        ok: map['ok'] == true,
        uri: map['uri'] as String?,
        path: map['path'] as String?,
        name: map['name'] as String?,
        readable: map['readable'] == true,
        message: map['message'] as String?,
      );

  /// 用户完成选择（区别于取消/失败）。
  final bool ok;
  final String? uri;
  final String? path;
  final String? name;
  final bool readable;
  final String? message;
}

/// 平台桥入口：probe / launch / command / events。
class LusicgalEngines {
  static const MethodChannel _method = MethodChannel('lusicgal/engines');
  static const EventChannel _events = EventChannel('lusicgal/engineEvents');

  /// PlatformView viewType（AndroidView / UiKitView）。
  static const String engineViewType = 'lusicgal-engine-view';

  Future<List<EngineProbe>> probeEngines() async {
    final raw = await _method.invokeMethod<Map<Object?, Object?>>('probeEngines');
    final list = raw == null ? const [] : raw['engines'] as List<Object?>? ?? const [];
    return list
        .whereType<Map>()
        .map((m) => EngineProbe.fromMap(m.cast<Object?, Object?>()))
        .toList();
  }

  Future<EngineLaunchResult> launch({
    required String engineId,
    required String gameId,
    required String gamePath,
    required String savePath,
    Map<String, Object>? options,
  }) async {
    final raw = await _method.invokeMethod<Map<Object?, Object?>>('launch', {
      'engineId': engineId,
      'gameId': gameId,
      'gamePath': gamePath,
      'savePath': savePath,
      if (options != null) 'options': options,
    });
    if (raw == null) {
      return const EngineLaunchResult(ok: false, message: '平台桥无返回');
    }
    return EngineLaunchResult.fromMap(raw);
  }

  /// 通用命令通道：pause / resume / stop / keyEvent / 自定义 JSON 命令。
  Future<void> sendCommand(String command, [Map<String, Object?>? args]) async {
    await _method.invokeMethod<void>('command', {
      'command': command,
      if (args != null) 'args': args,
    });
  }

  Future<void> stop() => sendCommand('stop');

  /// v2：输入事件注入（JSON 见 engine_abi.h：point/key/text；x/y 为 0~1）。
  Future<int> pushInput(String json) async {
    final rc = await _method.invokeMethod<int>('pushInput', {'json': json});
    return rc ?? -1;
  }

  /// v2：渲染面尺寸变化（旋转/分屏）。
  Future<int> surfaceSize(int w, int h) async {
    final rc = await _method.invokeMethod<int>('surfaceSize', {'w': w, 'h': h});
    return rc ?? -1;
  }

  /// 引擎事件流（EventChannel）。
  static Stream<EngineEvent> _eventStream(String gameId) =>
      _events.receiveBroadcastStream(gameId).map((raw) {
        if (raw is Map) {
          return EngineEvent.fromMap(raw.cast<Object?, Object?>());
        }
        return EngineEvent(type: 'log', data: {'message': '$raw'});
      });

  /// 单个游戏的会话事件流。
  Stream<EngineEvent> events({String? gameId}) => _eventStream(gameId ?? 'global');

  /// 选择游戏文件夹（SAF；Android 实现，其他平台返回 ok=false）。
  Future<FolderPickResult> pickGameFolder() async {
    try {
      final raw =
          await _method.invokeMethod<Map<Object?, Object?>>('pickGameFolder');
      if (raw == null) {
        return const FolderPickResult(ok: false, message: '平台桥无返回');
      }
      return FolderPickResult.fromMap(raw);
    } on MissingPluginException {
      return const FolderPickResult(ok: false, message: '当前平台不支持文件夹选择');
    } on PlatformException catch (e) {
      return FolderPickResult(ok: false, message: e.message);
    }
  }
}
