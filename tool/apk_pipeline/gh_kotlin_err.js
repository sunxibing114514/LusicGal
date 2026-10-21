'use strict';
// 下载指定 job 的完整日志，抓 Kotlin 编译错误行（e: 前缀）及上下文。
const REPO = 'sunxibing114514/LusicGal';
const TOK = process.env.LGT || '';
const jobId = process.argv[2];
(async () => {
  const headers = { 'User-Agent': 'lg' };
  if (TOK) headers.Authorization = 'Bearer ' + TOK;
  const lr = await fetch(`https://api.github.com/repos/${REPO}/actions/jobs/${jobId}/logs`, { headers, redirect: 'follow' });
  console.log('http', lr.status);
  const text = await lr.text();
  const lines = text.split('\n');
  const hits = [];
  lines.forEach((l, i) => {
    if (/^.*\se: /.test(l) || /error:/.test(l) && /kt/i.test(l)) hits.push(i);
  });
  if (!hits.length) {
    console.log('--- 未匹配 e: 行；打印 compileReleaseKotlin 附近 60 行 ---');
    const idx = lines.findIndex(l => l.includes('compileReleaseKotlin'));
    const from = Math.max(0, idx - 40), to = Math.min(lines.length, idx + 40);
    for (const l of lines.slice(from, to)) console.log(l.replace(/\r/g, '').slice(0, 500));
  } else {
    for (const i of hits) {
      for (const l of lines.slice(Math.max(0, i - 2), i + 3)) console.log(l.replace(/\r/g, '').slice(0, 500));
      console.log('----');
    }
  }
})();
