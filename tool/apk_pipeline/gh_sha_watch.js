'use strict';
// 匿名轮询指定 SHA 的 CI runs 至全部完成。
const repo = 'sunxibing114514/LusicGal';
const h = { 'User-Agent': 'lg' };
const sha = process.argv[2];
const sleep = (ms) => new Promise(z => setTimeout(z, ms));
(async () => {
  const dl = Date.now() + 45 * 60 * 1000;
  while (Date.now() < dl) {
    try {
      const r = await fetch(`https://api.github.com/repos/${repo}/actions/runs?head_sha=${sha}&per_page=10`, { headers: h });
      if (r.status === 200) {
        const j = await r.json();
        if (j.workflow_runs.length === 0) { console.log('no runs yet'); }
        else {
          let pend = false;
          for (const x of j.workflow_runs) {
            console.log(x.id, x.name.padEnd(10), (x.event + '').padEnd(18), (x.status + '').padEnd(12), x.conclusion || '-');
            if (x.status !== 'completed') pend = true;
          }
          if (!pend) { console.log('ALL SETTLED'); process.exit(0); }
        }
      } else console.log('http', r.status);
    } catch (e) { console.log('err', e.message); }
    await sleep(90000);
  }
  console.log('TIMEOUT');
  process.exit(2);
})();
