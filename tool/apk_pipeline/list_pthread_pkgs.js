'use strict';
const fs = require('fs');
const { zstdDecompressSync } = require('zlib');
const tar = zstdDecompressSync(fs.readFileSync('C:/LusicGal/.toolchain/ucrt64.db'));
let off = 0;
const seen = new Set();
while (off + 512 <= tar.length) {
  const name = tar.toString('latin1', off, off + 100).replace(/\0/g, '');
  if (!name) break;
  const size = parseInt(tar.toString('latin1', off + 124, off + 136).replace(/\0| /g, ''), 8) || 0;
  const m = name.match(/^(mingw-w64-ucrt-x86_64-[^/]*pthread[^/]*)\//);
  if (m) seen.add(m[1]);
  off += 512 + Math.ceil(size / 512) * 512;
}
console.log([...seen].join('\n'));
