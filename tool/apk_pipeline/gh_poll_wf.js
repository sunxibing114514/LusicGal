'use strict';
// 观察某 workflow（默认 app.yml）在指定 sha 上的最新 run：每 interval 秒列
// job 状态，直到完成或超 max 分钟。用法：
//   POLL_WF=app.yml node gh_poll_wf.js <sha7> [intervalSec] [maxMin]
const token = process.env.LUSICGAL_GH_TOKEN;
const wf = process.env.POLL_WF || 'app.yml';
const repo = 'sunxibing114514/LusicGal';
const sha = process.argv[2];
const interval = Number(process.argv[3] || 120);
const maxMin = Number(process.argv[4] || 180);

if (!sha) { console.error('用法: node gh_poll_wf.js <sha7> [intervalSec] [maxMin]'); process.exit(1); }

(async () => {
  const deadline = Date.now() + maxMin * 60 * 1000;
  let seen = 0;
  while (Date.now() < deadline) {
    let run = null;
    const wantEvent = process.env.POLL_EVENT || '';
    for (let page = 1; page <= 3 && !run; page++) {
      const r = await fetch(`https://api.github.com/repos/${repo}/actions/workflows/${wf}/runs?per_page=50&page=${page}`, {
        headers: { Authorization: `Bearer ${token}`, 'User-Agent': 'lg' },
      }).then(x => x.json());
      const cand = (r.workflow_runs || []).filter(x => x.head_sha.startsWith(sha)
        && (!wantEvent || x.event === wantEvent));
      run = cand[0] || null;
    }
    if (!run) { console.log(`等待 ${wf} run 出现…`); await new Promise(z => setTimeout(z, interval * 1000)); continue; }
    const j = await fetch(`https://api.github.com/repos/${repo}/actions/runs/${run.id}/jobs?per_page=50`, {
      headers: { Authorization: `Bearer ${token}`, 'User-Agent': 'lg' },
    }).then(x => x.json());
    console.log(`\n[${new Date().toISOString()}] run=${run.status}/${run.conclusion ?? '…'} :: ${run.html_url}`);
    for (const job of j.jobs || []) {
      console.log(`  ${job.name} :: ${job.status}/${job.conclusion ?? '…'}`);
    }
    if (run.status === 'completed') {
      console.log(`RUN_DONE conclusion=${run.conclusion}`);
      process.exit(run.conclusion === 'success' ? 0 : 1);
    }
    await new Promise(z => setTimeout(z, interval * 1000));
  }
  console.log('TIMEOUT');
  process.exit(2);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
