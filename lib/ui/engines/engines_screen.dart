import 'package:flutter/material.dart';
import 'package:lusicgal_engines/lusicgal_engines.dart';
import 'package:provider/provider.dart';

import '../../core/models/engine_id.dart';
import '../../engine/engine_host.dart';
import '../ui_helpers.dart';

/// 引擎页：探测各核心打包状态（probeEngines），缺失时给出指引。
class EnginesScreen extends StatefulWidget {
  const EnginesScreen({super.key});

  @override
  State<EnginesScreen> createState() => _EnginesScreenState();
}

class _EnginesScreenState extends State<EnginesScreen> {
  Future<Map<String, EngineProbe>>? _future;

  EngineHost get _host => context.read<EngineHost>();

  @override
  void initState() {
    super.initState();
    _future = _host.probeEngines();
  }

  void _refresh() {
    setState(() {
      _future = _host.probeEngines();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('引擎'),
        actions: [
          IconButton(
            tooltip: '重新探测',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<Map<String, EngineProbe>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final probes = snapshot.data ?? const <String, EngineProbe>{};
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                for (final engine in EngineId.values)
                  if (engine != EngineId.unknown)
                    _EngineCard(
                      engine: engine,
                      probe: probes[engine.id],
                    ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('关于引擎核心', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          '引擎核心以"可选模块"方式接入：Android 检查包内 '
                          'liblusicgal_<引擎>.so 是否存在（零装载探测，'
                          '点"开始游戏"时才真正加载核心），'
                          'iOS 通过 dlsym 探测静态符号。核心缺失不影响 App 其它功能。\n\n'
                          '核心的交叉编译脚本位于 native/engines/<引擎>/，'
                          'CI 尝试任务见 .github/workflows/engines.yml；'
                          '上游选型与 pin 见 docs/ENGINE_NOTES.md。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '探测方式：Android System.loadLibrary / iOS dlsym',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({required this.engine, this.probe});

  final EngineId engine;
  final EngineProbe? probe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = probe?.available ?? false;
    return Card(
      child: ListTile(
        leading: Icon(engine.icon, color: scheme.primary),
        title: Text(engine.label),
        subtitle: Text(
          available
              ? (probe?.version == null
                  ? engine.description
                  : '${engine.description} · ${probe!.version}')
              : (probe?.message ?? '${engine.description} · 核心未打包'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: DecoratedBox(
          decoration: BoxDecoration(
            color: available ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              available ? '可用' : '未打包',
              style: TextStyle(
                fontSize: 12,
                color: available ? scheme.onPrimaryContainer : scheme.outline,
              ),
            ),
          ),
        ),
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(engine.label),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(engine.description),
                const SizedBox(height: 8),
                Text(
                  available
                      ? '状态：可用${probe?.version == null ? '' : '（${probe!.version}）'}'
                      : '状态：核心未打包\n${probe?.message ?? ''}',
                ),
                const SizedBox(height: 8),
                Text(
                  '构建方式：native/engines/${engine.id}（脚本）+ '
                  '.github/workflows/engines.yml（CI）',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
