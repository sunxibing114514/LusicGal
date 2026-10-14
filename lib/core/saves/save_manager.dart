import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// 单个存档文件。
class SaveItem {
  SaveItem({
    required this.relativePath,
    required this.absolutePath,
    required this.sizeBytes,
    required this.modified,
  });

  final String relativePath;
  final String absolutePath;
  final int sizeBytes;
  final DateTime modified;
}

/// 存档管理：按 `<docs>/saves/<gameId>/<engineId>/` 隔离；
/// zip 导出至 `<docs>/export/`（iOS 经"文件"App 可直接取走）。
class SaveManager {
  SaveManager({required this.root});

  final Directory root;

  Directory saveDirFor(String gameId, String engineId) =>
      Directory(p.join(root.path, 'saves', gameId, engineId));

  Directory get exportDir => Directory(p.join(root.path, 'export'));

  /// 递归列出某游戏的全部存档文件。
  Future<List<SaveItem>> listSaves(String gameId, String engineId) async {
    final dir = saveDirFor(gameId, engineId);
    if (!dir.existsSync()) return const [];
    final items = <SaveItem>[];
    await for (final entity in dir.list(followLinks: false, recursive: true)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      items.add(SaveItem(
        relativePath: p.relative(entity.path, from: dir.path),
        absolutePath: entity.path,
        sizeBytes: stat.size,
        modified: stat.modified,
      ));
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  /// 导出为 zip。返回导出文件。
  Future<File> exportZip(
    String gameId,
    String engineId, {
    required String title,
  }) async {
    final dir = saveDirFor(gameId, engineId);
    final archive = Archive();
    if (dir.existsSync()) {
      await for (final entity in dir.list(followLinks: false, recursive: true)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: dir.path);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(
          'saves/$rel',
          bytes.length,
          bytes,
        ));
      }
    }
    final encoded = ZipEncoder().encode(archive) ?? <int>[];
    await exportDir.create(recursive: true);
    final slug = _sanitize(title);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '').substring(0, 15);
    final out = File(p.join(exportDir.path, '$slug-saves-$stamp.zip'));
    await out.writeAsBytes(encoded, flush: true);
    return out;
  }

  /// 从 zip 导入（带 zip-slip 防护）。返回解出的文件数。
  Future<int> importZip(String gameId, String engineId, List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final dir = saveDirFor(gameId, engineId);
    final dirAbs = p.normalize(dir.absolute.path);
    var count = 0;
    await dir.create(recursive: true);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      var name = entry.name;
      // 兼容由本应用导出的 zip（saves/ 前缀）。
      if (name.startsWith('saves/')) name = name.substring('saves/'.length);
      if (name.isEmpty || name.startsWith('/') || p.isAbsolute(name)) continue;
      final normalized = p.normalize(name);
      if (normalized.split(p.separator).contains('..')) continue;
      final target = p.normalize(p.join(dirAbs, normalized));
      if (!p.isWithin(dirAbs, target)) continue;
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content as List<int>, flush: true);
      count++;
    }
    return count;
  }

  Future<void> deleteSave(SaveItem item, String gameId, String engineId) async {
    final f = File(item.absolutePath);
    if (f.existsSync()) await f.delete();
    // 清理因删除而变空的目录。
    var dir = f.parent;
    final base = saveDirFor(gameId, engineId).absolute.path;
    while (p.normalize(dir.path).length > base.length &&
        p.isWithin(base, dir.path)) {
      try {
        await dir.delete(); // 非空会抛异常，直接终止循环。
        dir = dir.parent;
      } on FileSystemException {
        break;
      }
    }
  }

  String _sanitize(String s) {
    final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return cleaned.isEmpty ? 'game' : cleaned;
  }
}
