'use strict';
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const r = await (await fetch(`https://api.github.com/repos/${repo}`, { headers: h })).json();
  console.log('private =', r.private, '| default_branch =', r.default_branch, '| permissions =', JSON.stringify(r.permissions));
  const perm = await fetch(`https://api.github.com/repos/${repo}/actions/permissions`, { headers: h });
  console.log('actions/permissions:', perm.status, JSON.stringify(await perm.json()));
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
