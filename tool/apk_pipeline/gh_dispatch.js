'use strict';
// 触发 engines.yml 的 workflow_dispatch（跑手动实验腿：kirikiri/renpy 等）。
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const r = await fetch(`https://api.github.com/repos/${repo}/actions/workflows/engines.yml/dispatches`, {
    method: 'POST', headers: { ...h, 'Content-Type': 'application/json' },
    body: JSON.stringify({ ref: 'main' }),
  });
  console.log('dispatch status', r.status, r.status === 204 ? 'OK' : await r.text());
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
