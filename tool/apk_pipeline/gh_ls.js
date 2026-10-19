'use strict';
// 列 GitHub 目录（含 symlink 目标）。用法: node gh_ls.js <owner/repo> <path> <ref> [raw]
const token = process.env.LUSICGAL_GH_TOKEN;
const h = { 'User-Agent': 'lg', Accept: 'application/vnd.github+json', ...(token ? { Authorization: 'Bearer ' + token } : {}) };
(async () => {
  const [repo, path, ref] = process.argv.slice(2);
  const r = await fetch(`https://api.github.com/repos/${repo}/contents/${path}?ref=${ref}`, { headers: h });
  console.log('status', r.status);
  const j = await r.json();
  if (!Array.isArray(j)) { console.log(JSON.stringify(j).slice(0, 300)); process.exit(1); }
  for (const x of j) console.log(x.type.padEnd(5), x.name.padEnd(30), x.target || '', x.size || '');
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
