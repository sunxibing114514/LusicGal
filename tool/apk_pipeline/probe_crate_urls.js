'use strict';
const cands = [
  'https://rsproxy.cn/crates/ab_glyph_rasterizer/0.1.10/download',
  'https://rsproxy.cn/crates.io/crates/ab_glyph_rasterizer/0.1.10/download',
  'https://rsproxy.cn/api/v1/crates/ab_glyph_rasterizer/0.1.10/download',
  'https://crates.io/api/v1/crates/ab_glyph_rasterizer/0.1.10/download',
];
(async () => {
  for (const u of cands) {
    try {
      const r = await fetch(u);
      const len = r.headers.get('content-length') || (r.body ? 'stream' : 0);
      console.log(r.status, len, u);
    } catch (e) { console.log('ERR', e.message, u); }
  }
})();
