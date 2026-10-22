import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/library/import_service.dart';
import '../../core/library/library_store.dart';
import '../../core/models/engine_id.dart';
import '../../core/models/game_entry.dart';
import '../../engine/engine_host.dart';
import '../ui_helpers.dart';

/// 打开导入面板：扫描 App 专属目录的候选文件夹 / 系统选择器挑封包文件。
Future<void> showImportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const ImportSheet(),
  );
}

class ImportSheet extends StatefulWidget {
  const ImportSheet({super.key});

  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<ImportSheet> {
  late Future<List<ImportCandidate>> _scanFuture;
  bool _busy = false;

  ImportService get _import => context.read<ImportService>();
  LibraryStore get _store => context.read<LibraryStore>();

  @override
  void initState() {
    super.initState();
    _scanFuture = _import.scan();
  }

  void _rescan() {
    setState(() {
      _scanFuture = _import.scan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('导入游戏', style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                '首选"选择游戏文件夹"：直接指向你放游戏的位置，即选即玩、不复制入库。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            // 即选即用主通道：SAF 选文件夹 → 解析直路径 → 原地登记（不复制）。
            FilledButton.icon(
              onPressed: _busy ? null : _pickFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择游戏文件夹（不复制，即选即玩）'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                '支持共享目录（Download 等）与 App 专属目录，全系统版本即选即玩。'
                '可选游戏文件夹，或选"游戏总目录"——会列出其下识别到的各游戏'
                '子文件夹，勾选批量收录。首次选择时会请求存储权限，请选择"允许"。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
              ),
            ),
            const Divider(height: 24),
            Text('或从 App 专属目录扫描', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Flexible(
              child: FutureBuilder<List<ImportCandidate>>(
                future: _scanFuture,
                builder: (context, snapshot) {
                  final candidates = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (candidates == null || candidates.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '未在专属目录发现游戏文件夹。\n放入后点击"重新扫描"。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final c = candidates[i];
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(c.displayName),
                        subtitle: const Text('点击导入到书库'),
                        trailing: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                        onTap: _busy ? null : () => _importDirectory(c),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _rescan,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新扫描'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _pickFiles,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('选择封包文件'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// 根级强特征：游戏本体的主特征文件必在自身根上（data.xp3、nscript.dat、
  /// tyrano.js、Scene.pck、*.rpa 所在的 game/ 属例外——由内部目录名单兜底）。
  /// 必须先于递归探测判断：总目录的子游戏证据会污染根目录自身的
  /// detect 结论（v0.1.5 现机实测病根——根目录递归扫到子游戏后 confident，
  /// 单条分支吞掉批量清单）。
  static final RegExp _strongRootFile = RegExp(
    r'^('
    r'.*\.xp3|.*\.nsa|.*\.rpa|.*\.ald|.*\.nvsg|.*\.hcb|.*\.pac|'
    r'nscript\.dat|0\.txt|00\.txt|tyrano\.js|app\.asar|scene\.pck|'
    r'gameexe\.dat|gameexe\.ini|uk2\.cfg|seen\.txt|startup\.tjs|'
    r'rpg_core\.js|rmmz_core\.js|plugins\.js'
    r')$',
    caseSensitive: false,
  );

  /// 引擎运行时/资源目录名：出现在游戏本体内部的子目录（renpy 的 game/、
  /// RPGMV 的 js/、补丁目录等）。总目录语义下这些目录即使被识别出
  /// 游戏特征也不是独立游戏。
  static const Set<String> _internalDirNames = {
    'game', 'games', 'js', 'data', 'tyrano', 'www', 'resources', 'audio',
    'movies', 'video', 'bgm', 'save', 'savedata', 'system', 'plugin',
    'plugins', 'patch', 'patchs', 'update', 'updates', 'renpy', 'env',
    'font', 'fonts', 'image', 'images', 'bgimage', 'cg', 'scenario',
    'sound', 'voice', 'system40', 'others',
  };

  /// SAF 选择文件夹（用户指令：读取该文件夹下的文件夹）：
  /// - 根上有强特征文件（游戏本体）→ 单条收录；
  /// - 否则视为"游戏总目录"：一级子文件夹逐个识别（未识别的非空子文件夹
  ///   再探其一级子文件夹＝二级兜底），识别到游戏的进批量勾选清单，
  ///   未识别的非空子文件夹也列出（勾选后逐个手动指定引擎）。
  Future<void> _pickFolder() async {
    final host = context.read<EngineHost>();
    final picked = await host.pickGameFolder();
    if (!mounted) return;
    if (!picked.ok) {
      // 用户取消（无 message 差异）静默；真实失败给出原因。
      if (picked.message != null && picked.message != '已取消') {
        _toast(picked.message!);
      }
      return;
    }
    if (picked.path == null || !picked.readable) {
      _toast(
        picked.message ?? '该文件夹无法直接读取，请移入 App 专属目录后扫描导入。',
      );
      return;
    }
    final root = Directory(picked.path!);
    final rootName = picked.name ?? p.basename(root.path);

    // 1) 根级强特征 → 游戏本体语义（最常见：直接选了某个游戏的文件夹）。
    var rootIsGame = false;
    try {
      for (final e in root.listSync(followLinks: false)) {
        if (e is File && _strongRootFile.hasMatch(p.basename(e.path))) {
          rootIsGame = true;
          break;
        }
      }
    } catch (_) {}
    if (rootIsGame) {
      await _addReferenced(root, rootName, picked.uri);
      return;
    }
    if (!mounted) return;

    // 2) 总目录语义：扫一级（+二级兜底）子文件夹。
    final confidentDirs = <Directory, DetectResult>{};
    final manualDirs = <Directory>[];
    try {
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final base = p.basename(entity.path);
        if (base.startsWith('.')) continue;
        if (_internalDirNames.contains(base.toLowerCase())) continue;
        final d = await _import.previewDetect(entity.path);
        if (d.confident) {
          confidentDirs[entity] = d;
        } else {
          // 二级兜底："合集名/游戏名/游戏本体"结构。
          var subHit = false;
          try {
            for (final e2 in entity.listSync(followLinks: false)) {
              if (e2 is! Directory) continue;
              final base2 = p.basename(e2.path);
              if (base2.startsWith('.') ||
                  _internalDirNames.contains(base2.toLowerCase())) {
                continue;
              }
              final d2 = await _import.previewDetect(e2.path);
              if (d2.confident) {
                confidentDirs[e2] = d2;
                subHit = true;
              }
            }
          } catch (_) {}
          if (!subHit && _dirNonEmpty(entity)) manualDirs.add(entity);
        }
      }
    } catch (_) {}
    if (!mounted) return;

    // 3) 特征在内部子目录的单游戏布局（renpy 的 game/、RPGMV 的 js/）：
    // 没有任何"非内部目录名"的自信子文件夹，而根递归探测自信 → 单游戏。
    if (confidentDirs.isEmpty && manualDirs.isEmpty) {
      final rootDetect = await _import.previewDetect(root.path);
      if (!mounted) return;
      if (rootDetect.confident) {
        await _addReferenced(root, rootName, picked.uri);
        return;
      }
      // 什么都没有 → 询问是否整夹收录（手动指定引擎）。
      final doAdd = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('未在「$rootName」下发现游戏'),
          content: const Text(
            '没有识别到任何游戏特征。可将整个文件夹作为单一游戏收录，'
            '稍后在详情面板手动指定引擎。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('整个文件夹收录'),
            ),
          ],
        ),
      );
      if (doAdd == true) await _addReferenced(root, rootName, picked.uri);
      return;
    }

    // 4) 批量勾选 → 收录。
    final chosen = await _batchPickDialog(rootName, confidentDirs, manualDirs);
    if (chosen == null || chosen.isEmpty) return;
    setState(() => _busy = true);
    var ok = 0;
    var skipped = 0;
    for (final item in chosen) {
      EngineId? force;
      if (item.detect == null) {
        if (!mounted) break;
        force = await _pickEngineDialog();
        if (force == null) {
          skipped++;
          continue;
        }
      }
      final s = await _import.addReferencedDirectory(
        item.dir,
        title: p.basename(item.dir.path),
        folderUri: picked.uri,
        forceEngine: force,
      );
      if (s.imported) ok++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _rescan();
    Navigator.of(context).pop();
    _toast(ok > 0
        ? '已从「$rootName」收录 $ok 个游戏'
        '${skipped > 0 ? '（跳过 $skipped 个）' : ''}· 引用不复制'
        : '未收录任何游戏');
  }

  bool _dirNonEmpty(Directory d) {
    try {
      return d.listSync(followLinks: false).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 单目录收录（引用登记；不 confident 时弹引擎确认）。
  Future<void> _addReferenced(
    Directory dir,
    String? title,
    String? folderUri,
  ) async {
    setState(() => _busy = true);
    var summary = await _import.addReferencedDirectory(
      dir,
      title: title,
      folderUri: folderUri,
    );
    if (summary.needsConfirmation && mounted) {
      final engine = await _pickEngineDialog();
      if (engine == null) {
        setState(() => _busy = false);
        return;
      }
      summary = await _import.addReferencedDirectory(
        dir,
        title: title,
        folderUri: folderUri,
        forceEngine: engine,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (summary.imported) {
      Navigator.of(context).pop();
      _toast('已收录《${_store.byId(summary.gameId ?? '')?.title}》'
          '（${summary.engineDetail ?? summary.engine?.label}· 引用文件夹）');
    } else {
      _toast(summary.error ?? '未能识别引擎类型，可稍后在详情面板手动指定。');
    }
  }

  /// 游戏总目录批量勾选：识别到游戏的子文件夹（默认全选）＋
  /// 未识别的非空子文件夹（默认不选，勾选后逐个手动指定引擎）。
  Future<List<_PickedSub>?> _batchPickDialog(
    String rootName,
    Map<Directory, DetectResult> confidentDirs,
    List<Directory> manualDirs,
  ) {
    final checked = <_PickedSub, bool>{};
    for (final e in confidentDirs.entries) {
      checked[_PickedSub(e.key, e.value)] = true;
    }
    for (final d in manualDirs) {
      checked[_PickedSub(d, null)] = false;
    }
    return showDialog<List<_PickedSub>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text('「$rootName」下发现 ${checked.length} 个文件夹'),
          content: SizedBox(
            width: 320,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final entry in checked.entries)
                  CheckboxListTile(
                    dense: true,
                    value: entry.value,
                    title: Text(
                      p.basename(entry.key.dir.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      entry.key.detect == null
                          ? '未识别 —— 勾选后手动指定引擎'
                          : (entry.key.detect!.engineDetail ??
                              entry.key.detect!.engine.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (v) =>
                        setDialog(() => checked[entry.key] = v ?? false),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                checked.entries
                    .where((e) => e.value)
                    .map((e) => e.key)
                    .toList(),
              ),
              child: Text(
                '收录所选（${checked.values.where((v) => v).length}）',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importDirectory(ImportCandidate candidate) async {
    setState(() => _busy = true);    var summary = await _import.importDirectory(candidate.dir);
    var engine = summary.engine;
    if (summary.needsConfirmation && mounted) {
      final picked = await _pickEngineDialog();
      if (picked == null) {
        setState(() => _busy = false);
        return;
      }
      summary = await _import.importDirectory(
        candidate.dir,
        forceEngine: picked,
      );
      engine = summary.engine;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (summary.imported) {
      _rescan();
      Navigator.of(context).pop();
      _toast('已导入《${_store.byId(summary.gameId ?? '')?.title}》'
          '（${summary.engineDetail ?? engine?.label}）');
    } else {
      _toast(summary.error ?? '未能识别引擎类型，可稍后在详情面板手动指定。');
    }
  }

  Future<void> _pickFiles() async {
    // file_picker 13.x：静态方法、恒返回列表（空=取消），默认即多选。
    final picked = await FilePicker.pickFiles();
    final paths = picked.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    setState(() => _busy = true);
    final title = p.basenameWithoutExtension(paths.first);
    final summary = await _import.importFiles(
      paths.map(File.new).toList(),
      title: title,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (summary.imported) {
      Navigator.of(context).pop();
      _toast(
        summary.engine == EngineId.unknown
            ? '已导入，但未能确定引擎 —— 请在详情面板手动指定。'
            : '已导入《$title》（${summary.engineDetail ?? summary.engine?.label}）',
      );
    } else {
      _toast(summary.error ?? '导入失败');
    }
  }

  Future<EngineId?> _pickEngineDialog() {
    return showDialog<EngineId>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('未能自动识别引擎'),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in EngineId.values)
                if (e != EngineId.unknown)
                  ListTile(
                    leading: Icon(e.icon),
                    title: Text(e.label),
                    subtitle: Text(
                      e.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(dialogContext).pop(e),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// 总目录批量勾选的选中项：detect 为 null 表示未识别（收录时手动指定引擎）。
class _PickedSub {
  const _PickedSub(this.dir, this.detect);
  final Directory dir;
  final DetectResult? detect;
}
