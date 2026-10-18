'use strict';
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const r = await fetch(`https://api.github.com/repos/${repo}`, {
    method: 'PATCH', headers: { ...h, 'Content-Type': 'application/json' },
    body: JSON.stringify({ private: false }),
  });
  const j = await r.json();
  console.log('status', r.status, '| private =', j.private, '| html_url =', j.html_url || j.message);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
