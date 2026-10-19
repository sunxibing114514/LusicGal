'use strict';
// token 恢复哨：每 60s 探 /user；恢复后拉 round7 job 日志存盘并抽错误段。
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
const h = { Authorization: 'Bearer ' + token, 'User-Agent': 'lg' };
const sleep = (ms) => new Promise(z => setTimeout(z, ms));
(async () => {
  const deadline = Date.now() + 90 * 60 * 1000;
  while (Date.now() < deadline) {
    try {
      const u = await fetch('https://api.github.com/user', { headers: h });
      if (u.status === 200) {
        console.log('token recovered', new Date().toISOString());
        // 拉 jobs
        let j = null;
        for (let a = 0; a < 8 && !j; a++) {
          const jr = await fetch(`https://api.github.com/repos/${repo}/actions/runs/39282278813/jobs`, { headers: h });
          if (jr.status === 200) j = await jr.json(); else { console.log('jobs', jr.status); await sleep(15000); }
        }
        if (!j) { console.log('JOBS STILL FAIL'); process.exit(1); }
        const job = j.jobs.find(x => x.name.indexOf('\u5168\u91cf') >= 0);
        const lr = await fetch(`https://api.github.com/repos/${repo}/actions/jobs/${job.id}/logs`, { headers: h });
        if (lr.status !== 200) { console.log('logs', lr.status); process.exit(1); }
        const txt = await lr.text();
        require('fs').writeFileSync('C:/LusicGal/.toolchain/fullapk7.log', txt);
        console.log('log bytes', txt.length);
        const lines = txt.split('\n');
        const idx = lines.findIndex(l => /What went wrong/.test(l));
        if (idx >= 0) for (const q of lines.slice(idx, idx + 18)) console.log(q.slice(0, 250));
        else console.log('NO-What-went-wrong line?! tail:');
        if (idx < 0) for (const q of lines.slice(-40)) console.log(q.slice(0, 250));
        process.exit(0);
      }
      if (u.status !== 401) console.log('user probe status', u.status);
    } catch (e) { console.log('probe err', e.message); }
    await sleep(60000);
  }
  console.log('TIMEOUT token never recovered');
  process.exit(2);
})();
