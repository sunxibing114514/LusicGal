import 'dart:io';

import 'package:path/path.dart' as p;

import '../detect/engine_detector.dart';
import '../models/engine_id.dart';
import '../models/game_entry.dart';
import 'library_store.dart';

/// 一个待导入的候选目录（扫描结果）。
class ImportCandidate {
  ImportCandidate({required this.dir, required this.displayName});

  final Directory dir;
  final String displayName;
}

/// 一次导入的结论。
class ImportSummary {
  ImportSummary({
    required this.imported,
    required this.detect,
    this.engine,
    this.engineDetail,
    this.error,
    this.gameId,
  });

  final bool imported;
  final DetectResult detect;
  final EngineId? engine;
  final String? engineDetail;
  final String? error;
  final String? gameId;

  /// 识别置信度不足且未强制指定引擎 → 需要 UI 让用户确认。
  bool get needsConfirmation => !imported && engine == null && error == null;
}

/// 游戏导入：扫描已知目录 / 复制单文件包 / 引用外部文件夹 三通道。
///
/// - 扫描通道：用户把游戏文件夹放入 App 专属目录（Android 的
///   `Android/data/com.lusicgal/files/`、iOS 的"文件"App 中的 LusicGal 目录），
///   dart:io 可直接读写，无需任何存储权限。
/// - 文件通道：系统选择器挑选单个封包（.xp3/.rpa/.nsa…）复制入库。
/// - 引用通道（addReferencedDirectory）：SAF 选任意文件夹，解析直路径后
///   原地游玩 —— 不复制、不搬移（Android 10 共享目录受限时不可用，UI 降级提示）。
class ImportService {
  ImportService({required this.store, required this.importRoots});

  final LibraryStore store;
  final List<Directory> importRoots;
  final EngineDetector detector = EngineDetector();

  /// 罗列所有导入根目录下的一级子目录（跳过隐藏目录与 games 库目录本身）。
  Future<List<ImportCandidate>> scan() async {
    final result = <ImportCandidate>[];
    for (final root in importRoots) {
      if (!root.existsSync()) continue;
      final gamesPath = store.gamesDir.path;
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final base = p.basename(entity.path);
        if (base.startsWith('.') || base == 'games' || base == 'saves' || base == 'export') {
          continue;
        }
        if (p.equals(entity.path, gamesPath)) continue;
        result.add(ImportCandidate(dir: entity, displayName: base));
      }
    }
    return result;
  }

  /// 预览识别结果（不落盘）。
  Future<DetectResult> previewDetect(String dirPath) async =>
      detector.detect(dirPath);

  /// 注册引用文件夹条目（即选即用：不复制、不搬移，直接指向用户文件夹）。
  ///
  /// 调用前提：[dirPath] 是当前可直读的目录（SAF 解析成功且 readable）。
  /// [folderUri] 为 SAF 树 URI（持久化授权凭证，重装后可凭其恢复）。
  Future<ImportSummary> addReferencedDirectory(
    Directory dir, {
    String? title,
    String? folderUri,
    EngineId? forceEngine,
    String? forceEngineDetail,
  }) async {
    final detect = detector.detect(dir.path);
    final engine = forceEngine ?? (detect.confident ? detect.engine : null);
    final detail = forceEngineDetail ?? detect.engineDetail;
    if (engine == null || engine == EngineId.unknown) {
      return ImportSummary(imported: false, detect: detect);
    }
    if (!dir.existsSync()) {
      return ImportSummary(imported: false, detect: detect, error: '目录不存在');
    }
    final entry = await store.addNew(
      title: (title ?? p.basename(dir.path)).trim(),
      engine: engine,
      engineDetail: detail,
      path: dir.path,
      sourceKind: 'folder',
      folderUri: folderUri,
    );
    return ImportSummary(
      imported: true,
      detect: detect,
      engine: engine,
      engineDetail: detail,
      gameId: entry.id,
    );
  }

  /// 导入整个目录：优先 rename（同分区瞬时完成），失败退化为递归复制。
  Future<ImportSummary> importDirectory(
    Directory source, {
    String? title,
    EngineId? forceEngine,
    String? forceEngineDetail,
  }) async {
    final detect = detector.detect(source.path);
    final engine = forceEngine ?? (detect.confident ? detect.engine : null);
    final detail = forceEngineDetail ?? detect.engineDetail;
    if (engine == null || engine == EngineId.unknown) {
      return ImportSummary(imported: false, detect: detect);
    }
    if (!source.existsSync()) {
      return ImportSummary(imported: false, detect: detect, error: '目录不存在');
    }

    final id = GameEntry.newId();
    final target = Directory(p.join(store.gamesDir.path, id));
    try {
      await store.gamesDir.create(recursive: true);
      try {
        await source.rename(target.path);
      } on FileSystemException {
        await _copyDir(source, target);
      }
    } on FileSystemException catch (e) {
      return ImportSummary(imported: false, detect: detect, error: e.message);
    }

    final entry = await store.addNew(
      title: (title ?? p.basename(source.path)).trim(),
      engine: engine,
      engineDetail: detail,
      path: target.path,
    );
    return ImportSummary(
      imported: true,
      detect: detect,
      engine: engine,
      engineDetail: detail,
      gameId: entry.id,
    );
  }

  /// 导入单个/多个封包文件（如 data.xp3、arc.nsa）。
  Future<ImportSummary> importFiles(
    List<File> files, {
    required String title,
    EngineId? forceEngine,
  }) async {
    if (files.isEmpty) {
      return ImportSummary(imported: false, detect: const DetectResult(
        engine: EngineId.unknown,
        evidence: [],
      ), error: '未选择文件');
    }
    final id = GameEntry.newId();
    final target = Directory(p.join(store.gamesDir.path, id));
    try {
      await target.create(recursive: true);
      for (final f in files) {
        await f.copy(p.join(target.path, p.basename(f.path)));
      }
    } on FileSystemException catch (e) {
      return ImportSummary(imported: false, detect: const DetectResult(
        engine: EngineId.unknown,
        evidence: [],
      ), error: e.message);
    }

    final detect = detector.detect(target.path);
    final engine = forceEngine ?? (detect.confident ? detect.engine : EngineId.unknown);
    final entry = await store.addNew(
      title: title.trim(),
      engine: engine,
      engineDetail: detect.engineDetail,
      path: target.path,
    );
    return ImportSummary(
      imported: true,
      detect: detect,
      engine: engine,
      engineDetail: detect.engineDetail,
      gameId: entry.id,
    );
  }

  /// 跨分区回退：递归复制目录（rename 同分区瞬时优先，此为失败兜底）。
  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final targetPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDir(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }
}
