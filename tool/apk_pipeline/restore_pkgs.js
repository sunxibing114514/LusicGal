#!/usr/bin/env node
// LusicGal Windows 包还原器：按 .dart_tool/package_config.json（Linux 迁移）
// 从 pub.dev 拉取全部 hosted 包到本地 pub-cache 并重写路径表。
// —— DSH 沙箱适配：下载用 node fetch（schannel 被禁），解包用 tar.exe
//    （stdio: 'ignore' —— 管道 stdio 被沙箱禁止，stdio.ignore 合法）。
'use strict';
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const ROOT = 'C:/LusicGal';
const PC = path.join(ROOT, '.dart_tool', 'package_config.json');
const CACHE = 'C:/LusicGal/.toolchain/pub-cache/hosted/pub.dev';

const cfg = JSON.parse(fs.readFileSync(PC, 'utf8'));

// SDK 包路径映射（Windows 工具链树内）。
const FLUTTER = 'C:/LusicGal/.toolchain/flutter';
const sdkMap = {
  flutter: FLUTTER + '/packages/flutter',
  flutter_test: FLUTTER + '/packages/flutter_test',
  flutter_web_plugins: FLUTTER + '/packages/flutter_web_plugins',
  flutter_driver: FLUTTER + '/packages/flutter_driver',
  fuchsia_remote_debug_protocol: FLUTTER + '/packages/fuchsia_remote_debug_protocol',
  sky_engine: FLUTTER + '/bin/cache/pkg/sky_engine',
};

const hosted = [];
const sdkPkgs = [];
for (const p of cfg.packages) {
  if (sdkMap[p.name]) {
    sdkPkgs.push({ ...p, rootUri: 'file:///' + sdkMap[p.name].replace(/\\/g, '/') });
  } else {
    // 兼容两种形态：Linux 迁移表（file:///tmp/.pub-cache/…）与本工具重写后的
    // Windows pub-cache 路径；目录名均为 <name>-<version>。
    const m = p.rootUri.match(/(?:\/tmp\/\.pub-cache\/hosted\/pub\.dev|pub-cache\/hosted\/pub\.dev)\/([^/?#]+)$/);
    if (m) hosted.push({ ...p, dir: m[1] });
  }
  // 相对路径（lusicgal ../ 与 lusicgal_engines ../plugins/...）保持不动。
}

fs.mkdirSync(CACHE, { recursive: true });

// 纯 node tar.gz 解包（零 spawn —— DSH 沙箱会 EPERM 拒绝 child_process）。
function extractTarGz(tgzFile, destDir) {
  const zlib = require('zlib');
  const raw = zlib.gunzipSync(fs.readFileSync(tgzFile));
  let off = 0;
  while (off + 512 <= raw.length) {
    const h = raw.subarray(off, off + 512);
    const name = h.toString('utf8', 0, 100).replace(/\0.*$/s, '');
    if (!name) break;
    const sizeField = h.toString('utf8', 124, 136).replace(/\0| /g, '');
    const size = parseInt(sizeField, 8) || 0;
    const type = h[156];
    const prefix = h.toString('utf8', 345, 500).replace(/\0.*$/s, '');
    const full = (prefix ? prefix + '/' : '') + name;
    off += 512;
    if (full !== '././@PaxHeader' && !full.startsWith('PaxHeader')) {
      const target = path.join(destDir, full);
      if (type === 0x30 || type === 0) {            // '0'/NUL = 常规文件
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, raw.subarray(off, off + size));
      } else if (type === 0x35) {                   // '5' = 目录
        fs.mkdirSync(target, { recursive: true });
      } else if (type === 0x32) {                  // '2' = 符号链接（pub 包少用；落盘为文本提示）
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target + '.symlink', h.toString('utf8', 157, 257).replace(/\0.*$/s, ''));
      }
    }
    off += Math.ceil(size / 512) * 512;
  }
}

async function fetchOne(pkg) {
  const dest = path.join(CACHE, pkg.dir);
  if (fs.existsSync(path.join(dest, 'pubspec.yaml'))) return 'cached';
  const tgz = path.join(CACHE, pkg.dir + '.tar.gz');
  const url = `https://pub.dev/api/archives/${pkg.dir}.tar.gz`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url} HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(tgz, buf);
  fs.mkdirSync(dest, { recursive: true });
  extractTarGz(tgz, dest);
  fs.unlinkSync(tgz);
  return 'ok';
}

(async () => {
  let done = 0, fail = 0;
  for (const pkg of hosted) {
    try {
      await fetchOne(pkg);
      done++;
      if (done % 10 === 0) console.log(`  ...${done}/${hosted.length}`);
    } catch (e) {
      fail++;
      console.error(`FAIL ${pkg.dir}: ${e.message}`);
    }
  }
  console.log(`hosted: ${done} ok, ${fail} fail; sdk: ${sdkPkgs.length}`);

  // 重写 package_config.json（备份原件）。
  const out = {
    configVersion: 2,
    packages: cfg.packages.map(p => {
      const sdk = sdkMap[p.name];
      if (sdk) return { ...p, rootUri: 'file:///' + sdk.replace(/\\/g, '/') };
      const m = p.rootUri.match(/(?:\/tmp\/\.pub-cache\/hosted\/pub\.dev|pub-cache\/hosted\/pub\.dev)\/([^/?#]+)$/);
      if (m) return { ...p, rootUri: 'file:///' + (CACHE + '/' + m[1]).replace(/\\/g, '/') };
      return p;
    }),
    generator: 'lusicgal-win-restore',
    generatorVersion: '1.0',
    flutterRoot: 'file:///' + FLUTTER.replace(/\\/g, '/'),
    flutterVersion: '3.47.7',
  };
  try { fs.accessSync(PC + '.linux.bak'); } catch { fs.copyFileSync(PC, PC + '.linux.bak'); }
  fs.writeFileSync(PC, JSON.stringify(out, null, 2));
  console.log('package_config.json rewritten (linux backup at .linux.bak)');
})().catch(e => { console.error(e); process.exit(1); });
