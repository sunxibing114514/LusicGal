import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusicgal/core/detect/engine_detector.dart';
import 'package:lusicgal/core/models/engine_id.dart';

/// 引擎识别测试：规则来源见 engine_detector.dart 头注释
/// （KEY 系规则逐条对应 siglus_rs engine-detect）。
void main() {
  late Directory tmp;
  final detector = EngineDetector();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lg_detect');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  /// 在 [dir] 下创建文件（bytes 为空则空文件）。
  Future<void> put(Directory dir, String name,
      [List<int> bytes = const []]) async {
    final f = File('${dir.path}/$name');
    await f.create(recursive: true);
    if (bytes.isNotEmpty) await f.writeAsBytes(bytes);
  }

  test('Kirikiri：XP3 魔数', () async {
    final g = await tmp.createTemp('kirikiri');
    await put(
      g,
      'data.xp3',
      [0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x8A, 0x00, 0x00, 0x00, 0x00],
    );
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.kirikiri);
    expect(r.confident, isTrue);
  });

  test('Kirikiri：startup.tjs', () async {
    final g = await tmp.createTemp('krkr_tjs');
    await put(g, 'startup.tjs');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.kirikiri);
    expect(r.confident, isTrue);
  });

  test('ONScripter：nscript.dat + arc.nsa（NSA 魔数）', () async {
    final g = await tmp.createTemp('ons');
    await put(g, 'nscript.dat', [1, 2, 3, 4]);
    await put(g, 'arc.nsa', [0x4E, 0x53, 0x41, 0x00, 0x00]);
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.onscripter);
    expect(r.confident, isTrue);
  });

  test("Ren'Py：RPA-3.0 魔数（game/scripts.rpa 嵌套目录）", () async {
    final g = await tmp.createTemp('renpy');
    await put(g, 'game/scripts.rpa', 'RPA-3.0 1234 20\n'.codeUnits);
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.renpy);
    expect(r.confident, isTrue);
  });

  test('Siglus：Scene.pck', () async {
    final g = await tmp.createTemp('siglus');
    await put(g, 'Scene.pck');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.siglus);
    expect(r.engineDetail, 'SiglusEngine');
    expect(r.confident, isTrue);
  });

  test('AVG32：Gameexe.ini + PACL 场景封包', () async {
    final g = await tmp.createTemp('avg32');
    await put(g, 'Gameexe.ini', '#title\n'.codeUnits);
    await put(g, 'SEEN.TXT', 'PACL'.codeUnits);
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.siglus);
    expect(r.engineDetail, 'AVG32');
  });

  test('RealLive：Gameexe.ini + 10000 条目 SEEN.TXT（0x1d0 头）', () async {
    final g = await tmp.createTemp('reallive');
    await put(g, 'Gameexe.ini', '#KID\n'.codeUnits);
    final seen = List<int>.filled(64, 0);
    // u32 entries = 10000, u32 first offset = 16
    seen[0] = 10000 & 0xFF;
    seen[1] = (10000 >> 8) & 0xFF;
    seen[2] = (10000 >> 16) & 0xFF;
    seen[3] = (10000 >> 24) & 0xFF;
    seen[4] = 16; // offset lo
    seen[16] = 0xD0; // 0x1d0 LE
    seen[17] = 0x01;
    await put(g, 'SEEN.TXT', seen);
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.siglus);
    expect(r.engineDetail, 'RealLive');
  });

  test('UK2：UK2 TEXT 魔数的 .mes', () async {
    final g = await tmp.createTemp('uk2');
    await put(g, '01.mes', '<< UK2 TEXT Ver1.00 >>\ndata'.codeUnits);
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.siglus);
    expect(r.engineDetail, 'UK2');
  });

  test('FVP（rfvp）：nvsg 封包 + hcb 脚本', () async {
    final g = await tmp.createTemp('rfvp');
    await put(g, 'data.nvsg');
    await put(g, 'boot.hcb');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.rfvp);
    expect(r.confident, isTrue);
  });

  test('Sena（SoftPAL）：pac 封包', () async {
    final g = await tmp.createTemp('sena');
    await put(g, 'data.pac');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.sena);
  });

  test('System 3.x：ald 封包', () async {
    final g = await tmp.createTemp('xsystem35');
    await put(g, 'data.ald');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.xsystem35);
    expect(r.confident, isTrue);
  });

  test('未知：空目录', () async {
    final g = await tmp.createTemp('unknown');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.unknown);
    expect(r.confident, isFalse);
  });

  test('多引擎并存取最高分（XP3 优先于低分特征）', () async {
    final g = await tmp.createTemp('mixed');
    await put(
      g,
      'data.xp3',
      [0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x8A, 0, 0, 0, 0],
    );
    await put(g, 'readme.pac'); // sena +6
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.kirikiri);
    expect(r.evidence.length, greaterThanOrEqualTo(2));
  });

  test('Tyrano：tyrano.js 运行时', () async {
    final g = await tmp.createTemp('tyrano');
    await put(g, 'index.html');
    await put(g, 'tyrano.js');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.tyrano);
    expect(r.confident, isTrue);
  });

  test('Tyrano：.ks 场景脚本', () async {
    final g = await tmp.createTemp('tyrano_ks');
    await put(g, 'data/scenario/first.ks');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.tyrano);
    expect(r.confident, isTrue);
  });

  test('RPG Maker MV：js/rpg_core.js', () async {
    final g = await tmp.createTemp('rpgmv');
    await put(g, 'index.html');
    await put(g, 'js/rpg_core.js');
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.rpgmv);
    expect(r.confident, isTrue);
  });

  test('RPG Maker MZ：js/rmmz_core.js（优先于 MV 通用证据）', () async {
    final g = await tmp.createTemp('rpgmz');
    await put(g, 'index.html');
    await put(g, 'js/plugins.js'); // MV 通用 +4
    await put(g, 'js/rmmz_core.js'); // MZ +10
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.rpgmz);
    expect(r.confident, isTrue);
  });

  test('PC：MZ 魔数 exe（低权重，让位核心证据）', () async {
    final g = await tmp.createTemp('pc');
    await put(g, 'Game.exe', [0x4D, 0x5A, 0x90, 0x00]);
    final r = detector.detect(g.path);
    expect(r.engine, EngineId.pcwinlator);
    // 混有 Ren'Py 证据时让位：
    final g2 = await tmp.createTemp('pc_renpy');
    await put(g2, 'Game.exe', [0x4D, 0x5A, 0x90, 0x00]);
    await put(g2, 'game/scripts.rpa', 'RPA-3.0 1234 20\n'.codeUnits);
    final r2 = detector.detect(g2.path);
    expect(r2.engine, EngineId.renpy);
  });

  test('PSP：detectFile（ISO9660 魔数 @0x8001）', () async {
    final f = File('${tmp.path}/umd.iso');
    final bytes = List<int>.filled(0x8010, 0);
    for (var i = 0; i < 5; i++) {
      bytes[0x8001 + i] = 'CD001'.codeUnitAt(i);
    }
    await f.writeAsBytes(bytes);
    final r = detector.detect(f.path); // 目录不存在 → 文件识别
    expect(r.engine, EngineId.psp);
    expect(r.confident, isTrue);
  });

  test('PSP：CSO 魔数 / PBP 魔数', () async {
    final cso = File('${tmp.path}/game.cso');
    await cso.writeAsBytes('CISO'.codeUnits);
    expect(detector.detectFile(cso.path).engine, EngineId.psp);

    final pbp = File('${tmp.path}/eboot.pbp');
    await pbp.writeAsBytes([0x00, ...'PBP'.codeUnits]);
    expect(detector.detectFile(pbp.path).engine, EngineId.psp);
  });
}
