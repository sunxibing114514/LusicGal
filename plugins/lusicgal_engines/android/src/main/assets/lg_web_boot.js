/*
 * LusicGal Web 引擎启动 hook（注入到 index.html 的 <head>）。
 *
 * 职责：
 *  - 运行时自适应识别 TyranoScript / RPG Maker MV / MZ；
 *  - 音频生命周期：Activity onPause/onResume 时全量暂停/恢复
 *    （WebAudio 上下文 + <audio>/<video> 元素；Tyrano 额外走 kag 内部表）；
 *  - 虚拟手柄按键合成（RPG MV/MZ 的键盘交互）→ KeyboardEvent；
 *  - localStorage 健康自检 + 坏则 lusicgalBridge 后备 polyfill
 *    （v0.1.11 起：存档走引擎原生 localStorage —— 端口固定后按 origin
 *    持久；不再改写引擎的存档函数，杜绝语义错配）。
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

  // ---- localStorage 健康自检 + 坏则 polyfill（document-start，先于所有引擎脚本）----
  //
  // v0.1.11 修正：此前这里是"$.setStorage/$.getStorage → lusicgalBridge
  // 落盘"的桥接补丁 —— 与 tyrano libs.js 的原生语义（escape/unescape、
  // "null" 字符串、LZString、boot 中途换实现）三重错配，触发 tyrano 自家
  // $.getStorageWeb 的 catch → 现机实测弹
  // "この環境はセーブ機能を利用できません" + "セーブデータが壊れている…"
  // 双框。端口固定（v0.1.10）后原生 localStorage 即可持久，桥接彻底退役。
  //
  // 兜底保留：若设备 WebView 的原生 localStorage 真的抛异常（profile
  // 损坏等），本 hook 在引擎脚本加载前用 lusicgalBridge 后备存储 polyfill
  // 之 —— 引擎全程用自家原生语义读写，无双语义错配。
  (function () {
    var PREFIX = 'lgls::';
    var nativeOk = false;
    try {
      var probe = '__lg_probe__';
      window.localStorage.setItem(probe, '1');
      var r = window.localStorage.getItem(probe);
      window.localStorage.removeItem(probe);
      nativeOk = (r === '1');
    } catch (e) { nativeOk = false; }
    if (nativeOk) return;

    var mem = {};
    function b() {
      return typeof window.lusicgalBridge !== 'undefined' && window.lusicgalBridge;
    }
    // 冷启动水化：后备盘已有键载入内存（bridge 调用同步返回）。
    if (b()) {
      try {
        var raw = window.lusicgalBridge.listStorage();
        var ks = JSON.parse(raw || '[]');
        for (var i = 0; i < ks.length; i++) {
          if (String(ks[i]).indexOf(PREFIX) !== 0) continue;
          var k = String(ks[i]).substring(PREFIX.length);
          var v = window.lusicgalBridge.getStorage(ks[i]);
          if (v !== '' && v != null) mem[k] = v;
        }
      } catch (e) { }
    }
    var shim = {
      get length() {
        var n = 0;
        for (var k in mem) { if (Object.prototype.hasOwnProperty.call(mem, k)) n++; }
        return n;
      },
      key: function (i) {
        var n = 0;
        for (var k in mem) {
          if (!Object.prototype.hasOwnProperty.call(mem, k)) continue;
          if (n === i) return k;
          n++;
        }
        return null;
      },
      getItem: function (k) {
        k = String(k);
        return Object.prototype.hasOwnProperty.call(mem, k) ? mem[k] : null;
      },
      setItem: function (k, v) {
        k = String(k);
        mem[k] = String(v);
        if (b()) { try { window.lusicgalBridge.setStorage(PREFIX + k, String(v)); } catch (e) { } }
      },
      removeItem: function (k) {
        k = String(k);
        delete mem[k];
        if (b()) { try { window.lusicgalBridge.removeStorage(PREFIX + k); } catch (e) { } }
      },
      clear: function () {
        if (b()) {
          try {
            var ks = JSON.parse(window.lusicgalBridge.listStorage() || '[]');
            for (var i = 0; i < ks.length; i++) {
              if (String(ks[i]).indexOf(PREFIX) === 0) {
                window.lusicgalBridge.removeStorage(String(ks[i]));
              }
            }
          } catch (e) { }
        }
        mem = {};
      }
    };
    try {
      Object.defineProperty(window, 'localStorage', {
        get: function () { return shim; },
        configurable: true
      });
      window.sessionStorage = shim; // 会话存储同兜底（引擎有引用）。
    } catch (e) {
      // defineProperty 失败（极端）→ 原样保留，引擎可能仍报存档框。
    }
  })();
})();
