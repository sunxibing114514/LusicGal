'use strict';
// 拉一次 run 内指定名称 job 的日志尾部（不依赖步骤表）。
// 用法：node gh_jobtail.js <run_id> <job名匹配串> [tailChars=6000]
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const id = process.argv[2], m = process.argv[3] || '', tail = parseInt(process.argv[4] || '6000', 10);
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const jobs = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs/${id}/jobs?per_page=50`, { headers: h })).json();
  for (const j of jobs.jobs || []) {
    if (!j.name.includes(m)) continue;
    console.log(`\n######## ${j.name} :: ${j.conclusion}`);
    const lg = await fetch(`https://api.github.com/repos/${repo}/actions/jobs/${j.id}/logs`, { headers: h });
    const body = await lg.text();
    console.log(body.slice(-tail));
  }
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
