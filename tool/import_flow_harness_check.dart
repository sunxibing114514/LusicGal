// 导入流 harness：目录导入搬移沙盒 / Web 工程识别入库 / 封包导入
//（经 flutter pub get 的 package_config 直跑真源码；foundation 走最小桩，
// 见 tool/gen_alt_packages.py —— 外板条目已按用户指令移除）。
import 'dart:io';
import '../lib/core/library/import_service.dart';
import '../lib/core/library/library_store.dart';
import '../lib/core/models/engine_id.dart';

int passed = 0, failed = 0;
void check(String label, bool cond) {
  if (cond) { passed++; print('PASS  $label'); }
  else { failed++; print('FAIL  $label'); }
}

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('lg_import');
  try {
    final store = LibraryStore(root: tmp);
    await store.load();
    final import = ImportService(store: store, importRoots: [tmp]);

    // ---- 核心引擎目录：搬入沙盒 ----
    final krkr = Directory('${tmp.path}/krkrgame');
    await krkr.create();
    await File('${krkr.path}/data.xp3')
        .writeAsBytes([0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x8A, 0, 0, 0, 0]);
    final r1 = await import.importDirectory(krkr);
    check('KRKR 识别入库', r1.imported && r1.engine == EngineId.kirikiri);
    check('搬入沙盒（源目录消失）', !krkr.existsSync());
    final e1 = store.byId(r1.gameId ?? '');
    check('path=沙盒目录', e1 != null &&
        e1.path.startsWith('${tmp.path}/games/') &&
        File('${e1.path}/data.xp3').existsSync());

    // ---- Web 工程（Tyrano）：搬入沙盒 + 可直接游玩形态 ----
    final ty = Directory('${tmp.path}/tyranogame');
    await Directory('${ty.path}/data').create(recursive: true);
    await File('${ty.path}/index.html').writeAsString('<html><head></head></html>');
    await File('${ty.path}/tyrano.js').writeAsString('//tyrano');
    await File('${ty.path}/data/system/Config.tjs').create(recursive: true);
    final r2 = await import.importDirectory(ty);
    check('Tyrano 识别入库', r2.imported && r2.engine == EngineId.tyrano);
    final e2 = store.byId(r2.gameId ?? '');
    check('Web 条目 path=沙盒目录（WebView 直读）', e2 != null &&
        e2.path.startsWith('${tmp.path}/games/') &&
        File('${e2.path}/index.html').existsSync());
    check('isWebGame 形态（App 内直接游玩）', e2!.engine.isWebGame && e2.engine.isOutboard);

    // ---- 封包导入（.xp3 单文件建目录）----
    final src = File('${tmp.path}/loose.xp3');
    await src.writeAsBytes([0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x8A, 0, 0, 0, 0]);
    final r3 = await import.importFiles([src], title: '散装封包');
    check('封包导入识别', r3.imported && r3.engine == EngineId.kirikiri);
    check('封包入库（源文件保留）', src.existsSync() &&
        store.byId(r3.gameId ?? '')!.path.startsWith('${tmp.path}/games/'));

    // ---- 未识别目录：不导入、不搬动 ----
    final unk = Directory('${tmp.path}/junkdir');
    await unk.create();
    await File('${unk.path}/Game.exe').writeAsBytes([0x4D, 0x5A, 0x90, 0x00]);
    final r4 = await import.importDirectory(unk);
    check('纯 exe 目录不识别（PC 条目已移除）', !r4.imported);
    check('未识别目录原地不动', unk.existsSync());
  } finally {
    await tmp.delete(recursive: true);
  }
  print('\npassed=$passed failed=$failed');
  exit(failed == 0 ? 0 : 1);
}
