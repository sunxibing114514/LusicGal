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

/// 游戏导入：扫描已知目录 / 复制单文件包双通道。
///
/// - 扫描通道：用户把游戏文件夹放入 App 专属目录（Android 的
///   `Android/data/com.lusicgal/files/`、iOS 的"文件"App 中的 LusicGal 目录），
///   dart:io 可直接读写，无需任何存储权限。
/// - 文件通道：系统选择器挑选单个封包（.xp3/.rpa/.nsa…）复制入库。
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

  /// 导入整个目录：优先 rename（同分区瞬时完成），失败退化为递归复制。
  Future<ImportSummary> importDirectory(
    Directory source, {
    String? title,
    EngineId? forceEngine,
    String? forceEngineDetail,
  }) async {
    final detect = detector.detect(source.path);
    final engine = forceEngine ?? (detect.confident ? detect.engine : null);
    var detail = forceEngineDetail ?? detect.engineDetail;
    if (engine == EngineId.pcwinlator && (detail == null || detail.isEmpty)) {
      // PC 条目：自动挑选目录顶层的 PE 启动器。
      detail = pickLauncherExe(source);
    }
    if (engine == null || engine == EngineId.unknown) {
      return ImportSummary(imported: false, detect: detect);
    }
    if (!source.existsSync()) {
      return ImportSummary(imported: false, detect: detect, error: '目录不存在');
    }
    if (engine == EngineId.pcwinlator) {
      // 原位条目：winlator-cn 按本机路径把目录挂进容器（独立 UID 读取），
      // 沙盒内目录必然挂载失败 —— 不搬进沙盒，路径原样引用；若目录在
      // 应用私有区，启动侧 DIR_NOT_SHARED 守卫会给出迁移指引。
      final entry = await store.addNew(
        title: (title ?? p.basename(source.path)).trim(),
        engine: engine,
        engineDetail: detail,
        path: source.path,
      );
      return ImportSummary(
        imported: true,
        detect: detect,
        engine: engine,
        engineDetail: detail,
        gameId: entry.id,
      );
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

  /// 导入 PSP 镜像条目（单个 iso/cso/pbp/chd 文件复制入库；
  /// 启动时经 PPSSPP 外板拉起）。
  Future<ImportSummary> importPspFile(File file, {String? title}) async {
    final detect = detector.detectFile(file.path);
    if (detect.engine != EngineId.psp) {
      return ImportSummary(imported: false, detect: detect, error: '不是 PSP 镜像（iso/cso/pbp/chd）');
    }
    if (!file.existsSync()) {
      return ImportSummary(imported: false, detect: detect, error: '文件不存在');
    }
    final id = GameEntry.newId();
    try {
      await store.gamesDir.create(recursive: true);
      // 镜像体积可能数 GB：优先 rename（同分区瞬时），失败退化为复制。
      final target = File(p.join(store.gamesDir.path, id, p.basename(file.path)));
      await target.parent.create(recursive: true);
      try {
        await file.rename(target.path);
      } on FileSystemException {
        await file.copy(target.path);
      }
      final entry = await store.addNew(
        title: (title ?? p.basenameWithoutExtension(file.path)).trim(),
        engine: EngineId.psp,
        path: target.path,
      );
      return ImportSummary(
        imported: true,
        detect: detect,
        engine: EngineId.psp,
        gameId: entry.id,
      );
    } on FileSystemException catch (e) {
      return ImportSummary(imported: false, detect: detect, error: e.message);
    }
  }

  /// 添加 Android 应用条目（不复制任何文件；path = 包名）。
  Future<ImportSummary> addAppEntry({
    required String packageName,
    required String label,
  }) async {
    // 注：evidence 含包名插值 → 非 const 构造。
    final detect = DetectResult(
      engine: EngineId.androidapp,
      evidence: [DetectEvidence('app:$packageName', '已安装应用条目', 10)],
    );
    final entry = await store.addNew(
      title: label.trim().isEmpty ? packageName : label.trim(),
      engine: EngineId.androidapp,
      path: packageName,
    );
    return ImportSummary(
      imported: true,
      detect: detect,
      engine: EngineId.androidapp,
      gameId: entry.id,
    );
  }

  /// 添加 PC 条目（原位引用公共存储目录，不复制 —— winlator-cn 按本机
  /// 路径挂载容器，目录必须可被其独立 UID 读取）。
  Future<ImportSummary> addPcEntryInPlace({
    required Directory dir,
    String? title,
  }) async {
    if (!dir.existsSync()) {
      return ImportSummary(
        imported: false,
        detect: const DetectResult(engine: EngineId.unknown, evidence: []),
        error: '目录不存在',
      );
    }
    final detect = detector.detect(dir.path);
    final exe = pickLauncherExe(dir);
    if (exe == null) {
      return ImportSummary(
        imported: false,
        detect: detect,
        error: '目录内未找到 .exe 启动器',
      );
    }
    final entry = await store.addNew(
      title: (title ?? p.basename(dir.path)).trim(),
      engine: EngineId.pcwinlator,
      engineDetail: exe,
      path: dir.path,
    );
    return ImportSummary(
      imported: true,
      detect: detect,
      engine: EngineId.pcwinlator,
      engineDetail: exe,
      gameId: entry.id,
    );
  }

  /// PC 条目（winlator-cn）：挑选启动 exe（顶层优先，一层子目录兜底；
  /// 协议接受相对 dir_path 的路径）。名含 game/start/launch 优先。
  static String? pickLauncherExe(Directory dir) {
    try {
      // 返回 [scanRoot] 下 .exe 的相对路径（可能只是文件名）。
      String? pickFrom(Directory scanRoot, bool subScan) {
        final exes = scanRoot
            .listSync(followLinks: false)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.exe'))
            .toList();
        if (exes.isEmpty) return null;
        for (final f in exes) {
          final b = p.basename(f.path).toLowerCase();
          if (b.contains('game') || b.contains('start') || b.contains('launch')) {
            return subScan
                ? '${p.basename(scanRoot.path)}/${p.basename(f.path)}'
                : p.basename(f.path);
          }
        }
        return subScan
            ? '${p.basename(scanRoot.path)}/${p.basename(exes.first.path)}'
            : p.basename(exes.first.path);
      }

      final top = pickFrom(dir, false);
      if (top != null) return top;
      // 一层子目录兜底（bin/、Game/ 等惯例）。
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is Directory) {
          final found = pickFrom(entity, true);
          if (found != null) return found;
        }
      }
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDir(entity, Directory(p.join(dst.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(dst.path, name));
      } else if (entity is Link) {
        final link = Link(p.join(dst.path, name));
        await link.create(await entity.target(), recursive: false);
      }
    }
  }
}
