import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_store.dart';
import '../../core/models/game_entry.dart';
import '../../core/saves/save_manager.dart';
import '../ui_helpers.dart';

/// 存档页。[game] 为空时先选择游戏（首页 Tab），否则直接管理该游戏存档。
class SavesScreen extends StatelessWidget {
  const SavesScreen({super.key, this.game});

  final GameEntry? game;

  @override
  Widget build(BuildContext context) {
    if (game != null) {
      return _GameSavesScreen(game: game!);
    }
    final store = context.watch<LibraryStore>();
    final games = store.games;
    return Scaffold(
      appBar: AppBar(title: const Text('存档管理')),
      body: games.isEmpty
          ? Center(
              child: Text(
                '书库为空，先去导入游戏吧',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : ListView.builder(
              itemCount: games.length,
              itemBuilder: (context, i) => ListTile(
                leading: Icon(games[i].engine.icon),
                title: Text(games[i].title),
                subtitle: Text(games[i].engineBadge),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _GameSavesScreen(game: games[i]),
                  ),
                ),
              ),
            ),
    );
  }
}

class _GameSavesScreen extends StatefulWidget {
  const _GameSavesScreen({required this.game});

  final GameEntry game;

  @override
  State<_GameSavesScreen> createState() => _GameSavesScreenState();
}

class _GameSavesScreenState extends State<_GameSavesScreen> {
  int _reloadKey = 0;
  bool _busy = false;

  SaveManager get _saves => context.read<SaveManager>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.game.title} · 存档'),
        actions: [
          IconButton(
            tooltip: '导出 zip',
            icon: const Icon(Icons.archive_outlined),
            onPressed: _busy ? null : _export,
          ),
          IconButton(
            tooltip: '导入 zip',
            icon: const Icon(Icons.unarchive_outlined),
            onPressed: _busy ? null : _import,
          ),
        ],
      ),
      body: FutureBuilder<List<SaveItem>>(
        key: ValueKey(_reloadKey),
        future: _saves.listSaves(widget.game.id, widget.game.engine.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <SaveItem>[];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_off_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  const Text('暂无存档。开始游戏后由引擎核心写入，\n也可导入之前导出的 zip。'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(items[i].relativePath),
              subtitle: Text(
                '${items[i].sizeBytes} B · '
                '${items[i].modified.toLocal().toString().substring(0, 19)}',
              ),
              trailing: IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await _saves.deleteSave(items[i], widget.game.id, widget.game.engine.id);
                  setState(() => _reloadKey++);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final out = await _saves.exportZip(
        widget.game.id,
        widget.game.engine.id,
        title: widget.game.title,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出：${out.path}\n（iOS 可在文件 App 的 LusicGal 目录取走）')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = result?.paths.whereType<String>().firstOrNull;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final count =
          await _saves.importZip(widget.game.id, widget.game.engine.id, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 $count 个存档文件')),
        );
        setState(() => _reloadKey++);
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
