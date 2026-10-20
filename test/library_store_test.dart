import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusicgal/core/library/library_store.dart';
import 'package:lusicgal/core/models/engine_id.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lg_store');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('新增 / 查询 / 重命名 / 引擎变更', () async {
    final store = LibraryStore(root: tmp);
    await store.load();
    expect(store.games, isEmpty);

    final entry = await store.addNew(
      title: '星之梦',
      engine: EngineId.kirikiri,
      path: '${tmp.path}/g1',
    );
    expect(store.games.length, 1);
    expect(store.byId(entry.id)?.title, '星之梦');
    expect(entry.engine, EngineId.kirikiri);

    await store.rename(entry.id, 'planetarian');
    expect(store.byId(entry.id)?.title, 'planetarian');

    await store.setEngine(entry.id, EngineId.siglus, 'RealLive');
    expect(store.byId(entry.id)?.engine, EngineId.siglus);
    expect(store.byId(entry.id)?.engineDetail, 'RealLive');
  });

  test('JSON 持久化与重载', () async {
    final store = LibraryStore(root: tmp);
    await store.load();
    final e1 = await store.addNew(
      title: '月姬',
      engine: EngineId.onscripter,
      path: '${tmp.path}/g2',
      engineDetail: null,
    );
    await store.recordPlay(e1.id, const Duration(minutes: 5));

    final reloaded = LibraryStore(root: tmp);
    await reloaded.load();
    final g = reloaded.byId(e1.id);
    expect(g, isNotNull);
    expect(g!.title, '月姬');
    expect(g.engine, EngineId.onscripter);
    expect(g.playedSeconds, 300);
    expect(g.playedDisplay, '5 分钟');
    expect(g.lastPlayedAt, isNotNull);
  });

  test('删除（仅记录 / 连文件）', () async {
    final store = LibraryStore(root: tmp);
    await store.load();
    final dir = Directory('${tmp.path}/g3');
    await dir.create(recursive: true);
    final e1 = await store.addNew(
      title: '寒蝉',
      engine: EngineId.onscripter,
      path: dir.path,
    );

    await store.remove(e1.id, deleteFiles: false);
    expect(store.games, isEmpty);
    expect(dir.existsSync(), isTrue, reason: '仅移除记录不应删除文件');

    final e2 = await store.addNew(
      title: '寒蝉2',
      engine: EngineId.onscripter,
      path: dir.path,
    );
    await store.remove(e2.id, deleteFiles: true);
    expect(dir.existsSync(), isFalse, reason: '应删除游戏文件目录');

    final reloaded = LibraryStore(root: tmp);
    await reloaded.load();
    expect(reloaded.games, isEmpty);
  });

  test('路径丢失标记（pathMissing）', () async {
    final store = LibraryStore(root: tmp);
    await store.load();
    await store.addNew(
      title: '幽灵游戏',
      engine: EngineId.renpy,
      path: '${tmp.path}/not-exist',
    );
    final reloaded = LibraryStore(root: tmp);
    await reloaded.load();
    expect(reloaded.games.single.pathMissing, isTrue);
  });

  test('损坏的 JSON 退化为空库', () async {
    await File('${tmp.path}/library.json')
        .writeAsString('{ not valid json !!!');
    final store = LibraryStore(root: tmp);
    await store.load();
    expect(store.games, isEmpty);
  });

  test('引用文件夹条目：登记 / JSON 回读 / 删除保护', () async {
    final store = LibraryStore(root: tmp);
    await store.load();
    // 模拟用户共享目录中的游戏文件夹（在库外）。
    final userGame = Directory('${tmp.path}/shared/MyGame');
    await userGame.create(recursive: true);

    final ref = await store.addNew(
      title: 'MyGame',
      engine: EngineId.tyrano,
      path: userGame.path,
      sourceKind: 'folder',
      folderUri: 'content://tree/primary%3Ashared%2FMyGame',
    );
    expect(ref.isReferenced, isTrue);
    expect(ref.folderUri, isNotNull);

    // JSON 回读：引用字段不丢。
    final reloaded = LibraryStore(root: tmp);
    await reloaded.load();
    final g = reloaded.games.single;
    expect(g.isReferenced, isTrue);
    expect(g.sourceKind, 'folder');
    expect(g.folderUri, startsWith('content://tree/'));

    // 即使请求 deleteFiles=true，引用条目也绝不删用户文件。
    await reloaded.remove(g.id, deleteFiles: true);
    expect(reloaded.games, isEmpty);
    expect(userGame.existsSync(), isTrue,
        reason: '引用文件夹条目删除时不得动用户文件');

    // 普通导入条目保持原有删除语义（回归护栏）。
    final dir = Directory('${tmp.path}/g4');
    await dir.create(recursive: true);
    final normal = await store.addNew(
      title: '入库副本',
      engine: EngineId.kirikiri,
      path: dir.path,
    );
    expect(normal.isReferenced, isFalse);
    await store.remove(normal.id, deleteFiles: true);
    expect(dir.existsSync(), isFalse);
  });
}
