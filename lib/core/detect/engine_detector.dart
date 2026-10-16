import 'dart:io';
import 'dart:math';

import '../models/engine_id.dart';
import '../models/game_entry.dart';

/// 基于纯文件特征的游戏引擎识别器。
///
/// 规则来源（证据链可解释）：
/// - KEY 系四引擎识别表逐条移植自 siglus_rs `crates/engine-detect/src/lib.rs`：
///   SiglusEngine ← `Scene.pck` / `Gameexe.dat`；
///   AVG32 ← `Gameexe.ini` + `PACL` 封包或 `TPC32` 散装场景；
///   RealLive ← `Gameexe.ini` + 10000 条目 `SEEN.TXT`（首场景头 0x1d0/0x1cc）；
///   UK2 ← `UK2.CFG` 或 `<< UK2 TEXT Ver1.00 >>` 魔数的 `.MES`。
/// - Ren'Py 的 RPA 魔数（`RPA-3.0 `）来自官方 renpy/loader.py。
/// - FVP（rfvp）：*.hcb 脚本 + *.nvsg 封包（rfvp 仓库 crates：hcb2lua / nvsg_pack）。
/// - SoftPAL（sena-rs）：*.pac 封包（crate：pal-pac-unpacker）。
/// - System 3.x（xsystem35-sdl2）：*.ald 封包。
/// - Kirikiri：XP3 封包魔数 `XP3\r\n\x1a\x8a`；ONScripter：`nscript.dat` / NSA 封包。
class EngineDetector {
  static const int maxDepth = 4;

  /// XP3 封包头：`XP3\r\n\x1a\x8a`。
  static const List<int> xp3Magic = [0x58, 0x50, 0x33, 0x0D, 0x0A, 0x1A, 0x8A];

  /// NScripter NSA 封包头：`NSA\0`。
  static const List<int> nsaMagic = [0x4E, 0x53, 0x41, 0x00];

  /// AVG32 场景封包头（siglus_rs engine-detect）。
  static const String avg32ArchiveMagic = 'PACL';

  /// AVG32 散装场景头（siglus_rs engine-detect）。
  static const String avg32SceneMagic = 'TPC32';

  /// UK2 文本魔数（siglus_rs engine-detect）。
  static const String uk2MesMagic = '<< UK2 TEXT Ver1.00 >>';

  /// RealLive 的 SEEN.TXT 目录条目数（siglus_rs engine-detect）。
  static const int realLiveTocEntries = 10000;

  /// RealLive 首场景头大小（旧 AVG2000 为 0x1cc）。
  static const int realLiveHeaderSize = 0x1d0;

  /// 对单个目录做识别。返回最高分引擎 + 全部证据（供导入界面改判）。
  DetectResult detect(String rootPath) {
    final root = Directory(rootPath);
    if (!root.existsSync()) {
      // 目录不存在：可能是文件条目（PSP 镜像）—— 走文件识别。
      if (File(rootPath).existsSync()) return detectFile(rootPath);
      return const DetectResult(engine: EngineId.unknown, evidence: []);
    }

    final ctx = _ScanContext();
    _scan(root, 0, ctx);

    final scores = <EngineId, double>{};
    final details = <EngineId, String?>{};
    void add(EngineId engine, String file, String reason, double weight,
        {String? detail}) {
      scores.update(engine, (v) => v + weight, ifAbsent: () => weight);
      ctx.evidence.add(DetectEvidence(file, reason, weight));
      if (engine == EngineId.siglus && detail != null) {
        details[engine] ??= detail;
      }
    }

    // ---- Kirikiri ----
    for (final path in ctx.byExtension['xp3'] ?? const <String>[]) {
      if (_hasBytesPrefix(path, xp3Magic)) {
        add(EngineId.kirikiri, _basename(path), 'XP3 封包（魔数校验通过）', 10);
      } else {
        add(EngineId.kirikiri, _basename(path), 'XP3 封包（按扩展名）', 7);
      }
    }
    if (ctx.fileNames.contains('startup.tjs')) {
      add(EngineId.kirikiri, 'startup.tjs', 'KrKr 启动脚本', 5);
    }
    final tjsCount = (ctx.byExtension['tjs'] ?? const []).length;
    if (tjsCount > 0) {
      add(EngineId.kirikiri, '*.tjs ×$tjsCount', 'TJS2 脚本', 3);
    }

    // ---- ONScripter ----
    if (ctx.fileNames.contains('nscript.dat')) {
      add(EngineId.onscripter, 'nscript.dat', 'NScripter 主脚本', 10);
    }
    for (final name in const ['0.txt', '00.txt']) {
      if (ctx.fileNames.contains(name)) {
        add(EngineId.onscripter, name, 'ONScripter 文本脚本', 6);
      }
    }
    for (final path in ctx.byExtension['nsa'] ?? const <String>[]) {
      if (_hasBytesPrefix(path, nsaMagic)) {
        add(EngineId.onscripter, _basename(path), 'NSA 封包（魔数校验通过）', 8);
      } else {
        add(EngineId.onscripter, _basename(path), 'NSA 封包（按扩展名）', 6);
      }
    }
    final sarCount = (ctx.byExtension['sar'] ?? const []).length;
    if (sarCount > 0) {
      add(EngineId.onscripter, '*.sar ×$sarCount', 'NScripter SAR 封包', 5);
    }

    // ---- Ren'Py ----
    for (final path in ctx.byExtension['rpa'] ?? const <String>[]) {
      if (_hasAsciiPrefix(path, 'RPA-')) {
        add(EngineId.renpy, _basename(path), 'RPA 归档（魔数校验通过）', 10);
      } else {
        add(EngineId.renpy, _basename(path), 'RPA 归档（按扩展名）', 7);
      }
    }
    if (ctx.dirNames.contains('renpy')) {
      add(EngineId.renpy, 'renpy/', "Ren'Py 运行时目录", 6);
    }
    final rpycCount = (ctx.byExtension['rpyc'] ?? const []).length;
    if (rpycCount > 0) {
      add(EngineId.renpy, '*.rpyc ×$rpycCount', "Ren'Py 编译脚本", 6);
    }

    // ---- KEY 系（siglus_rs engine-detect 规则） ----
    if (ctx.fileNames.contains('scene.pck')) {
      add(EngineId.siglus, 'Scene.pck', 'SiglusEngine 场景封包', 10, detail: 'SiglusEngine');
    }
    if (ctx.fileNames.contains('gameexe.dat')) {
      add(EngineId.siglus, 'Gameexe.dat', 'SiglusEngine 配置', 10, detail: 'SiglusEngine');
    }
    if (ctx.fileNames.contains('uk2.cfg')) {
      add(EngineId.siglus, 'UK2.CFG', 'UK2 配置', 10, detail: 'UK2');
    }
    if (ctx.hasUk2Mes) {
      add(EngineId.siglus, ctx.uk2MesPath ?? '*.mes', 'UK2 TEXT 魔数（<< UK2 TEXT Ver1.00 >>）', 10,
          detail: 'UK2');
    }
    final hasGameexeIni = ctx.fileNames.contains('gameexe.ini');
    final seenPath = ctx.seenPath;
    if (hasGameexeIni && seenPath != null) {
      if (_hasAsciiPrefix(seenPath, avg32ArchiveMagic)) {
        add(EngineId.siglus, _basename(seenPath), 'Gameexe.ini + PACL 场景封包 → AVG32', 10,
            detail: 'AVG32');
      } else if (_looksLikeRealLiveSeen(seenPath)) {
        add(EngineId.siglus, _basename(seenPath), 'Gameexe.ini + RealLive SEEN 目录（10000 条目）',
            10,
            detail: 'RealLive');
      } else if (ctx.hasSceneMagicTpc32) {
        add(EngineId.siglus, _basename(seenPath), 'Gameexe.ini + TPC32 场景 → AVG32', 9,
            detail: 'AVG32');
      }
    } else if (hasGameexeIni) {
      add(EngineId.siglus, 'Gameexe.ini', 'KEY 系配置（细分待定）', 3, detail: 'KEY 系');
    }

    // ---- FVP（rfvp） ----
    final hcbCount = (ctx.byExtension['hcb'] ?? const []).length;
    if (hcbCount > 0) {
      add(EngineId.rfvp, '*.hcb ×$hcbCount', 'FVP HCB 脚本', 8);
    }
    final nvsgCount = (ctx.byExtension['nvsg'] ?? const []).length;
    if (nvsgCount > 0) {
      add(EngineId.rfvp, '*.nvsg ×$nvsgCount', 'FVP NVSG 封包', 10);
    }

    // ---- SoftPAL（sena-rs） ----
    final pacCount = (ctx.byExtension['pac'] ?? const []).length;
    if (pacCount >= 1) {
      add(EngineId.sena, '*.pac ×$pacCount', 'SoftPAL PAC 封包', 6);
    }

    // ---- System 3.x（xsystem35-sdl2） ----
    final aldCount = (ctx.byExtension['ald'] ?? const []).length;
    if (aldCount > 0) {
      add(EngineId.xsystem35, '*.ald ×$aldCount', 'AliceSoft ALD 封包', 10);
    }

    // ---- Tyrano（TyranoScript / TyranoBuilder）----
    // Web 构建特征：tyrano.js 运行时 + data/ 下 .ks 脚本；
    // 桌面构建特征：Electron app.asar（根或 resources/）。
    final asarCount = (ctx.byExtension['asar'] ?? const []).length;
    if (asarCount > 0) {
      add(EngineId.tyrano, 'app.asar ×$asarCount', 'Electron 应用包（TyranoBuilder 桌面导出）', 9);
    }
    if (ctx.fileNames.contains('tyrano.js')) {
      add(EngineId.tyrano, 'tyrano.js', 'TyranoScript 运行时', 10);
    }
    final ksCount = (ctx.byExtension['ks'] ?? const []).length;
    if (ksCount > 0) {
      add(EngineId.tyrano, '*.ks ×$ksCount', 'TyranoScript 场景脚本', 6);
    }

    // ---- RPG Maker MV / MZ ----
    if (ctx.fileNames.contains('rpg_core.js')) {
      add(EngineId.rpgmv, 'js/rpg_core.js', 'RPG Maker MV 核心运行时', 10);
    }
    if (ctx.fileNames.contains('rmmz_core.js')) {
      add(EngineId.rpgmz, 'js/rmmz_core.js', 'RPG Maker MZ 核心运行时', 10);
    }
    if (ctx.fileNames.contains('plugins.js') && ctx.fileNames.contains('index.html')) {
      // MV/MZ 通用插件清单；不与核心冲突（核心引擎目录不会同时是 web 根）。
      add(EngineId.rpgmv, 'index.html + js/plugins.js', 'RPG 工程结构（MV 按核心文件细分）', 4);
    }

    // ---- PC（Windows 游戏 → winlator-cn 外置启动）----
    // 注意权重克制：多数引擎目录都附带 Windows 版启动器 exe，
    // 期望让位给更强的核心证据（rpa/xp3/ald…）。
    for (final path in (ctx.byExtension['exe'] ?? const <String>[]).take(3)) {
      if (_hasBytesPrefix(path, [0x4D, 0x5A])) {
        add(EngineId.pcwinlator, _basename(path), 'PE 可执行（MZ 魔数）', 6);
        break;
      }
    }

    // ---- 汇总：取最高分；证据全量保留（供 UI 手动改判） ----
    if (scores.isEmpty) {
      return DetectResult(engine: EngineId.unknown, evidence: ctx.evidence);
    }
    final best =
        scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return DetectResult(
      engine: best.key,
      engineDetail: best.key == EngineId.siglus ? details[EngineId.siglus] : null,
      evidence: ctx.evidence,
    );
  }

  // ----------------------------------------------------------------------

  /// 对单个文件做识别（PSP 镜像条目：iso / cso / pbp / chd）。
  /// 协议参考：PPSSPP 的 UMD 镜像（ISO9660/UDF + CSO 压缩 + PBP 打包）。
  DetectResult detectFile(String filePath) {
    final f = File(filePath);
    if (!f.existsSync()) {
      return const DetectResult(engine: EngineId.unknown, evidence: []);
    }
    final base = _basename(filePath);
    final dot = base.lastIndexOf('.');
    final ext = dot > 0 ? base.substring(dot + 1).toLowerCase() : '';

    final evidence = <DetectEvidence>[];
    void add(String reason, double weight) =>
        evidence.add(DetectEvidence(base, reason, weight));

    switch (ext) {
      case 'iso':
        // ISO9660 卷描述符 "CD001" @ 0x8001（PSP UMD 也用它）。
        if (_hasBytesPrefixAt(filePath, 0x8001, 'CD001')) {
          add('光盘镜像（ISO9660 魔数校验通过）', 10);
          break;
        }
        add('ISO 镜像（按扩展名）', 6);
        break;
      case 'cso':
        if (_hasBytesPrefixAt(filePath, 0, 'CISO')) {
          add('CSO 压缩镜像（CISO 魔数校验通过）', 10);
          break;
        }
        add('CSO 压缩镜像（按扩展名）', 6);
        break;
      case 'pbp':
        if (_hasBytesPrefixAt(filePath, 0, '\u0000PBP')) {
          add('PBP 打包镜像（PBP 魔数校验通过）', 10);
          break;
        }
        add('PBP 打包镜像（按扩展名）', 6);
        break;
      case 'chd':
        // PPSSPP ≥ v1.13 支持 CHD；MAME CHD 头 "MAMECHD"。
        add('CHD 压缩镜像（PPSSPP 支持）', 7);
        break;
      case 'exe':
        if (_hasBytesPrefixAt(filePath, 0, 'MZ')) {
          add('PE 可执行（MZ 魔数）→ PC 条目建议手动指定目录', 4);
        }
        break;
      default:
        return const DetectResult(engine: EngineId.unknown, evidence: []);
    }
    return DetectResult(
      engine: ext == 'exe' ? EngineId.pcwinlator : EngineId.psp,
      evidence: evidence,
    );
  }

  /// 读取 [offset] 处的 ASCII 前缀比较。
  static bool _hasBytesPrefixAt(String path, int offset, String magic) {
    try {
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() < offset + magic.length) {
        return false;
      }
      final raf = f.openSync();
      try {
        raf.setPositionSync(offset);
        final bytes = raf.readSync(magic.length);
        return String.fromCharCodes(bytes).startsWith(magic);
      } finally {
        raf.closeSync();
      }
    } on Exception {
      return false;
    }
  }

  void _scan(Directory dir, int depth, _ScanContext ctx) {
    if (depth > maxDepth) return;
    final List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in children) {
      if (ctx.fileCount > 4000) return;
      if (entity is Directory) {
        final base = _basename(entity.path);
        if (base.startsWith('.') || base == '__MACOSX') continue;
        ctx.dirNames.add(base.toLowerCase());
        _scan(entity, depth + 1, ctx);
      } else if (entity is File) {
        final base = _basename(entity.path);
        ctx.fileCount++;
        final dot = base.lastIndexOf('.');
        if (dot <= 0 || dot == base.length - 1) {
          ctx.fileNames.add(base.toLowerCase());
          continue;
        }
        final ext = base.substring(dot + 1).toLowerCase();
        final nameLower = base.toLowerCase();
        ctx.byExtension.putIfAbsent(ext, () => <String>[]).add(entity.path);
        ctx.fileNames.add(nameLower);
        if (nameLower == 'seen.txt') {
          ctx.seenPath ??= entity.path;
        }
        if (ext == 'mes' && _fileStartsWith(entity.path, uk2MesMagic)) {
          ctx.hasUk2Mes = true;
          ctx.uk2MesPath ??= entity.path;
        }
        if (ext == 'txt' && _fileStartsWith(entity.path, avg32SceneMagic)) {
          ctx.hasSceneMagicTpc32 = true;
        }
      }
    }
  }

  String _basename(String path) {
    final i = max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    return i < 0 ? path : path.substring(i + 1);
  }

  /// 读文件前若干字节与二进制魔数比较。
  static bool _hasBytesPrefix(String path, List<int> magic) {
    try {
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() < magic.length) return false;
      final raf = f.openSync();
      try {
        final bytes = raf.readSync(magic.length);
        for (var i = 0; i < magic.length; i++) {
          if (bytes[i] != magic[i]) return false;
        }
        return true;
      } finally {
        raf.closeSync();
      }
    } on Exception {
      return false;
    }
  }

  /// 读文件前缀并比较 ASCII 魔数。
  static bool _hasAsciiPrefix(String path, String magic) =>
      _fileStartsWith(path, magic);

  /// 读文件头 64KB 内是否以 [prefix] 开头。
  static bool _fileStartsWith(String path, String prefix) {
    try {
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() < prefix.length) return false;
      final raf = f.openSync();
      try {
        final bytes = raf.readSync(prefix.length);
        return String.fromCharCodes(bytes).startsWith(prefix);
      } finally {
        raf.closeSync();
      }
    } on Exception {
      return false;
    }
  }

  /// RealLive 的 SEEN.TXT：小端 u32 目录条目数 == 10000，
  /// 首条目偏移处的场景头大小为 0x1d0（或旧 AVG2000 的 0x1cc）。
  static bool _looksLikeRealLiveSeen(String path) {
    try {
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() < 12) return false;
      final raf = f.openSync();
      try {
        final header = raf.readSync(8);
        final entries = header[0] |
            (header[1] << 8) |
            (header[2] << 16) |
            (header[3] << 24);
        if (entries != realLiveTocEntries) return false;
        final offset = header[4] |
            (header[5] << 8) |
            (header[6] << 16) |
            (header[7] << 24);
        if (offset <= 0 || offset >= f.lengthSync()) return false;
        raf.setPositionSync(offset);
        final scene = raf.readSync(4);
        final sceneHeader = scene[0] |
            (scene[1] << 8) |
            (scene[2] << 16) |
            (scene[3] << 24);
        return sceneHeader == realLiveHeaderSize || sceneHeader == 0x1cc;
      } finally {
        raf.closeSync();
      }
    } on Exception {
      return false;
    }
  }
}

class _ScanContext {
  /// 扩展名 → 完整路径列表（小写扩展名）。
  final Map<String, List<String>> byExtension = {};
  final Set<String> fileNames = {};
  final Set<String> dirNames = {};
  final List<DetectEvidence> evidence = [];
  String? seenPath;
  bool hasUk2Mes = false;
  String? uk2MesPath;
  bool hasSceneMagicTpc32 = false;
  int fileCount = 0;
}
