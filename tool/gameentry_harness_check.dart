// GameEntry options 序列化往返 + 形态注释一致性验证（纯 Dart）。
// 用后即删：CI 的 flutter test 仍以 test/library_store_test.dart 为准。
import 'dart:io';
import '../lib/core/models/engine_id.dart';
import '../lib/core/models/game_entry.dart';

int passed = 0, failed = 0;
void check(String label, bool cond) {
  if (cond) { passed++; print('PASS  $label'); }
  else { failed++; print('FAIL  $label'); }
}

Future<void> main() async {
  // 旧格式兼容（无 options 字段）。
  final legacy = GameEntry.fromJson({
    'id': 'g1',
    'title': '旧条目',
    'engine': 'kirikiri',
    'engineDetail': null,
    'path': '/x/y',
    'addedAt': '2026-10-15T00:00:00.000',
    'lastPlayedAt': null,
    'playedSeconds': 0,
  });
  check('旧 JSON 无 options → {}', legacy.options.isEmpty);

  // 新格式：options 持久化往返。
  final e = GameEntry(
    id: 'g2',
    title: 'PC 条目',
    engine: EngineId.pcwinlator,
    engineDetail: 'Game.exe',
    path: '/data/games/g2',
    addedAt: DateTime.parse('2026-10-15T00:00:00.000'),
    options: {
      'container_id': 3,
      'graphics_driver': 'turnip,zink',
      'screen_size': '1600x900',
    },
  );
  final json = e.toJson().map((k, v) => MapEntry<Object?, Object?>(k, v));
  final back = GameEntry.fromJson(json);
  check('options 往返（3 键）', back.options.length == 3 &&
      back.options['container_id'] == 3 &&
      back.options['graphics_driver'] == 'turnip,zink' &&
      back.options['screen_size'] == '1600x900');
  check('engineDetail 往返', back.engineDetail == 'Game.exe');
  check('engine 往返', back.engine == EngineId.pcwinlator);

  // 空 options 不写键（老存储干净）。
  final noOpt = GameEntry(
    id: 'g3', title: 't', engine: EngineId.sena, path: '/p',
    addedAt: DateTime.now(),
  );
  check('空 options 不入 JSON', !noOpt.toJson().containsKey('options'));

  // path 语义文档一致性（形态 → 字段注释）。
  check('psp 条目 path=文件 / androidapp path=包名（注释约束）',
      EngineId.psp.isExternalLauncher && EngineId.androidapp.isExternalLauncher);

  print('\npassed=$passed failed=$failed');
  exit(failed == 0 ? 0 : 1);
}
