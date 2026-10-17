// 独立验证 harness：不经 flutter_test，直接驱动真实检测器
//（engine_detector 纯 dart:io，可独立编译运行）。
// 用后即删：CI 的 flutter test 仍以 test/engine_detector_test.dart 为准。
import 'dart:io';
import '../lib/core/detect/engine_detector.dart';
import '../lib/core/models/engine_id.dart';

int passed = 0, failed = 0;

Future<void> put(Directory dir, String name, [List<int> bytes = const []]) async {
  final f = File('${dir.path}/$name');
  await f.create(recursive: true);
  if (bytes.isNotEmpty) await f.writeAsBytes(bytes);
}

void check(String label, bool cond) {
  if (cond) {
    passed++;
    print('PASS  $label');
  } else {
    failed++;
    print('FAIL  $label');
  }
}

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('lg_detect');
  final d = EngineDetector();

  // --- 新规则：Tyrano ---
  var g = await tmp.createTemp('tyrano');
  await put(g, 'index.html');
  await put(g, 'tyrano.js');
  var r = d.detect(g.path);
  check('tyrano.js → tyrano', r.engine == EngineId.tyrano && r.confident);

  g = await tmp.createTemp('tyrano_ks');
  await put(g, 'data/scenario/first.ks');
  r = d.detect(g.path);
  check('.ks → tyrano (≥6)', r.engine == EngineId.tyrano && r.confident);

  g = await tmp.createTemp('tyrano_asar');
  await put(g, 'app.asar', [0, 0, 0, 4]);
  r = d.detect(g.path);
  check('app.asar → tyrano (9 分)', r.engine == EngineId.tyrano && r.confident);

  // --- 新规则：RPG MV / MZ ---
  g = await tmp.createTemp('rpgmv');
  await put(g, 'index.html');
  await put(g, 'js/rpg_core.js');
  r = d.detect(g.path);
  check('rpg_core.js → rpgmv', r.engine == EngineId.rpgmv && r.confident);

  g = await tmp.createTemp('rpgmz');
  await put(g, 'index.html');
  await put(g, 'js/plugins.js');
  await put(g, 'js/rmmz_core.js');
  r = d.detect(g.path);
  check('rmmz_core.js 优先于 MV 通用证据', r.engine == EngineId.rpgmz && r.confident);

  // --- PC 条目已移除（用户指令）：exe 不再产生证据 ---
  g = await tmp.createTemp('pc_renpy');
  await put(g, 'Game.exe', [0x4D, 0x5A, 0x90, 0x00]);
  await put(g, 'game/scripts.rpa', 'RPA-3.0 1234 20\n'.codeUnits);
  r = d.detect(g.path);
  check('exe 不再产生 PC 证据（rpa 照常驱动 Ren\'Py）',
      r.engine == EngineId.renpy && r.confident);

  g = await tmp.createTemp('pc_only');
  await put(g, 'Game.exe', [0x4D, 0x5A, 0x90, 0x00]);
  r = d.detect(g.path);
  check('纯 exe 目录 → unknown', r.engine == EngineId.unknown);

  // --- 回归：原有规则不回归 ---
  g = await tmp.createTemp('krkr');
  await put(g, 'data.xp3', [0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x8A, 0, 0, 0, 0]);
  await put(g, 'readme.pac');
  r = d.detect(g.path);
  check('回归：XP3 优先于低分特征', r.engine == EngineId.kirikiri);

  g = await tmp.createTemp('unknown');
  r = d.detect(g.path);
  check('回归：空目录 → unknown', r.engine == EngineId.unknown && !r.confident);

  g = await tmp.createTemp('ons');
  await put(g, 'nscript.dat', [1, 2, 3, 4]);
  r = d.detect(g.path);
  check('回归：nscript.dat → onscripter', r.engine == EngineId.onscripter);

  g = await tmp.createTemp('xsystem35');
  await put(g, 'data.ald');
  r = d.detect(g.path);
  check('回归：ald → xsystem35', r.engine == EngineId.xsystem35);

  // --- EngineId 形态标志 ---
  check('isWebGame 三员', EngineId.tyrano.isWebGame &&
      EngineId.rpgmv.isWebGame && EngineId.rpgmz.isWebGame);
  check('isOutboard = renpy + web', EngineId.renpy.isOutboard &&
      EngineId.tyrano.isOutboard &&
      !EngineId.kirikiri.isOutboard && !EngineId.onscripter.isOutboard);
  check('fromId 往返', EngineId.fromId('tyrano') == EngineId.tyrano &&
      EngineId.fromId('nope') == EngineId.unknown);
  check('isCore 仅 8 真核', EngineId.kirikiri.isCore &&
      !EngineId.tyrano.isCore && !EngineId.renpy.isWebGame);

  await tmp.delete(recursive: true);
  print('\npassed=$passed failed=$failed');
  exit(failed == 0 ? 0 : 1);
}
