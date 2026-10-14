import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/engine_id.dart';
import '../models/game_entry.dart';

/// 游戏书库：JSON 原子持久化（tmp + rename），[ChangeNotifier] 驱动 UI。
class LibraryStore extends ChangeNotifier {
  LibraryStore({required this.root}) {
    _file = File(p.join(root.path, 'library.json'));
  }

  /// App Documents 目录（注入以便测试）。
  final Directory root;
  late final File _file;

  final List<GameEntry> _games = [];

  /// 导入的游戏文件所在根目录。
  Directory get gamesDir => Directory(p.join(root.path, 'games'));

  List<GameEntry> get games => List.unmodifiable(_games);

  GameEntry? byId(String id) {
    for (final g in _games) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// 从磁盘载入；不存在时创建空库。
  Future<void> load() async {
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    if (!_file.existsSync()) {
      _games.clear();
      notifyListeners();
      return;
    }
    try {
      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _games
        ..clear()
        ..addAll(decoded
            .whereType<Map>()
            .map((m) => GameEntry.fromJson(m.cast<Object?, Object?>())));
    } on FormatException {
      // 损坏的库文件：保留空库而不是崩溃。
      _games.clear();
    }
    await refreshPathStatus();
  }

  /// 校验各游戏目录是否仍在原处。
  Future<void> refreshPathStatus() async {
    var changed = false;
    for (final g in _games) {
      final desired = !Directory(g.path).existsSync();
      if (g.pathMissing != desired) {
        g.pathMissing = desired;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _persist() async {
    final payload = jsonEncode(_games.map((g) => g.toJson()).toList());
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(_file.path);
  }

  /// 新增条目（调用方保证文件已就位）。
  Future<GameEntry> addNew({
    required String title,
    required EngineId engine,
    required String path,
    String? engineDetail,
  }) async {
    final entry = GameEntry(
      id: GameEntry.newId(),
      title: title,
      engine: engine,
      engineDetail: engineDetail,
      path: path,
      addedAt: DateTime.now(),
    );
    _games.add(entry);
    await _persist();
    notifyListeners();
    return entry;
  }

  Future<void> rename(String id, String newTitle) async {
    final g = byId(id);
    if (g == null) return;
    g.title = newTitle;
    await _persist();
    notifyListeners();
  }

  Future<void> setEngine(String id, EngineId engine, String? detail) async {
    final g = byId(id);
    if (g == null) return;
    g.engine = engine;
    g.engineDetail = detail;
    await _persist();
    notifyListeners();
  }

  /// 移除条目；[deleteFiles] 同时删除游戏文件目录。
  Future<void> remove(String id, {required bool deleteFiles}) async {
    final g = byId(id);
    if (g == null) return;
    _games.remove(g);
    if (deleteFiles) {
      final dir = Directory(g.path);
      if (dir.existsSync()) {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // 文件已被外部移除等 —— 忽略。
        }
      }
    }
    // 存档目录保留（用户可能之后重新导入同名游戏）。
    await _persist();
    notifyListeners();
  }

  /// 记录一次游玩（叠加时长 + 刷新最近游玩时间）。
  Future<void> recordPlay(String id, Duration duration) async {
    final g = byId(id);
    if (g == null) return;
    g.playedSeconds += duration.inSeconds;
    g.lastPlayedAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  @visibleForTesting
  List<GameEntry> get debugGames => _games;
}
