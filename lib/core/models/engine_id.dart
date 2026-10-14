/// LusicGal 支持的引擎类型与元数据。
///
/// 核心库命名约定：`liblusicgal_<id>.so`（Android）/ `lusicgal_<id>` 静态符号前缀（iOS）。
enum EngineId {
  kirikiri('kirikiri', 'Kirikiri', '吉里吉里 / KAG（*.xp3）', 'liblusicgal_kirikiri'),
  onscripter('onscripter', 'ONScripter', 'NScripter 系（nscript.dat / arc.nsa）', 'liblusicgal_onscripter'),
  renpy('renpy', "Ren'Py", "Ren'Py（*.rpa / renpy/）", 'liblusicgal_renpy'),
  siglus('siglus', 'KEY 系', 'Siglus / RealLive / AVG32 / UK2', 'liblusicgal_siglus'),
  rfvp('rfvp', 'Rfvp', 'FVP 引擎（*.hcb / *.nvsg）', 'liblusicgal_rfvp'),
  sena('sena', 'Sena', 'SoftPAL 引擎（*.pac）', 'liblusicgal_sena'),
  xsystem35('xsystem35', 'System 3.x', 'AliceSoft（*.ald）', 'liblusicgal_xsystem35'),
  artemis('artemis', 'Artemis', 'minori 系（手动指定）', 'liblusicgal_artemis'),
  unknown('unknown', '未知', '未识别', '');

  const EngineId(this.id, this.label, this.description, this.coreLibName);

  /// 稳定字符串 id（跨平台通道 / 存储使用）。
  final String id;

  /// 展示名。
  final String label;

  /// 中文描述（UI 副标题）。
  final String description;

  /// Android 侧核心动态库名（System.loadLibrary 参数）。
  final String coreLibName;

  static EngineId fromId(String id) =>
      EngineId.values.firstWhere((e) => e.id == id, orElse: () => EngineId.unknown);
}
