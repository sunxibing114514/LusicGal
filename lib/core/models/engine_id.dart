/// LusicGal 支持的引擎类型与元数据。
///
/// 核心库命名约定：`liblusicgal_<id>.so`（Android）/ `lusicgal_<id>` 静态符号前缀（iOS）。
///
/// 两种引擎形态（docs/ARCHITECTURE.md「条目模型」；2026-10 用户指令：
/// 移除 PSP/PC/应用三个外板条目，全部引擎 App 内直接游玩）：
/// - [isCore]：ABI v2 原生核心（8 个，dlsym 桥派发）。
/// - [isWebGame]：内置 WebView 跑法（Tyrano / RPG MV / MZ）—— 本地 HTTP 注入。
/// 两类 [coreLibName] 语义不变；Web 引擎为空 —— 不经核心库装载。
enum EngineId {
  kirikiri('kirikiri', 'Kirikiri', '吉里吉里 / KAG（*.xp3）', 'liblusicgal_kirikiri'),
  onscripter('onscripter', 'ONScripter', 'NScripter 系（nscript.dat / arc.nsa）', 'liblusicgal_onscripter'),
  renpy('renpy', "Ren'Py", "Ren'Py（*.rpa / renpy/）", 'liblusicgal_renpy'),
  siglus('siglus', 'KEY 系', 'Siglus / RealLive / AVG32 / UK2', 'liblusicgal_siglus'),
  rfvp('rfvp', 'Rfvp', 'FVP 引擎（*.hcb / *.nvsg）', 'liblusicgal_rfvp'),
  sena('sena', 'Sena', 'SoftPAL 引擎（*.pac）', 'liblusicgal_sena'),
  xsystem35('xsystem35', 'System 3.x', 'AliceSoft（*.ald）', 'liblusicgal_xsystem35'),
  artemis('artemis', 'Artemis', 'minori 系（手动指定）', 'liblusicgal_artemis'),
  // ---- Web 引擎（内置 WebView + 本地 HTTP 注入跑法）----
  tyrano('tyrano', 'Tyrano', 'TyranoScript / TyranoBuilder（index.html / app.asar）', ''),
  rpgmv('rpgmv', 'RPG Maker MV', 'RPG ツクール MV（js/rpg_core.js）', ''),
  rpgmz('rpgmz', 'RPG Maker MZ', 'RPG ツクール MZ（js/rmmz_core.js）', ''),
  unknown('unknown', '未知', '未识别', '');

  const EngineId(this.id, this.label, this.description, this.coreLibName);

  /// 稳定字符串 id（跨平台通道 / 存储使用）。
  final String id;

  /// 展示名。
  final String label;

  /// 中文描述（UI 副标题）。
  final String description;

  /// Android 侧核心动态库名（System.loadLibrary 参数）；空 = 非核心形态。
  final String coreLibName;

  /// ABI v2 原生核心形态。
  bool get isCore => coreLibName.isNotEmpty;

  /// 内置 WebView 跑法（本地 HTTP 服务 + hook 注入）。
  bool get isWebGame => id == 'tyrano' || id == 'rpgmv' || id == 'rpgmz';

  /// 启动后游戏脱离本页全屏运行，播放器页应自动让位
  ///（Ren'Py Route B 与 Web 全屏页同模式）。
  bool get isOutboard => id == 'renpy' || isWebGame;

  static EngineId fromId(String id) =>
      EngineId.values.firstWhere((e) => e.id == id, orElse: () => EngineId.unknown);
}
