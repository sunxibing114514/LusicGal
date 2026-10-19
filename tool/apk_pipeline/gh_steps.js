'use strict';
// 匿名列 run 的 job/step 态 + 出败步名。用法: node gh_steps.js <runId>
const h = { 'User-Agent': 'lg' };
const repo = 'sunxibing114514/LusicGal';
async function getJson(url, tries = 8) {
  for (let a = 0; a < tries; a++) {
    try {
      const r = await fetch(url, { headers: h });
      if (r.status === 200) return await r.json();
      console.log('http', r.status, 'attempt', a);
    } catch (e) { console.log('err', e.message, 'attempt', a); }
    await new Promise(z => setTimeout(z, 10000));
  }
  return null;
}
(async () => {
  const runId = process.argv[2];
  const j = await getJson(`https://api.github.com/repos/${repo}/actions/runs/${runId}/jobs`);
  if (!j) { console.log('JOBS FAIL'); process.exit(1); }
  for (const job of j.jobs) {
    if (job.conclusion === 'skipped' || job.name.indexOf('ios') >= 0) continue;
    console.log('== ' + job.name + ' :: ' + job.conclusion);
    for (const s of job.steps) {
      const mark = (s.status === 'completed' && s.conclusion !== 'success' && s.conclusion !== 'skipped') ? 'XX' : '  ';
      console.log(`${mark} ${s.name} :: ${s.conclusion ?? s.status}`);
    }
  }
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
