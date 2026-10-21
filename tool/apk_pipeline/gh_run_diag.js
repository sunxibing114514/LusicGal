'use strict';
// 诊断工具：列出指定 run 的 jobs/steps 结论（token 或匿名均可，日志需 token）。
const REPO = 'sunxibing114514/LusicGal';
const TOK = process.env.LGT || '';
const runId = process.argv[2];
(async () => {
  const headers = { 'User-Agent': 'lg' };
  if (TOK) headers.Authorization = 'Bearer ' + TOK;
  const r = await fetch(`https://api.github.com/repos/${REPO}/actions/runs/${runId}/jobs?per_page=50`, { headers });
  const j = await r.json();
  console.log('http', r.status);
  for (const job of j.jobs || []) {
    console.log(`\n== JOB ${job.name} [${job.conclusion}] (id=${job.id})`);
    for (const s of job.steps || []) {
      console.log(`  ${s.conclusion === 'success' ? '  ok' : (s.conclusion || s.status).padEnd(5).slice(0, 5)} ${s.name}`);
    }
    if (job.conclusion !== 'success') {
      // 拉失败 job 的日志（jobs 列表不再带 logs_url —— 现拼 job 日志端点）。
      try {
        const lr = await fetch(`https://api.github.com/repos/${REPO}/actions/jobs/${job.id}/logs`, { headers, redirect: 'follow' });
        if (lr.ok) {
          const text = await lr.text();
          const lines = text.split('\n').filter(l => /error|Error|FAILED|failure|Exception|✗|失败|warning/i.test(l));
          console.log('  --- 日志关键行（尾部 80）---');
          for (const l of lines.slice(-80)) console.log('  ' + l.replace(/\r/g, '').slice(0, 400));
        } else console.log('  logs http ' + lr.status);
      } catch (e) { console.log('  logs err ' + e.message); }
    }
  }
})();
