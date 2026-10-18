'use strict';
const fs = require('fs');
const path = require('path');
const { zstdDecompressSync } = require('zlib');
const { execFileSync } = require('child_process');

const TOOL = 'C:/LusicGal/.toolchain';
const SC = `${TOOL}/rust/rustc/lib/rustlib/x86_64-pc-windows-gnu/lib/self-contained`;
const AR = `${TOOL}/android-ndk-r29/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-ar.exe`;

function untar(buf, dest) {
  let off = 0;
  const files = [];
  while (off + 512 <= buf.length) {
    const name = buf.toString('latin1', off, off + 100).replace(/\0/g, '');
    if (!name) break;
    const sizeField = buf.toString('latin1', off + 124, off + 136).replace(/\0| /g, '');
    const size = sizeField ? parseInt(sizeField, 8) : 0;
    const target = path.join(dest, name);
    if (name.endsWith('/')) fs.mkdirSync(target, { recursive: true });
    else if (size > 0) {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, buf.subarray(off + 512, off + 512 + size));
      files.push(name);
    }
    off += 512 + Math.ceil(size / 512) * 512;
  }
  return files;
}

(async () => {
  const tar = zstdDecompressSync(fs.readFileSync(`${TOOL}/ucrt64.db`));
  let off = 0, fname = null;
  while (off + 512 <= tar.length) {
    const name = tar.toString('latin1', off, off + 100).replace(/\0/g, '');
    if (!name) break;
    const size = parseInt(tar.toString('latin1', off + 124, off + 136).replace(/\0| /g, ''), 8) || 0;
    if (name.endsWith('/desc') && /x86_64-winpthreads-\d/.test(name)) {
      const desc = tar.toString('utf8', off + 512, off + 512 + size);
      const m = desc.match(/%FILENAME%\n([^\n]+)/);
      if (m) fname = m[1].trim();
      break;
    }
    off += 512 + Math.ceil(size / 512) * 512;
  }
  console.log('winpthread file:', fname);
  if (!fname) process.exit(1);
  const r = await fetch(`https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/ucrt64/${fname}`);
  if (!r.ok) throw new Error(`fetch ${r.status}`);
  const zst = Buffer.from(await r.arrayBuffer());
  const files = untar(zstdDecompressSync(zst), `${TOOL}/wpt-pkg`);
  console.log(files.filter(f => /\.a$/.test(f)).join('\n'));
  let copied = 0;
  for (const f of files) {
    if (/\/lib\/[^/]+\.a$/.test(f)) {
      fs.copyFileSync(`${TOOL}/wpt-pkg/${f}`, path.join(SC, path.basename(f)));
      copied++;
      console.log('lib:', path.basename(f));
    }
  }
  console.log('copied:', copied);
  fs.rmSync(`${TOOL}/wpt-pkg`, { recursive: true, force: true });
})();
