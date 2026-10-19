'use strict';
// 列 run 工件 + 下载指定名。用法:
//   node gh_artifact_dl.js <runId> [nameSubstr]
const token = process.env.LUSICGAL_GH_TOKEN;
const fs = require('fs');
const repo = 'sunxibing114514/LusicGal';
const h = { Authorization: 'Bearer ' + token, 'User-Agent': 'lg' };
const sleep = (ms) => new Promise(z => setTimeout(z, ms));
async function getJson(url, tries = 8) {
  for (let a = 0; a < tries; a++) {
    try {
      const r = await fetch(url, { headers: h });
      if (r.status === 200) return await r.json();
      console.log('http', r.status, 'attempt', a, url.slice(-60));
    } catch (e) { console.log('err', e.message, 'attempt', a); }
    await sleep(12000);
  }
  return null;
}
(async () => {
  const runId = process.argv[2];
  const want = process.argv[3] || '';
  const j = await getJson(`https://api.github.com/repos/${repo}/actions/runs/${runId}/artifacts`);
  if (!j) { console.log('ARTIFACTS FAIL'); process.exit(1); }
  for (const a of j.artifacts) console.log(a.id, a.name, a.size_in_bytes);
  if (!want) process.exit(0);
  const a = j.artifacts.find(x => x.name.indexOf(want) >= 0);
  if (!a) { console.log('NOT FOUND', want); process.exit(1); }
  for (let t = 0; t < 8; t++) {
    try {
      const r = await fetch(a.archive_download_url, { headers: h });
      if (r.status === 200) {
        const b = Buffer.from(await r.arrayBuffer());
        const out = `C:/LusicGal/.toolchain/${a.name}.zip`;
        fs.writeFileSync(out, b);
        console.log('saved', out, b.length);
        process.exit(0);
      }
      console.log('dl http', r.status, 'attempt', t);
    } catch (e) { console.log('dl err', e.message, 'attempt', t); }
    await sleep(15000);
  }
  console.log('DOWNLOAD GAVEUP');
  process.exit(1);
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
