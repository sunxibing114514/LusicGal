'use strict';
// 观察某 workflow（默认 app.yml）在指定 sha 上的最新 run：每 interval 秒列
// job 状态，直到完成或超 max 分钟。用法：
//   node gh_poll_wf.js <sha7|runId> [intervalSec] [maxMin]
// runId（纯数字）= 直接盯该 run；否则按 sha（可加 POLL_EVENT 过滤）找。
const token = process.env.LUSICGAL_GH_TOKEN || '';
const wf = process.env.POLL_WF || 'app.yml';
const repo = 'sunxibing114514/LusicGal';
const key = process.argv[2];
const interval = Number(process.argv[3] || 120);
const maxMin = Number(process.argv[4] || 180);

if (!key) { console.error('用法: node gh_poll_wf.js <sha7|runId> [intervalSec] [maxMin]'); process.exit(1); }

(async () => {
  const deadline = Date.now() + maxMin * 60 * 1000;
  let run = null;
  if (/^\d+$/.test(key)) {
    run = { id: key, html_url: `https://github.com/${repo}/actions/runs/${key}` };
  }
  while (Date.now() < deadline) {
    if (!run) {
      const wantEvent = process.env.POLL_EVENT || '';
      for (let page = 1; page <= 3 && !run; page++) {
        const r = await fetch(`https://api.github.com/repos/${repo}/actions/workflows/${wf}/runs?per_page=50&page=${page}`, {
          headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), 'User-Agent': 'lg' },
        }).then(x => x.json());
        const cand = (r.workflow_runs || []).filter(x => x.head_sha.startsWith(key)
          && (!wantEvent || x.event === wantEvent));
        run = cand[0] || null;
      }
      if (!run) { console.log(`等待 ${wf} run 出现…`); await new Promise(z => setTimeout(z, interval * 1000)); continue; }
    }
    const info = await fetch(`https://api.github.com/repos/${repo}/actions/runs/${run.id}`, {
      headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), 'User-Agent': 'lg' },
    }).then(x => x.json());
    const j = await fetch(`https://api.github.com/repos/${repo}/actions/runs/${run.id}/jobs?per_page=50`, {
      headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), 'User-Agent': 'lg' },
    }).then(x => x.json());
    console.log(`\n[${new Date().toISOString()}] run=${info.status}/${info.conclusion ?? '…'} :: ${info.html_url}`);
    for (const job of j.jobs || []) {
      console.log(`  ${job.name} :: ${job.status}/${job.conclusion ?? '…'}`);
    }
    if (info.status === 'completed') {
      console.log(`RUN_DONE conclusion=${info.conclusion}`);
      process.exit(info.conclusion === 'success' ? 0 : 1);
    }
    await new Promise(z => setTimeout(z, interval * 1000));
  }
  console.log('TIMEOUT');
  process.exit(2);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
