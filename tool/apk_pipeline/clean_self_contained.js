'use strict';
// 清洗 mingw self-contained 目录：删除成员为 ELF（android 侧泄漏产物/不兼容 COFF
// 链接）的归档，保留 COFF 归档。同时报告每个被删文件。
const fs = require('fs');
const path = require('path');

const SC = 'C:/LusicGal/.toolchain/rust/rustc/lib/rustlib/x86_64-pc-windows-gnu/lib/self-contained';
let removed = 0, kept = 0, suspect = [];
for (const f of fs.readdirSync(SC)) {
  if (!f.endsWith('.a')) continue;
  const p = path.join(SC, f);
  const buf = fs.readFileSync(p);
  // ar 魔 "!<arch>\n"
  if (buf.subarray(0, 8).toString('latin1') !== '!<arch>\n') { suspect.push(f); continue; }
  // 第一个成员头 60 字节，数据起点 68
  if (buf.length < 72) { suspect.push(f); continue; }
  const magic = buf.subarray(68, 72);
  if (magic[0] === 0x7f && magic[1] === 0x45) { fs.rmSync(p); removed++; console.log('DEL(elf)', f); }
  else kept++;
}
console.log(`removed=${removed} kept=${kept} suspect=${suspect.join(',')}`);
