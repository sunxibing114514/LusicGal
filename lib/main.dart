import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/library/import_service.dart';
import 'core/library/library_store.dart';
import 'core/saves/save_manager.dart';
import 'core/settings/settings_controller.dart';
import 'engine/engine_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final docs = await getApplicationDocumentsDirectory();
  final extDirs = await getExternalStorageDirectories();
  final importRoots = <Directory>[docs, if (extDirs?.isNotEmpty ?? false) extDirs!.first];

  final store = LibraryStore(root: docs);
  await store.load();

  final settings = SettingsController(file: File(p.join(docs.path, 'settings.json')));
  await settings.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>.value(value: store),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        Provider<ImportService>.value(
          value: ImportService(store: store, importRoots: importRoots),
        ),
        Provider<SaveManager>.value(value: SaveManager(root: docs)),
        Provider<EngineHost>.value(value: EngineHost()),
      ],
      child: const LusicGalApp(),
    ),
  );
}
