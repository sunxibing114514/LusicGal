import 'package:flutter/material.dart';

import '../../core/models/engine_id.dart';

/// 引擎图标 / 文案辅助。
extension EngineIdIcons on EngineId {
  IconData get icon => switch (this) {
        EngineId.kirikiri => Icons.folder_special_outlined,
        EngineId.onscripter => Icons.menu_book_outlined,
        EngineId.renpy => Icons.auto_stories_outlined,
        EngineId.siglus => Icons.vpn_key_outlined,
        EngineId.rfvp => Icons.movie_outlined,
        EngineId.sena => Icons.palette_outlined,
        EngineId.xsystem35 => Icons.castle_outlined,
        EngineId.artemis => Icons.filter_drama_outlined,
        // Web 引擎。
        EngineId.tyrano => Icons.web_asset_outlined,
        EngineId.rpgmv => Icons.grid_view_outlined,
        EngineId.rpgmz => Icons.grid_goldenratio_outlined,
        EngineId.unknown => Icons.help_outline,
      };
}

/// 手势名 → 中文。
const Map<String, String> gestureLabels = {
  'tap': '单击',
  'doubleTap': '双击',
  'longPress': '长按',
  'swipeLeft': '左滑',
  'swipeRight': '右滑',
  'swipeUp': '上滑',
  'swipeDown': '下滑',
  'volumeUp': '音量+',
  'volumeDown': '音量-',
  'back': '返回键',
};

/// 动作名 → 中文。
const Map<String, String> keyActionLabels = {
  'confirm': '确认',
  'cancel': '取消',
  'skip': '跳过',
  'fastForward': '快进',
  'menu': '菜单',
  'save': '存档',
  'load': '读档',
};

/// 音量通道名 → 中文。
const Map<String, String> volumeChannelLabels = {
  'master': '总音量',
  'bgm': 'BGM',
  'se': '音效',
  'voice': '语音',
};
