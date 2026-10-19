'use strict';
const token = process.env.LUSICGAL_GH_TOKEN;
const repo = 'sunxibing114514/LusicGal';
(async () => {
  const h = { Authorization: `Bearer ${token}`, 'User-Agent': 'lg', Accept: 'application/vnd.github+json' };
  const rels = await (await fetch(`https://api.github.com/repos/${repo}/releases?per_page=10`, { headers: h })).json();
  for (const r of rels) {
    console.log(`release ${r.tag_name} :: id=${r.id} :: ${r.name}`);
    for (const a of r.assets) console.log(`  asset id=${a.id} ${a.name} ${(a.size / 1048576).toFixed(1)}MB dl=${a.browser_download_url}`);
  }
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
