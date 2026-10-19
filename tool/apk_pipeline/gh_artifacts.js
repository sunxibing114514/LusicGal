'use strict';
// 下载一次 run 的全部 artifacts 到 build/ci_cores/。
// 用法：node gh_artifacts.js <run_id>
const fs = require('fs');
const path = require('path');
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
const outDir = path.join('C:', 'LusicGal', 'build', 'ci_cores');
fs.mkdirSync(outDir, { recursive: true });
(async () => {
  const id = process.argv[2];
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const arts = await (await fetch(`https://api.github.com/repos/${repo}/actions/runs/${id}/artifacts?per_page=50`, { headers: h })).json();
  for (const a of arts.artifacts || []) {
    const dest = path.join(outDir, a.name + '.zip');
    console.log(`↓ ${a.name} (${(a.size_in_bytes / 1048576).toFixed(1)}MB)`);
    const res = await fetch(a.archive_download_url, { headers: h });
    if (!res.ok) { console.error('  HTTP', res.status); continue; }
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(dest, buf);
    console.log(`  ✓ ${dest}`);
  }
  console.log('DONE');
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
