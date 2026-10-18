'use strict';
(async () => {
  const r = await fetch('https://api.github.com/repos/mstorsjo/llvm-mingw/releases/latest', {
    headers: { 'user-agent': 'LusicGal-builder' },
  });
  const j = await r.json();
  console.log('tag:', j.tag_name);
  for (const a of j.assets || []) {
    if (/ucrt-x86_64\.zip$/.test(a.name)) {
      console.log('asset:', a.name, (a.size / 1048576).toFixed(1) + 'MB');
      console.log('url:', a.browser_download_url);
    }
  }
})();
