import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/library/import_service.dart';
import '../../core/library/library_store.dart';
import '../../core/models/engine_id.dart';
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
                '把游戏文件夹放入 App 专属目录（Android：'
                'Android/data/com.lusicgal/files/；iOS：文件 App 中的 LusicGal），'
                '或选择单个封包文件导入。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
              ),
            ),
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

  Future<void> _importDirectory(ImportCandidate candidate) async {
    setState(() => _busy = true);
    var summary = await _import.importDirectory(candidate.dir);
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
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    final paths = result?.paths.whereType<String>().toList() ?? const <String>[];
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
