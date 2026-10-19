'use strict';
// 断点续传下载器：Range 续传 + 镜像回退 + 尺寸校验。
// 用法：node dl_resume.js <url> <dest> <expectedSize> [partMs=60000]
const fs = require('fs');
const path = require('path');
const [, , urlArg, dest, expectedSizeArg] = process.argv;
const expectedSize = parseInt(expectedSizeArg, 10);
if (!urlArg || !dest || !expectedSize) { console.error('用法: node dl_resume.js <url> <dest> <expectedSize>'); process.exit(2); }
const GH_RAW = 'https://github.com/sunxibing114514/LusicGal/releases/download/v0.1.0-win-core/LusicGal-debug.apk';
const URLS = [
  urlArg,
  'https://ghproxy.net/' + urlArg,
  'https://mirror.ghproxy.com/' + urlArg,
];
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
(async () => {
  for (;;) {
    const have = fs.existsSync(dest) ? fs.statSync(dest).size : 0;
    if (have >= expectedSize) {
      if (have === expectedSize) { console.log(`COMPLETE ${dest} (${have} bytes)`); return; }
      fs.rmSync(dest);
    }
    const from = fs.existsSync(dest) ? fs.statSync(dest).size : 0;
    const url = URLS[0];
    try {
      console.log(`GET ${url} from=${from}/${expectedSize}`);
      const res = await fetch(url, { headers: from ? { Range: `bytes=${from}-` } : {} });
      if (res.status !== 200 && res.status !== 206) throw new Error(`HTTP ${res.status}`);
      const total = parseInt(res.headers.get('content-length') || '0', 10) + from;
      if (res.status === 200 && from > 0) {
        // 服务器忽略 Range —— 重头来。
        fs.rmSync(dest);
        console.log('server ignored Range, restarting from 0');
        continue;
      }
      const fd = fs.openSync(dest, from ? 'a' : 'w');
      const reader = res.body.getReader();
      let written = from, lastLog = Date.now();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        fs.writeSync(fd, value);
        written += value.length;
        if (Date.now() - lastLog > 30000) {
          console.log(`  ${written} / ${total || expectedSize} (${(100 * written / expectedSize).toFixed(1)}%)`);
          lastLog = Date.now();
        }
      }
      fs.closeSync(fd);
      console.log(`chunk done at ${written}`);
    } catch (e) {
      console.log(`ERR ${e.message} — rotate mirror, retry in 10s`);
      URLS.push(URLS.shift());
      await sleep(10000);
    }
  }
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
