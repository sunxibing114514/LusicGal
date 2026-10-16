// 导入流 harness：PC 原位条目 / 自动挑 exe / PSP 入库 / 应用条目
//（经 flutter pub get 的 package_config 直跑真源码；用后保留为本地验证项）。
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

    // ---- PC 原位导入（目录含 MZ 魔数 exe；不带 .pac —— 现实 PC 目录）----
    final pcDir = Directory('${tmp.path}/pcgame');
    await Directory('${pcDir.path}/bin').create(recursive: true);
    final exe = File('${pcDir.path}/bin/Game.exe');
    await exe.writeAsBytes([0x4D, 0x5A, 0x90, 0x00]);
    await File('${pcDir.path}/game.dat').writeAsBytes([1, 2, 3]);

    final r1 = await import.importDirectory(pcDir);
    check('PC 自动识别 → pcwinlator', r1.imported && r1.engine == EngineId.pcwinlator);
    check('PC 原位：目录未被搬动', pcDir.existsSync() && exe.existsSync());
    final entry1 = store.byId(r1.gameId ?? '');
    check('PC 条目 path=原位目录', entry1?.path == pcDir.path);
    check('PC 自动挑 exe（子目录）', entry1?.engineDetail == 'bin/Game.exe');

    // ---- addPcEntryInPlace：顶层 exe 偏好 ----
    final pc2 = Directory('${tmp.path}/pc2');
    await pc2.create();
    await File('${pc2.path}/start.exe').writeAsBytes([0x4D, 0x5A]);
    await File('${pc2.path}/other.exe').writeAsBytes([0x4D, 0x5A]);
    final r2 = await import.addPcEntryInPlace(dir: pc2);
    check('in-place 顶层 exe（偏好 start）',
        r2.imported && r2.engineDetail == 'start.exe');
    check('in-place 不复制', pc2.existsSync() &&
        store.byId(r2.gameId ?? '')?.path == pc2.path);

    // ---- addPcEntryInPlace：无 exe 报错 ----
    final pc3 = Directory('${tmp.path}/pc3');
    await pc3.create();
    final r3 = await import.addPcEntryInPlace(dir: pc3);
    check('无 exe → 报错不导入', !r3.imported && (r3.error?.contains('.exe') ?? false));

    // ---- PSP 入库（复制进沙盒）----
    final isoBytes = List<int>.filled(0x8010, 0);
    for (var i = 0; i < 5; i++) {
      isoBytes[0x8001 + i] = 'CD001'.codeUnitAt(i);
    }
    final srcIso = File('${tmp.path}/umdgame.iso');
    await srcIso.writeAsBytes(isoBytes);
    final r4 = await import.importPspFile(srcIso);
    check('PSP 识别入库', r4.imported && r4.engine == EngineId.psp);
    final entry4 = store.byId(r4.gameId ?? '');
    check('PSP path=沙盒文件（≠原位）',
        entry4 != null && entry4.path != srcIso.path &&
            entry4.path.startsWith('${tmp.path}/games/'));
    check('PSP 目标文件存在', File(entry4?.path ?? 'x').existsSync());

    // ---- 应用条目 ----
    final r5 = await import.addAppEntry(packageName: 'com.demo.game', label: '演示');
    check('应用条目 path=包名',
        r5.imported && store.byId(r5.gameId ?? '')?.path == 'com.demo.game');
    check('应用条目标题', store.byId(r5.gameId ?? '')?.title == '演示');

    // ---- 常规引擎仍走搬移（回归）----
    final krkr = Directory('${tmp.path}/krkrgame');
    await krkr.create();
    await File('${krkr.path}/data.xp3')
        .writeAsBytes([0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x8A, 0, 0, 0, 0]);
    final r6 = await import.importDirectory(krkr);
    check('回归：核心引擎仍搬入沙盒',
        r6.imported && r6.engine == EngineId.kirikiri &&
            !krkr.existsSync() &&
            store.byId(r6.gameId ?? '')?.path.startsWith('${tmp.path}/games/') == true);
  } finally {
    await tmp.delete(recursive: true);
  }
  print('\npassed=$passed failed=$failed');
  exit(failed == 0 ? 0 : 1);
}
