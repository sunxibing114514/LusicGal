import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lusicgal_engines/lusicgal_engines.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_store.dart';
import '../../core/models/game_entry.dart';
import '../../core/saves/save_manager.dart';
import '../../core/settings/settings_controller.dart';
import '../../engine/engine_host.dart';

/// 播放器：承载引擎 PlatformView + 快捷控制。
///
/// 核心缺失时桥返回 CORE_NOT_BUNDLED —— 本页照常展示原生占位渲染面与指引，
/// 而不是崩溃（核心以可选模块接入，见 docs/ARCHITECTURE.md）。
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.game});

  final GameEntry game;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final EngineHost _host;
  late final SaveManager _saves;
  late final LibraryStore _store;
  StreamSubscription<EngineEvent>? _subscription;
  bool _launched = false;
  bool _coreMissing = false;
  bool _paused = false;
  String? _message;
  late final DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _host = context.read<EngineHost>();
    _saves = context.read<SaveManager>();
    _store = context.read<LibraryStore>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  Future<void> _launch() async {
    final settings = context.read<SettingsController>();
    final saveDir = _saves.saveDirFor(widget.game.id, widget.game.engine.id);
    await saveDir.create(recursive: true);
    final result = await _host.launchGame(
      game: widget.game,
      savePath: saveDir.path,
      options: settings.toLaunchOptions(),
    );
    if (!mounted) return;
    setState(() {
      _launched = true;
      if (!result.ok) {
        _coreMissing = result.coreMissing;
        _message = result.message;
      }
    });
    if (result.ok) {
      // 外板形态（Ren'Py Route B / Web 引擎 / 外板启动条目）：
      // 游戏在全屏 Activity 或外部应用中运行，本页自动让位（退出即回书库）。
      if (widget.game.engine.isOutboard) {
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (mounted) Navigator.of(context).maybePop();
        });
        return;
      }
      _subscription = _host.events(gameId: widget.game.id).listen((event) {
        if (!mounted) return;
        if (event.type == 'exit') {
          Navigator.of(context).maybePop();
        } else if (event.type == 'state') {
          setState(() {
            final state = event.data['state'];
            if (state == 'paused') _paused = true;
            if (state == 'running') _paused = false;
            _message = event.data['message'] as String? ?? _message;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    final elapsed = DateTime.now().difference(_startedAt);
    final host = _host;
    final store = _store;
    final gameId = widget.game.id;
    if (elapsed.inSeconds > 0) {
      // 引擎停止与游玩统计在后台完成（不影响页面关闭动画）。
      scheduleMicrotask(() async {
        try {
          await host.stop();
        } on Exception {
          // 平台通道不可用（测试环境）—— 忽略。
        }
        await store.recordPlay(gameId, elapsed);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final creationParams = <String, Object?>{
      'engineId': widget.game.engine.id,
      'gameId': widget.game.id,
    };
    final engineView = Platform.isAndroid
        ? AndroidView(
            viewType: LusicgalEngines.engineViewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
          )
        : UiKitView(
            viewType: LusicgalEngines.engineViewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: engineView),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Text(
                        widget.game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        widget.game.engineBadge,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_launched && _coreMissing)
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.of(context).padding.top + 64,
                child: Card(
                  color: scheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '引擎核心未打包',
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _message ?? '此引擎核心为可选编译模块。请参照 docs/BUILD.md 与 '
                              '.github/workflows/engines.yml 构建并打包核心。',
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // 启动失败（如 WebGameActivity 异常）：非核心缺失问题，
            // 单独提示（不套用"核心未打包"文案）。
            if (_launched && !_coreMissing && _message != null)
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.of(context).padding.top + 64,
                child: Card(
                  color: scheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _message!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 8,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: _paused ? '继续' : '暂停',
                      color: Colors.white,
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      onPressed: () {
                        setState(() => _paused = !_paused);
                        _host.sendCommand(_paused ? 'pause' : 'resume');
                      },
                    ),
                    IconButton(
                      tooltip: '自动播放',
                      color: Colors.white,
                      icon: const Icon(Icons.fast_forward_outlined),
                      onPressed: () => _host.key('auto'),
                    ),
                    IconButton(
                      tooltip: '快进（按住）',
                      color: Colors.white,
                      icon: const Icon(Icons.double_arrow_outlined),
                      onPressed: () => _host.key('speed'),
                    ),
                    IconButton(
                      tooltip: '跳过',
                      color: Colors.white,
                      icon: const Icon(Icons.skip_next_outlined),
                      onPressed: () => _host.key('skip'),
                    ),
                    IconButton(
                      tooltip: '存档',
                      color: Colors.white,
                      icon: const Icon(Icons.save_outlined),
                      onPressed: () => _host.sendCommand('save'),
                    ),
                    IconButton(
                      tooltip: '读档',
                      color: Colors.white,
                      icon: const Icon(Icons.restore_outlined),
                      onPressed: () => _host.sendCommand('load'),
                    ),
                    IconButton(
                      tooltip: '停止并退出',
                      color: Colors.white,
                      icon: const Icon(Icons.stop_circle_outlined),
                      onPressed: () {
                        _host.sendCommand('stop');
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
