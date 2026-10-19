'use strict';
// 取 GitHub 单文件原文。用法: node gh_cat.js <owner/repo> <path> <ref> <outFile>
const token = process.env.LUSICGAL_GH_TOKEN;
(async () => {
  const [repo, path, ref, out] = process.argv.slice(2);
  const h = { 'User-Agent': 'lg', Accept: 'application/vnd.github.raw', ...(token ? { Authorization: 'Bearer ' + token } : {}) };
  for (let a = 0; a < 10; a++) {
    try {
      const r = await fetch(`https://api.github.com/repos/${repo}/contents/${path}?ref=${ref}`, { headers: h });
      if (r.status === 200) {
        const t = await r.text();
        require('fs').writeFileSync(out, t);
        console.log('saved', out, t.length);
        process.exit(0);
      }
      console.log('http', r.status, 'attempt', a);
    } catch (e) { console.log('err', e.message, 'attempt', a); }
    await new Promise(z => setTimeout(z, 10000));
  }
  console.log('GAVEUP');
  process.exit(1);
})();
