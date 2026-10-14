import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusicgal/core/saves/save_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late SaveManager manager;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lg_saves');
    manager = SaveManager(root: tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('列出 / 删除存档文件（含子目录）', () async {
    final dir = manager.saveDirFor('g1', 'onscripter');
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'sav001.dat')).writeAsString('A');
    await Directory(p.join(dir.path, 'quick')).create();
    await File(p.join(dir.path, 'quick', 'q1.dat')).writeAsString('B');

    final items = await manager.listSaves('g1', 'onscripter');
    expect(items.length, 2);
    expect(items.map((i) => i.relativePath), containsAll(['sav001.dat', p.join('quick', 'q1.dat')]));

    await manager.deleteSave(items.first, 'g1', 'onscripter');
    final after = await manager.listSaves('g1', 'onscripter');
    expect(after.length, 1);
  });

  test('导出 zip 并可再导入（round-trip）', () async {
    final dir = manager.saveDirFor('g2', 'kirikiri');
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'savedata.sav')).writeAsString('DATA');
    await File(p.join(dir.path, 'global.sav')).writeAsString('GLOBAL');

    final out = await manager.exportZip('g2', 'kirikiri', title: '测试 游戏!');
    expect(await out.exists(), isTrue);
    expect(p.basename(out.path).startsWith('______'), isFalse); // sanitize 后非空

    final bytes = await out.readAsBytes();
    final imported = await manager.importZip('g9', 'kirikiri', bytes);
    expect(imported, 2);
    final listed = await manager.listSaves('g9', 'kirikiri');
    expect(listed.map((i) => i.relativePath), containsAll(['savedata.sav', 'global.sav']));
    expect(File(p.join(manager.saveDirFor('g9', 'kirikiri').path, 'savedata.sav'))
        .readAsStringSync(), 'DATA');
  });

  test('zip-slip 防护：拒绝路径穿越条目', () async {
    final evil = Archive()
      ..add(ArchiveFile('../evil.txt', 5, [1, 2, 3, 4, 5]))
      ..add(ArchiveFile('/abs/path.txt', 5, [1, 2, 3, 4, 5]))
      ..add(ArchiveFile('ok.txt', 2, [65, 66]));
    final bytes = ZipEncoder().encode(evil);

    final count = await manager.importZip('g3', 'onscripter', bytes);
    expect(count, 1, reason: '仅接受合法条目');
    expect(File(p.join(manager.saveDirFor('g3', 'onscripter').path, 'ok.txt')).existsSync(), isTrue);
    expect(File(p.join(tmp.parent.path, 'evil.txt')).existsSync(), isFalse);
  });

  test('空目录导出：生成合法 zip（0 条目）', () async {
    final dir = manager.saveDirFor('g4', 'renpy');
    await dir.create(recursive: true);
    final out = await manager.exportZip('g4', 'renpy', title: 'empty');
    expect(await out.exists(), isTrue);
  });
}
