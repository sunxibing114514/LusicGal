import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/settings/settings_controller.dart';
import 'core/theme.dart';
import 'ui/home_shell.dart';

/// LusicGal 应用根组件（主题由设置驱动：system / light / dark）。
class LusicGalApp extends StatelessWidget {
  const LusicGalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: 'LusicGal',
      debugShowCheckedModeBanner: false,
      theme: LusicTheme.light(),
      darkTheme: LusicTheme.dark(),
      themeMode: switch (settings.themeMode) {
        ThemeModeSetting.system => ThemeMode.system,
        ThemeModeSetting.light => ThemeMode.light,
        ThemeModeSetting.dark => ThemeMode.dark,
      },
      home: const HomeShell(),
    );
  }
}
