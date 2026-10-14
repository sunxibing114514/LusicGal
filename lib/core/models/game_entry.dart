import 'dart:math';

import 'engine_id.dart';

/// 书库中的单个游戏条目。
class GameEntry {
  GameEntry({
    required this.id,
    required this.title,
    required this.engine,
    required this.path,
    required this.addedAt,
    this.engineDetail,
    this.lastPlayedAt,
    this.playedSeconds = 0,
    this.pathMissing = false,
  });

  final String id;
  String title;
  EngineId engine;

  /// 引擎细分（如 KEY 系下的 "RealLive" / "AVG32"）。
  String? engineDetail;

  /// 游戏文件所在目录（导入后位于 App 沙盒内）。
  String path;
  final DateTime addedAt;
  DateTime? lastPlayedAt;
  int playedSeconds;

  /// 文件丢失（用户手动删除了目录）。
  bool pathMissing;

  Map<String, Object> toJson() => {
        'id': id,
        'title': title,
        'engine': engine.id,
        'engineDetail': engineDetail,
        'path': path,
        'addedAt': addedAt.toIso8601String(),
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
        'playedSeconds': playedSeconds,
      };

  static GameEntry fromJson(Map<Object?, Object?> json) {
    final engineRaw = json['engine'];
    return GameEntry(
      id: json['id']! as String,
      title: json['title']! as String,
      engine: EngineId.fromId(engineRaw is String ? engineRaw : 'unknown'),
      engineDetail: json['engineDetail'] as String?,
      path: json['path']! as String,
      addedAt: DateTime.parse(json['addedAt']! as String),
      lastPlayedAt: json['lastPlayedAt'] == null
          ? null
          : DateTime.parse(json['lastPlayedAt']! as String),
      playedSeconds: (json['playedSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  /// 由导入时间 + 随机后缀生成的 id（不引入 uuid 依赖）。
  static String newId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random();
    var suffix = '';
    for (var i = 0; i < 6; i++) {
      suffix += alphabet[rng.nextInt(alphabet.length)];
    }
    return '$ts-$suffix';
  }

  /// 上次游玩的友好文案；空时长表示从未游玩。
  String get playedDisplay {
    if (playedSeconds < 60) return playedSeconds <= 0 ? '未游玩' : '$playedSeconds 秒';
    if (playedSeconds < 3600) return '${playedSeconds ~/ 60} 分钟';
    return '${(playedSeconds / 3600).toStringAsFixed(1)} 小时';
  }

  /// 引擎徽标文案（含细分）。
  String get engineBadge => engineDetail == null ? engine.label : '${engine.label} · $engineDetail';
}

/// 识别证据（可解释的检测结论）。
class DetectEvidence {
  const DetectEvidence(this.file, this.reason, this.weight);

  final String file;
  final String reason;
  final double weight;

  Map<String, Object> toJson() => {'file': file, 'reason': reason, 'weight': weight};
}

/// 一次识别的完整结论。
class DetectResult {
  const DetectResult({
    required this.engine,
    required this.evidence,
    this.engineDetail,
  });

  final EngineId engine;
  final String? engineDetail;
  final List<DetectEvidence> evidence;

  double get score => evidence.fold(0, (a, e) => a + e.weight);

  /// 证据分阈值：低于此值视为不可信。
  bool get confident => score >= 6;

  Map<String, Object> toReportJson() => {
        'engine': engine.id,
        'engineDetail': engineDetail,
        'score': score,
        'confident': confident,
        'evidence': evidence.map((e) => e.toJson()).toList(),
      };
}
