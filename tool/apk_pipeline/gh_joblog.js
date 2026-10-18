'use strict';
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const id = process.argv[2];
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const jobs = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs/${id}/jobs?per_page=50`, { headers: h })).json();
  const j = (jobs.jobs || []).find(x => x.name.includes(process.argv[3] || 'sena'));
  console.log('job', j.id, j.status, j.conclusion, 'runner:', j.runner_name, 'labels:', (j.labels||[]).join(','));
  for (const s of j.steps) console.log(`  ${s.number}. ${s.status}/${s.conclusion} :: ${s.name}`);
  // 拉该 job 的日志（text/plain）
  const lg = await fetch(`https://api.github.com/repos/${repo}/actions/jobs/${j.id}/logs`, { headers: h });
  const body = await lg.text();
  console.log('=== LOG tail ===');
  console.log(body.slice(-3000));
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
