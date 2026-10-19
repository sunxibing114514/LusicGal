'use strict';
const token = process.env.LUSICGAL_GH_TOKEN;
const h = { Authorization: 'Bearer ' + token, 'User-Agent': 'lg' };
const repo = 'sunxibing114514/LusicGal';
async function tryFetch(url, tries, waitMs) {
  for (let a = 0; a < tries; a++) {
    try {
      const r = await fetch(url, { headers: h });
      if (r.status === 200) return r;
      console.log('http', r.status, 'attempt', a, url.slice(-70));
    } catch (e) { console.log('err', e.message, 'attempt', a); }
    await new Promise(z => setTimeout(z, waitMs));
  }
  return null;
}
(async () => {
  const jr = await tryFetch(`https://api.github.com/repos/${repo}/actions/runs/39263123330/jobs`, 12, 15000);
  if (!jr) { console.log('JOBS FAIL'); process.exit(1); }
  const j = await jr.json();
  const job = j.jobs.find(x => x.name.indexOf('\u5168\u91cf') >= 0);
  console.log('job', job.id, job.conclusion);
  const lr = await tryFetch(`https://api.github.com/repos/${repo}/actions/jobs/${job.id}/logs`, 12, 15000);
  if (!lr) { console.log('LOGS FAIL'); process.exit(1); }
  const txt = await lr.text();
  require('fs').writeFileSync('C:/LusicGal/.toolchain/fullapk6.log', txt);
  console.log('log bytes', txt.length);
  const lines = txt.split('\n');
  const idx = lines.findIndex(l => /What went wrong/.test(l));
  if (idx >= 0) for (const q of lines.slice(idx, idx + 16)) console.log(q.slice(0, 240));
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
