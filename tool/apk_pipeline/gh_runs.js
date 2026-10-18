'use strict';
// 查询 LusicGal 仓库 engines workflow 的最近 runs（及四核矩阵状态）。
// 用法：node gh_runs.js [maxRuns]
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const max = parseInt(process.argv[2] || '6', 10);
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const runs = await (await fetch(`https://api.github.com/repos/${repo}/actions/workflows/engines.yml/runs?per_page=${max}`, { headers: h })).json();
  for (const r of runs.workflow_runs || []) {
    console.log(`${r.id} ${r.status}/${r.conclusion} ${r.head_sha.slice(0,7)} ${r.created_at} ${r.event}`);
  }
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
