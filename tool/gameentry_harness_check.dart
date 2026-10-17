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
    title: '条目级参数',
    engine: EngineId.siglus,
    engineDetail: 'RealLive',
    path: '/data/games/g2',
    addedAt: DateTime.parse('2026-10-15T00:00:00.000'),
    options: {
      'volume': 80,
      'fontScale': 1.25,
      'fullscreen': true,
    },
  );
  final json = e.toJson().map((k, v) => MapEntry<Object?, Object?>(k, v));
  final back = GameEntry.fromJson(json);
  check('options 往返（3 键）', back.options.length == 3 &&
      back.options['volume'] == 80 &&
      back.options['fontScale'] == 1.25 &&
      back.options['fullscreen'] == true);
  check('engineDetail 往返', back.engineDetail == 'RealLive');
  check('engine 往返', back.engine == EngineId.siglus);

  // 空 options 不写键（老存储干净）。
  final noOpt = GameEntry(
    id: 'g3', title: 't', engine: EngineId.sena, path: '/p',
    addedAt: DateTime.now(),
  );
  check('空 options 不入 JSON', !noOpt.toJson().containsKey('options'));

  // 引擎形态（外板条目已移除，用户指令）。
  check('全部形态：8 核心 + 3 Web，无外板',
      EngineId.values.where((e) => e.isCore).length == 8 &&
      EngineId.values.where((e) => e.isWebGame).length == 3);

  print('\npassed=$passed failed=$failed');
  exit(failed == 0 ? 0 : 1);
}
