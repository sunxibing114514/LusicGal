'use strict';
// 带重试的 workflow_dispatch（平台 401/502 波动期）。
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
const wf = process.argv[2] || 'app.yml';
(async () => {
  for (let a = 0; a < 20; a++) {
    try {
      const r = await fetch(`https://api.github.com/repos/${repo}/actions/workflows/${wf}/dispatches`, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + token, 'User-Agent': 'lg', Accept: 'application/vnd.github+json', 'Content-Type': 'application/json' },
        body: JSON.stringify({ ref: 'main' }),
      });
      console.log('attempt', a, 'status', r.status);
      if (r.status === 204) { console.log('DISPATCH_OK'); process.exit(0); }
    } catch (e) { console.log('attempt', a, e.message); }
    await new Promise(z => setTimeout(z, 20000));
  }
  console.log('DISPATCH_GAVEUP');
  process.exit(1);
})();
