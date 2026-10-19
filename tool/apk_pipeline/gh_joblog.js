'use strict';
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const id = process.argv[2];
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const jobs = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs/${id}/jobs?per_page=50`, { headers: h })).json();
  for (const j of jobs.jobs || []) {
    if (j.conclusion !== 'failure') continue;
    console.log(`\n######## ${j.name}`);
    for (const s of j.steps) console.log(`  ${s.number}. ${s.status}/${s.conclusion} :: ${s.name}`);
    const lg = await fetch(`https://api.github.com/repos/${repo}/actions/jobs/${j.id}/logs`, { headers: h });
    const body = await lg.text();
    // 尾部 3500 字符（错误通常在尾部）
    console.log('--- LOG tail ---');
    console.log(body.slice(-3500));
  }
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
