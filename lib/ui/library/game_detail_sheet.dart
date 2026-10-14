import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_store.dart';
import '../../core/models/engine_id.dart';
import '../../core/models/game_entry.dart';
import '../player/player_screen.dart';
import '../saves/saves_screen.dart';
import '../ui_helpers.dart';

/// 打开某个游戏的详情/操作面板。
Future<void> showGameDetailSheet(BuildContext context, GameEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _DetailSheet(entry: entry),
  );
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.entry});

  final GameEntry entry;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(entry.engine.icon, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        entry.engineBadge,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '路径：${entry.path}\n'
              '添加于 ${entry.addedAt.toLocal().toString().substring(0, 16)} · '
              '累计游玩 ${entry.playedDisplay}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (entry.pathMissing) ...[
              const SizedBox(height: 8),
              Text(
                '⚠ 游戏文件已丢失，请重新导入。',
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: entry.pathMissing
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlayerScreen(game: entry),
                        ),
                      );
                    },
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始游戏'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SavesScreen(game: entry),
                  ),
                );
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('存档管理'),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.drive_file_rename_outline, size: 18),
                  label: const Text('重命名'),
                  onPressed: () => _rename(context, store),
                ),
                ActionChip(
                  avatar: const Icon(Icons.category_outlined, size: 18),
                  label: const Text('指定引擎'),
                  onPressed: () => _pickEngine(context, store),
                ),
                ActionChip(
                  avatar: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除'),
                  onPressed: () => _confirmDelete(context, store),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, LibraryStore store) async {
    final controller = TextEditingController(text: entry.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty && context.mounted) {
      await store.rename(entry.id, title);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickEngine(BuildContext context, LibraryStore store) async {
    final engine = await showDialog<EngineId>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('指定引擎'),
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
                    subtitle: Text(e.description, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    if (engine != null && context.mounted) {
      await store.setEngine(entry.id, engine, null);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete(BuildContext context, LibraryStore store) async {
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除《${entry.title}》'),
        content: const Text('存档目录会保留，可随时重新导入游戏。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DeleteChoice.recordOnly),
            child: const Text('仅移除记录'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.errorContainer,
              foregroundColor:
                  Theme.of(dialogContext).colorScheme.onErrorContainer,
            ),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DeleteChoice.withFiles),
            child: const Text('删除游戏文件'),
          ),
        ],
      ),
    );
    if (choice != null && context.mounted) {
      await store.remove(entry.id, deleteFiles: choice == _DeleteChoice.withFiles);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

enum _DeleteChoice { recordOnly, withFiles }
