#!/usr/bin/env node
// LusicGal 内核热换（kernel hot-swap）—— Windows/Linux 通用（node ≥16，零依赖）。
// ---------------------------------------------------------------------------
// 用法：
//   node tool/apk_pipeline/swap_kernel.js <in.apk> <out.apk> <new_flutter_assets_dir>
//
// 语义（docs/BUILD.md「内核边界与热换」）：
//   - APK 内 assets/flutter_assets/** 全部替换为 <new_flutter_assets_dir>/**；
//   - 其余条目（classes.dex / lib/*.so / resources.arsc / assets/lg_web_boot.js /
//     AndroidManifest.xml …）**逐项原样字节拷贝**——压缩方式、STORED 状态、
//     本地头均不变（本地头不含绝对偏移，无需改写）；
//   - 中央目录按新偏移重建（经典 zip，无 zip64）；
//   - 产物仍需 zipalign -p + apksigner（对齐与签名不在本脚本职责内）。
//
// 设计动机：真内核（app.dill）冷编 >550MB，受限容器无法产出；任意 ≥1GB
// 空闲内存的机器跑 `flutter assemble` 得到 flutter_assets 后，用本脚本把
// 已签 APK 换芯。dex/资源/原生库不动 —— 插件注册表已在 classes.dex。

'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

function fail(msg) { console.error('✗ ' + msg); process.exit(1); }

const [inApk, outApk, assetsDir] = process.argv.slice(2);
if (!inApk || !outApk || !assetsDir) {
  fail('用法: node swap_kernel.js <in.apk> <out.apk> <new_flutter_assets_dir>');
}

const buf = fs.readFileSync(inApk);

// ── EOCD 定位（最后的 0x06054b50，紧邻最多 64KB 注释）──────────────────────
let eocd = -1;
for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65536); i--) {
  if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
}
if (eocd < 0) fail('找不到 EOCD（zip 损坏？）');
const cdCount = buf.readUInt16LE(eocd + 10);
const cdOffset = buf.readUInt32LE(eocd + 16);
if (buf.readUInt32LE(cdOffset) !== 0x02014b50) fail('中央目录签名不匹配');

// ── 解析中央目录条目 ────────────────────────────────────────────────────────
const entries = [];
let p = cdOffset;
for (let n = 0; n < cdCount; n++) {
  if (buf.readUInt32LE(p) !== 0x02014b50) fail(`CD[${n}] 签名错`);
  const method = buf.readUInt16LE(p + 10);
  const crc = buf.readUInt32LE(p + 16);
  const csize = buf.readUInt32LE(p + 20);
  const usize = buf.readUInt32LE(p + 24);
  const nameLen = buf.readUInt16LE(p + 28);
  const extraLen = buf.readUInt16LE(p + 30);
  const commentLen = buf.readUInt16LE(p + 32);
  const lho = buf.readUInt32LE(p + 42);
  const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
  entries.push({ method, crc, csize, usize, lho, name, cd: p, nameLen, extraLen, commentLen });
  p += 46 + nameLen + extraLen + commentLen;
}
if (p !== eocd) fail('CD 尺寸与 EOCD 不一致');

// ── 收集新 flutter_assets 文件树 ───────────────────────────────────────────
const newFiles = [];
(function walk(dir, rel) {
  for (const f of fs.readdirSync(dir)) {
    const fp = path.join(dir, f);
    const st = fs.statSync(fp);
    if (st.isDirectory()) walk(fp, rel + f + '/');
    else newFiles.push({ abs: fp, arc: 'assets/flutter_assets/' + rel + f });
  }
})(assetsDir, '');
if (!newFiles.some(f => f.arc.endsWith('kernel_blob.bin'))) {
  fail('新资产目录缺 kernel_blob.bin —— 这不是 flutter assemble 的产物？');
}

// ── 输出：原条目逐字节拷贝（排除旧 flutter_assets）+ 新条目 deflate ─────────
const REPLACED = new Set(entries.filter(e => e.name.startsWith('assets/flutter_assets/')).map(e => e.name));
const out = [];
let offset = 0;
const push = chunk => { out.push(chunk); offset += chunk.length; };
const newCd = [];

const keep = entries.filter(e => !REPLACED.has(e.name));
console.log(`原条目 ${entries.length}（弃 ${REPLACED.size} 条 flutter_assets，保 ${keep.length}）+ 新 ${newFiles.length}`);

for (const e of keep) {
  // 本地段 = local header(30+nl+el) + 数据；csize 覆盖数据长度（有描述符时亦然）。
  const lho = e.lho;
  if (buf.readUInt32LE(lho) !== 0x04034b50) fail(`local header 错 @ ${e.name}`);
  const lNameLen = buf.readUInt16LE(lho + 26);
  const lExtraLen = buf.readUInt16LE(lho + 28);
  const dataStart = lho + 30 + lNameLen + lExtraLen;
  const block = buf.subarray(lho, dataStart + e.csize);
  const newLho = offset;
  push(block);
  newCd.push({ ...e, lho: newLho });
}

const addFile = f => {
  const data = fs.readFileSync(f.abs);
  const comp = zlib.deflateRawSync(data, { level: 9 });
  const crc = require('zlib').crc32 ? zlib.crc32(data) : crc32(data);
  const arc = Buffer.from(f.arc, 'utf8');
  const newLho = offset;
  const lh = Buffer.alloc(30);
  lh.writeUInt32LE(0x04034b50, 0);
  lh.writeUInt16LE(20, 4);            // version needed
  lh.writeUInt16LE(0, 6);             // flags（无描述符：尺寸已知）
  lh.writeUInt16LE(8, 8);             // deflate
  lh.writeUInt16LE(0, 10); lh.writeUInt16LE(0x2821, 12); // dos time/date
  lh.writeUInt32LE(crc >>> 0, 14);
  lh.writeUInt32LE(comp.length, 18);
  lh.writeUInt32LE(data.length, 22);
  lh.writeUInt16LE(arc.length, 26);
  lh.writeUInt16LE(0, 28);
  push(lh); push(arc); push(comp);
  newCd.push({ method: 8, crc: crc >>> 0, csize: comp.length, usize: data.length, lho: newLho, name: f.arc });
};

function crc32(buf) {
  let c, table = crc32.table;
  if (!table) {
    table = crc32.table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      c = n;
      for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      table[n] = c;
    }
  }
  c = 0 ^ (-1);
  for (let i = 0; i < buf.length; i++) c = (c >>> 8) ^ table[(c ^ buf[i]) & 0xFF];
  return (c ^ (-1)) >>> 0;
}

for (const f of newFiles) addFile(f);

// ── 新中央目录 + EOCD ───────────────────────────────────────────────────────
const cdStart = offset;
for (const e of newCd) {
  const nameBuf = Buffer.from(e.name, 'utf8');
  const ch = Buffer.alloc(46);
  ch.writeUInt32LE(0x02014b50, 0);
  ch.writeUInt16LE(20, 4);            // made by
  ch.writeUInt16LE(20, 6);            // needed
  ch.writeUInt16LE(0, 8);             // flags
  ch.writeUInt16LE(e.method, 10);
  ch.writeUInt16LE(0, 12); ch.writeUInt16LE(0x2821, 14);
  ch.writeUInt32LE(e.crc, 16);
  ch.writeUInt32LE(e.csize, 20);
  ch.writeUInt32LE(e.usize, 24);
  ch.writeUInt16LE(nameBuf.length, 28);
  ch.writeUInt16LE(0, 30);            // extra（拷贝条目：丢弃旧 extra ——
  ch.writeUInt16LE(0, 32);            //  aapt2 的 UT/ux 对齐条目无功能意义，
  ch.writeUInt16LE(0, 34);            // comment 长度（aapt2 条目无注释；
                                      // 旧 extra 丢弃 —— UT/ux 无功能意义，
                                      // 对齐由后续 zipalign -p 重建）
  ch.writeUInt16LE(0, 36);            // internal attrs
  ch.writeUInt32LE(0o644 << 16, 38);  // external attrs
  ch.writeUInt32LE(e.lho, 42);        // 本地头偏移
  push(ch); push(nameBuf);
}
const cdEnd = offset;
const eocdBuf = Buffer.alloc(22);
eocdBuf.writeUInt32LE(0x06054b50, 0);
eocdBuf.writeUInt16LE(0, 4);
eocdBuf.writeUInt16LE(0, 6);
eocdBuf.writeUInt16LE(newCd.length, 8);
eocdBuf.writeUInt16LE(newCd.length, 10);
eocdBuf.writeUInt32LE(cdEnd - cdStart, 12);
eocdBuf.writeUInt32LE(cdStart, 16);
eocdBuf.writeUInt16LE(0, 20);
push(eocdBuf);

// ── 落盘 ───────────────────────────────────────────────────────────────────
const fd = fs.openSync(outApk, 'w');
for (const c of out) fs.writeSync(fd, c);
fs.closeSync(fd);
console.log(`✓ ${outApk}：${newCd.length} 条目，kernel_blob 已换（${(fs.statSync(outApk).size / 1048576).toFixed(1)}MB）`);
console.log('  下一步：zipalign -p -f 4 <out> <aligned> && apksigner sign');
