'use strict';
// 匿名轮询 full-apk run 至终态，随后匿名核对 release 是否已由 CI 自建。
const repo = 'sunxibing114514/LusicGal';
const h = { 'User-Agent': 'lg' };
const sleep = (ms) => new Promise(z => setTimeout(z, ms));
(async () => {
  const rid = process.argv[2];
  const dl = Date.now() + 3.5 * 3600 * 1000;
  while (Date.now() < dl) {
    try {
      const r = await fetch(`https://api.github.com/repos/${repo}/actions/runs/${rid}`, { headers: h });
      if (r.status === 200) {
        const j = await r.json();
        console.log('poll', j.status, j.conclusion || '-', new Date().toISOString());
        if (j.status === 'completed') {
          console.log('FINAL:', j.conclusion);
          // 匿名核对 release（公开仓库）
          const rel = await fetch(`https://api.github.com/repos/${repo}/releases/tags/v0.1.1-full-core`, { headers: h });
          console.log('release http', rel.status);
          if (rel.status === 200) {
            const rj = await rel.json();
            console.log('release id', rj.id, 'assets:');
            for (const a of rj.assets) console.log('  asset', a.name, a.size_in_bytes, 'bytes', a.state);
          }
          process.exit(rel.status === 200 ? 0 : 1);
        }
      } else console.log('http', r.status);
    } catch (e) { console.log('err', e.message); }
    await sleep(150000);
  }
  console.log('RESULT: POLL_TIMEOUT');
  process.exit(2);
})();
