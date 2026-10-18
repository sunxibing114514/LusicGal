'use strict';
// 列出一次 run 的 jobs 与失败步骤摘要。
// 用法：node gh_jobs.js <run_id> [只看失败: fail]
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const id = process.argv[2];
  const onlyFail = process.argv[3] === 'fail';
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const jobs = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs/${id}/jobs?per_page=50`, { headers: h })).json();
  for (const j of jobs.jobs || []) {
    if (onlyFail && j.conclusion !== 'failure') continue;
    console.log(`== ${j.name} :: ${j.status}/${j.conclusion}`);
    for (const s of j.steps || []) {
      if (s.conclusion === 'failure') console.log(`   FAILSTEP: ${s.name} (${s.number})`);
    }
  }
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
