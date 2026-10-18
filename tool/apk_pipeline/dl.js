// node 流式下载器（绕过 Windows schannel 沙箱限制）。
// 用法: node dl.js <url> <out>
'use strict';
const fs = require('fs');
const { Readable } = require('stream');
const { pipeline } = require('stream/promises');

const [url, out] = process.argv.slice(2);
if (!url || !out) { console.error('用法: node dl.js <url> <out>'); process.exit(1); }

async function main() {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`);
  const rs = Readable.fromWeb(res.body);
  const total = +(res.headers.get('content-length') || 0);
  let got = 0; let last = -1;
  rs.on('data', c => {
    got += c.length;
    const pct = total ? Math.floor(got * 100 / total) : -1;
    if (pct !== last && (pct % 5 === 0)) { last = pct; process.stdout.write(`\r${out}: ${pct}% (${(got / 1048576).toFixed(0)}MB)`); }
  });
  await pipeline(rs, fs.createWriteStream(out));
  console.log(`\r✓ ${out}: ${(got / 1048576).toFixed(1)}MB`);
}
main().catch(e => { console.error('✗ ' + e.message); process.exit(1); });
