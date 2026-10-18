#!/usr/bin/env node
// LusicGal Windows 管线：往未签名 APK 追加 lib/arm64-v8a/*.so（STORED）。
// 策略：数据区与原中央目录逐字节保留（CD 内 lho 偏移仍有效），
// 尾部追加新 STORED 条目 + 新 CD 记录 + 重建 EOCD。
// .so 必须不压缩（extractNativeLibs=false + mmap 语义）；页对齐交给 zipalign -p。
// 输入必须未签名（zipalign 输出），随后重跑 zipalign + apksigner。
// 用法：node add_libs.js <in.apk> <out.apk> <lib文件...>
'use strict';
const fs = require('fs');
const path = require('path');

const [,, inApk, outApk, ...libFiles] = process.argv;
if (!inApk || !outApk || !libFiles.length) {
  console.error('用法: node add_libs.js <in.apk> <out.apk> <lib文件...>');
  process.exit(2);
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = (crc ^ buf[i]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

const inSize = fs.statSync(inApk).size;
const inFd = fs.openSync(inApk, 'r');
// EOCD 只可能在尾 65558+22 字节内：只读尾部，零全量缓冲。
const TAIL = 65580;
const tail = Buffer.allocUnsafe(Math.min(TAIL, inSize));
fs.readSync(inFd, tail, 0, tail.length, Math.max(0, inSize - tail.length));
const tailBase = inSize - tail.length;
let eocdRel = -1;
for (let i = tail.length - 22; i >= 0; i--) {
  if (tail.readUInt32LE(i) === 0x06054b50) { eocdRel = i; break; }
}
if (eocdRel < 0) throw new Error('EOCD not found');
const eocd = tailBase + eocdRel;
const count = tail.readUInt16LE(eocdRel + 10);
const cdOff = tail.readUInt32LE(eocdRel + 16);
// 中央目录整段读入（~几十 KB）。
const cd = Buffer.allocUnsafe(eocd - cdOff);
fs.readSync(inFd, cd, 0, cd.length, cdOff);
let p = 0;
const existing = new Set();
for (let k = 0; k < count; k++) {
  if (cd.readUInt32LE(p) !== 0x02014b50) throw new Error(`bad CD sig at ${p}`);
  const nl = cd.readUInt16LE(p + 28), el = cd.readUInt16LE(p + 30), cl = cd.readUInt16LE(p + 32);
  existing.add(cd.toString('utf8', p + 46, p + 46 + nl));
  p += 46 + nl + el + cl;
}
if (cdOff + p !== eocd) throw new Error('CD/EOCD 不一致');
const keepEnd = cdOff;         // [0, cdOff) 原样保留（纯数据区；旧 CD 弃置
                              // —— 留着会成为条目间的垃圾段，zipalign 拒收）
fs.closeSync(inFd);

// 收集要追加的 .so（同名去重）。
const toAdd = [];
for (const f of libFiles) {
  const arc = 'lib/arm64-v8a/' + path.basename(f);
  if (existing.has(arc)) { console.log(`跳过（已存在）: ${arc}`); continue; }
  existing.add(arc);
  toAdd.push({ arc, data: fs.readFileSync(f) });
}

// 布局：[原buf[0..keepEnd)] [新条目] [新CD记录] [EOCD]
const newLocal = [];
let cur = keepEnd;
for (const { arc, data } of toAdd) {
  const nameBuf = Buffer.from(arc, 'utf8');
  const lh = Buffer.alloc(30);
  lh.writeUInt32LE(0x04034b50, 0);
  lh.writeUInt16LE(20, 4); lh.writeUInt16LE(0, 6);
  lh.writeUInt16LE(0, 8);                  // STORED
  lh.writeUInt16LE(0, 10); lh.writeUInt16LE(0x2821, 12);
  lh.writeUInt32LE(crc32(data), 14);
  lh.writeUInt32LE(data.length, 18); lh.writeUInt32LE(data.length, 22);
  lh.writeUInt16LE(nameBuf.length, 26); lh.writeUInt16LE(0, 28);
  newLocal.push({ lho: cur, lh, nameBuf, data, crc: crc32(data) });
  cur += 30 + nameBuf.length + data.length;
  console.log(`+ ${arc}（${(data.length / 1048576).toFixed(1)}MB）`);
}

const cdStart = cur;
// 新 CD = 旧 CD 记录原样（lho 不变，数据区未动）+ 新条目记录追加。
const newCd = [cd];
for (const e of newLocal) {
  const ch = Buffer.alloc(46);
  ch.writeUInt32LE(0x02014b50, 0);
  ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6);
  ch.writeUInt16LE(0, 8); ch.writeUInt16LE(0, 10);
  ch.writeUInt16LE(0, 12); ch.writeUInt16LE(0x2821, 14);
  ch.writeUInt32LE(e.crc, 16);
  ch.writeUInt32LE(e.data.length, 20); ch.writeUInt32LE(e.data.length, 24);
  ch.writeUInt16LE(e.nameBuf.length, 28);
  ch.writeUInt16LE(0, 30); ch.writeUInt16LE(0, 32);
  ch.writeUInt16LE(0, 34); ch.writeUInt16LE(0, 36);
  ch.writeUInt32LE(0o644 << 16, 38);
  ch.writeUInt32LE(e.lho, 42);
  newCd.push(ch, e.nameBuf);
  cur += 46 + e.nameBuf.length;
}

const cdSize = cur - cdStart + cd.length;
const eocdOut = Buffer.alloc(22);
eocdOut.writeUInt32LE(0x06054b50, 0);
eocdOut.writeUInt16LE(0, 4); eocdOut.writeUInt16LE(0, 6);
const totalCount = count + newLocal.length;
eocdOut.writeUInt16LE(totalCount, 8); eocdOut.writeUInt16LE(totalCount, 10);
eocdOut.writeUInt32LE(cdSize, 12);   // EOCD+12 = CD 大小
eocdOut.writeUInt32LE(cdStart, 16);  // EOCD+16 = CD 偏移
eocdOut.writeUInt16LE(0, 20);

const fd = fs.openSync(outApk, 'w');
// 流式拷贝 [0, keepEnd)：分块低内存 —— 全量 readFileSync 会把 419MB 顶进
// 页文件，页文件又吃光磁盘（本机 RAM 565MB 实测 ENOSPC 陷阱）。
{
  const CHUNK = 16 * 1024 * 1024;
  const inFd = fs.openSync(inApk, 'r');
  const tmp = Buffer.allocUnsafe(Math.min(CHUNK, keepEnd));
  for (let off = 0; off < keepEnd; ) {
    const n = fs.readSync(inFd, tmp, 0, Math.min(CHUNK, keepEnd - off), off);
    fs.writeSync(fd, tmp, 0, n);
    off += n;
  }
  fs.closeSync(inFd);
}
for (const e of newLocal) { fs.writeSync(fd, e.lh); fs.writeSync(fd, e.nameBuf); fs.writeSync(fd, e.data); }
for (const b of newCd) fs.writeSync(fd, b);
fs.writeSync(fd, eocdOut);
fs.closeSync(fd);
console.log(`✓ ${outApk}：${count} → ${totalCount} 条目（追加 ${newLocal.length}）`);
console.log('  下一步：zipalign -p -f 4 <out> <aligned> && apksigner sign');
