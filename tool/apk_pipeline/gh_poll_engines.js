'use strict';
// 轮询 engines.yml 对指定 sha 的 run 直至完成。
// 用法：node gh_poll_engines.js <sha> [intervalSec=60] [maxMin=150]
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
const sha = process.argv[2];
const interval = (parseInt(process.argv[3] || '60', 10)) * 1000;
const maxMin = parseInt(process.argv[4] || '150', 10);
const deadline = Date.now() + maxMin * 60000;
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
(async () => {
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  let run = null;
  const wantEvent = process.env.POLL_EVENT || '';
  while (Date.now() < deadline) {
    const runs = await (await fetch(`https://api.github.com/repos/${repo}/actions/workflows/engines.yml/runs?per_page=8`, { headers: h })).json();
    run = (runs.workflow_runs || []).find(r => r.head_sha.startsWith(sha) && (!wantEvent || r.event === wantEvent));
    if (run) break;
    console.log('等待 engines run 出现…');
    await sleep(interval);
  }
  if (!run) { console.log('NO_RUN'); process.exit(1); }
  console.log(`run ${run.id} :: ${run.html_url}`);
  while (Date.now() < deadline) {
    const rd = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs/${run.id}`, { headers: h })).json();
    const jobs = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs/${run.id}/jobs?per_page=50`, { headers: h })).json();
    const lines = (jobs.jobs || []).filter(j => j.status !== 'skipped')
      .map(j => `  ${j.name} :: ${j.status}/${j.conclusion ?? '…'}`);
    console.log(`[${new Date().toISOString()}] run=${rd.status}/${rd.conclusion ?? '…'}\n${lines.join('\n')}`);
    if (rd.status === 'completed') {
      console.log('RUN_DONE conclusion=' + rd.conclusion);
      return;
    }
    await sleep(interval);
  }
  console.log('TIMEOUT');
  process.exit(2);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
