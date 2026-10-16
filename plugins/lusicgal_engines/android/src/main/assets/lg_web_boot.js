/*
 * LusicGal Web 引擎启动 hook（注入到 index.html 的 <head>）。
 *
 * 职责：
 *  - 运行时自适应识别 TyranoScript / RPG Maker MV / MZ；
 *  - 音频生命周期：Activity onPause/onResume 时全量暂停/恢复
 *    （WebAudio 上下文 + <audio>/<video> 元素；Tyrano 额外走 kag 内部表）；
 *  - 虚拟手柄按键合成（RPG MV/MZ 的键盘交互）→ KeyboardEvent；
 *  - Tyrano 存档桥接（$.setStorage/$.getStorage → lusicgalBridge 落盘）。
 *
 * 参考 xm486/YukiHub（GPL-3.0）assets/__tyrano__.js 的音频表思路重写；
 * 署名见 docs/LICENSE_NOTES.md。
 */
(function () {
  'use strict';

  var kind = null;

  function detect() {
    try {
      if (window.TYRANO && window.TYRANO.kag) return 'tyrano';
      if (window.Utils && window.Graphics) {
        if (window.RMMZ || (document.querySelector('script[src*="rmmz_"]'))) return 'rpgmz';
        return 'rpgmv';
      }
    } catch (e) { }
    return kind;
  }

  // ---- WebAudio 上下文跟踪（MV/MZ 与现代 Tyrano 均走 Web Audio）----
  var audioCtxs = [];
  var OrigCtx = window.AudioContext || window.webkitAudioContext;
  if (OrigCtx) {
    (function (C) {
      window.AudioContext = function () {
        var ctx = new C();
        audioCtxs.push(ctx);
        return ctx;
      };
      window.AudioContext.prototype = C.prototype;
    })(OrigCtx);
  }

  // ---- <audio>/<video> 元素暂停/恢复 ----
  var pausedMedia = [];

  function pauseMedia() {
    var list = document.querySelectorAll('audio, video');
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (el.paused) continue;
      try { el.pause(); pausedMedia.push(el); } catch (e) { }
    }
  }

  function resumeMedia() {
    for (var i = 0; i < pausedMedia.length; i++) {
      try { pausedMedia[i].play(); } catch (e) { }
    }
    pausedMedia.length = 0;
  }

  window.__lgAudioPause = function () {
    kind = kind || detect();
    try {
      for (var i = 0; i < audioCtxs.length; i++) {
        if (audioCtxs[i].state === 'running') audioCtxs[i].suspend();
      }
    } catch (e) { }
    if (kind === 'tyrano') {
      try {
        var b = TYRANO.kag.tmp.map_bgm || {};
        var s = TYRANO.kag.tmp.map_se || {};
        for (var k in b) { if (b[k] && b[k].pause) b[k].pause(); }
        for (var k2 in s) { if (s[k2] && s[k2].pause) s[k2].pause(); }
      } catch (e) { }
    }
    pauseMedia();
  };

  window.__lgAudioResume = function () {
    kind = kind || detect();
    try {
      for (var i = 0; i < audioCtxs.length; i++) {
        if (audioCtxs[i].state === 'suspended') audioCtxs[i].resume();
      }
    } catch (e) { }
    if (kind === 'tyrano') {
      try {
        var b = TYRANO.kag.tmp.map_bgm || {};
        var cur = TYRANO.kag.stat.current_bgm;
        if (cur && b[cur]) { b[cur].play(); }
        else if (b[0]) { b[0].play(); }
      } catch (e) { }
    }
    resumeMedia();
  };

  // ---- 虚拟手柄按键合成 ----
  var keyCodeMap = {
    ArrowUp: 38, ArrowDown: 40, ArrowLeft: 37, ArrowRight: 39,
    Enter: 13, Escape: 27, Space: 32, Shift: 16, Control: 17,
    Z: 90, X: 88, C: 67, V: 86, B: 66, N: 78, Menu: 93, Tab: 9,
    PageUp: 33, PageDown: 34, Home: 36, End: 35, Insert: 45
  };

  window.__lgKey = function (code, type) {
    try {
      var kc = keyCodeMap[code] || (code.length === 1 ? code.toUpperCase().charCodeAt(0) : 0);
      var ev = new KeyboardEvent(type, {
        key: code, code: code, keyCode: kc, which: kc,
        bubbles: true, cancelable: true
      });
      (document.activeElement || document).dispatchEvent(ev);
      if (typeof window.onkeydown === 'function' || typeof window.onkeyup === 'function') {
        // 部分引擎直接挂在 window 处理器上。
        var f = type === 'keydown' ? window.onkeydown : window.onkeyup;
        if (typeof f === 'function') f.call(window, ev);
      }
    } catch (e) { }
  };

  // ---- Tyrano 存档桥接（jQuery $.setStorage 路径）----
  function hasBridge() {
    return typeof window.lusicgalBridge !== 'undefined' && window.lusicgalBridge;
  }

  var patchTyranoSave = function () {
    if (kind !== 'tyrano' || !window.jQuery || !window.$ || !hasBridge()) return;
    try {
      $.setStorage = function (key, val) {
        try {
          window.lusicgalBridge.setStorage(key, encodeURIComponent(JSON.stringify(val)));
        } catch (e) { }
      };
      $.getStorage = function (key) {
        try {
          var s = window.lusicgalBridge.getStorage(key);
          return s === '' || s == null ? null : decodeURIComponent(s);
        } catch (e) { return null; }
      };
      $.openWebFromApp = function (url) {
        try { window.lusicgalBridge.openUrl(url); } catch (e) { }
      };
    } catch (e) { }
  };

  // 引擎脚本异步加载：轮询至识别成功后挂桥。
  var tries = 0;
  var timer = setInterval(function () {
    kind = detect();
    if (kind || ++tries > 120) {
      clearInterval(timer);
      if (kind) patchTyranoSave();
    }
  }, 500);
})();
