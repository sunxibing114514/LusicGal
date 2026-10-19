'use strict';
const h = { 'User-Agent': 'lg' };
const repo = 'sunxibing114514/LusicGal';
async function getJson(url, tries = 6) {
  for (let a = 0; a < tries; a++) {
    try {
      const r = await fetch(url, { headers: h });
      if (r.status === 200) return await r.json();
      console.log('http', r.status, 'attempt', a, url.slice(-60));
    } catch (e) { console.log('err', e.message, 'attempt', a); }
    await new Promise(z => setTimeout(z, 8000));
  }
  return null;
}
(async () => {
  const j = await getJson(`https://api.github.com/repos/${repo}/actions/runs/39263123330/jobs`);
  if (!j || !j.jobs) { console.log('JOBS FAIL'); process.exit(1); }
  const job = j.jobs.find(x => x.name.indexOf('\u5168\u91cf') >= 0); // 全量
  console.log('job', job && job.name, job && job.conclusion);
  const cs = await getJson(`https://api.github.com/repos/${repo}/commits/7a21655/check-runs`);
  if (!cs || !cs.check_runs) { console.log('CHECK RUNS FAIL'); process.exit(1); }
  for (const cr of cs.check_runs) {
    if (cr.conclusion === 'failure' && cr.name === job.name) {
      const a = await getJson(cr.url + '/annotations');
      for (const an of a || []) console.log('ANN:', (an.message || '').slice(0, 400));
    }
  }
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
