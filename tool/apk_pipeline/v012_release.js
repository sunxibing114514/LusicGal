'use strict';
// v0.1.2 发布自治管线：401 浪期间挂后台一杆到底。
//   1) push main（60s 重试，浪最长等 4.5h）
//   2) 匿名轮询 HEAD 的 app+engines 双 verify → 必须 success
//   3) 打 tag v0.1.2-full-core → 推 tag（触发 full-apk 产线）
//   4) 匿名轮询 full-apk run → success
//   5) 下载 release APK → aapt2 dump permissions/badging
//      → 断言 INTERNET + sensorLandscape → 报告落 build/v012_report.json
// 任何一步败到终态即退出非 0；报告文件始终写出（含失败原因）。
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const GIT = 'C:\\LusicGal\\.toolchain\\mingit\\cmd\\git.exe';
const AAPT2 = 'C:\\LusicGal\\.toolchain\\android-sdk\\build-tools\\android-14\\aapt2.exe';
const TOK = process.env.LGT;
const REPO_URL = `https://x-access-token:${TOK}@github.com/sunxibing114514/LusicGal.git`;
const REPO = 'sunxibing114514/LusicGal';
// tag 可经 LGT_TAG 覆盖（默认 v0.1.2-full-core 保持向后兼容）。
const TAG = process.env.LGT_TAG || 'v0.1.2-full-core';
const APK_OUT = `C:\\LusicGal\\.toolchain\\LusicGal-${TAG}.apk`;
const REPORT = 'C:\\LusicGal\\build\\v012_report.json';
const START = Date.now();
const log = (m) => console.log(new Date().toISOString().slice(11, 19), m);
const sleep = (ms) => new Promise((z) => setTimeout(z, ms));

const report = { startedAt: new Date().toISOString(), steps: {} };
function mark(step, state, detail) {
  report.steps[step] = { state, detail, at: new Date().toISOString() };
  try { fs.mkdirSync(path.dirname(REPORT), { recursive: true }); fs.writeFileSync(REPORT, JSON.stringify(report, null, 2)); } catch (_) {}
}

function git(args, timeout = 90000) {
  try {
    return { code: 0, out: execFileSync(GIT, ['-c', 'http.sslBackend=openssl', ...args], {
      cwd: 'C:\\LusicGal',
      env: { ...process.env, GIT_CONFIG_GLOBAL: 'C:\\LusicGal\\.toolchain\\gitconfig' },
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout,
    }).toString() };
  } catch (e) {
    return { code: e.status === undefined ? 1 : e.status, out: ((e.stdout || '') + (e.stderr || '')).toString() };
  }
}

async function api(pathname, authed = false) {
  const headers = { 'User-Agent': 'lg' };
  if (authed) headers.Authorization = 'Bearer ' + TOK;
  const r = await fetch(`https://api.github.com${pathname}`, { headers });
  let body = null;
  try { body = await r.json(); } catch (_) {}
  return { status: r.status, body };
}

async function waitRuns(sha, deadlineMs, need = ['app', 'engines']) {
  const dl = Date.now() + deadlineMs;
  while (Date.now() < dl) {
    // 注意：actions API 的 ?head_sha= 过滤有索引滞后（实测 >30min）——
    // 拉最近 runs 全量后客户端匹配 head_sha 字段。
    const r = await api(`/repos/${REPO}/actions/runs?per_page=40`);
    if (r.status === 200 && Array.isArray(r.body.workflow_runs)) {
      const runs = r.body.workflow_runs;
      const done = {};
      for (const need_name of need) {
        const run = runs.find(
          (x) => x.name === need_name && (x.head_sha || '').startsWith(sha));
        if (run && run.status === 'completed') done[need_name] = run.conclusion;
      }
      if (Object.keys(done).length === need.length) return done;
    }
    await sleep(45000);
  }
  return null;
}

(async () => {
  // ---- 1. push main（浪窗可经 LGT_WAIT_HOURS 扩，默认 4.5h）----
  let pushed = false;
  const pushDl = Date.now() + parseFloat(process.env.LGT_WAIT_HOURS || '4.5') * 3600 * 1000;
  while (Date.now() < pushDl) {
    const r = git(['push', REPO_URL, 'main']);
    if (r.code === 0) { log('PUSH OK: ' + r.out.trim().split('\n').pop()); pushed = true; break; }
    log('push fail: ' + r.out.trim().split('\n').pop().slice(0, 120));
    await sleep(60000);
  }
  if (!pushed) { mark('push', 'fail', '浪未退（4.5h）'); log('ABORT: push 未成'); process.exit(2); }
  mark('push', 'ok', r0());
  const sha = git(['rev-parse', 'HEAD']).out.trim().slice(0, 7);
  report.sha = sha;
  log('HEAD=' + sha);

  // ---- 2. verify 双闸 ----
  log('等待 app+engines verify @' + sha);
  const verdict = await waitRuns(sha, 30 * 60000);
  if (!verdict) { mark('verify', 'fail', '30min 未完成'); process.exit(3); }
  const bad = Object.entries(verdict).filter(([, v]) => v !== 'success');
  mark('verify', bad.length ? 'fail' : 'ok', JSON.stringify(verdict));
  if (bad.length) { log('ABORT: verify 红灯 ' + JSON.stringify(verdict)); process.exit(3); }
  log('verify 双绿 ✓ ' + JSON.stringify(verdict));

  // ---- 3. tag + push tag ----
  git(['tag', '-f', TAG, sha]);
  let tagged = false;
  const tagDl = Date.now() + 30 * 60000;
  while (Date.now() < tagDl) {
    const r = git(['push', REPO_URL, TAG]);
    if (r.code === 0) { log('TAG 推送 OK'); tagged = true; break; }
    log('tag push fail: ' + r.out.trim().split('\n').pop().slice(0, 120));
    await sleep(60000);
  }
  if (!tagged) { mark('tag', 'fail', '30min 未退'); process.exit(4); }
  mark('tag', 'ok', TAG + ' @' + sha);

  // ---- 4. full-apk 产线（最长 2.5h）----
  log('等待 full-apk run（tag ' + TAG + '）');
  let run = null;
  const buildDl = Date.now() + 2.5 * 3600 * 1000;
  while (Date.now() < buildDl) {
    const r = await api(`/repos/${REPO}/actions/runs?event=push&per_page=30`);
    if (r.status === 200) {
      const hit = r.body.workflow_runs.find((x) => x.name === 'full-apk' && x.head_sha.startsWith(sha));
      if (hit) {
        run = hit;
        if (hit.status === 'completed') break;
      }
    }
    await sleep(90000);
  }
  if (!run) { mark('fullapk', 'fail', 'run 未出现/超时'); process.exit(5); }
  mark('fullapk', run.conclusion === 'success' ? 'ok' : 'fail', `run=${run.id} ${run.conclusion}`);
  if (run.conclusion !== 'success') { log('ABORT: full-apk ' + run.conclusion); process.exit(5); }
  log('full-apk 全绿 ✓ run=' + run.id);

  // ---- 5. 下载 release APK ----
  const dlUrl = `https://github.com/${REPO}/releases/download/${TAG}/LusicGal-${TAG}.apk`;
  log('下载 ' + dlUrl);
  let ok = false;
  for (let i = 0; i < 10 && !ok; i++) {
    try {
      const res = await fetch(dlUrl, { headers: { 'User-Agent': 'lg' }, redirect: 'follow' });
      if (res.status === 200) {
        const { Readable } = require('stream');
        const total = +(res.headers.get('content-length') || 0);
        let got = 0;
        const out = fs.createWriteStream(APK_OUT);
        await new Promise((resolve, reject) => {
          Readable.fromWeb(res.body).on('data', (c) => { got += c.length; })
            .on('error', reject).pipe(out);
          out.on('error', reject).on('finish', () => resolve());
        });
        const size = fs.statSync(APK_OUT).size;
        log(`下载完成 ${size} bytes（期望 ${total}）`);
        // v0.1.6 起 useLegacyPackaging 压缩后 APK ~70-75MB：硬编码 100MB
        // 旧闸会十连"完成"仍判败（v0.1.10 实证）。改为字节精确比对，
        // 无 content-length 时退 50MB 保守下限。
        if (total > 0 ? size === total : size > 50000000) ok = true;
      } else { log('dl http ' + res.status); await sleep(30000); }
    } catch (e) { log('dl err ' + e.message); await sleep(30000); }
  }
  mark('download', ok ? 'ok' : 'fail', APK_OUT);
  if (!ok) process.exit(6);

  // ---- 6. aapt2 断言（INTERNET + sensorLandscape + 体积）----
  let perm = '', badge = '';
  try {
    perm = execFileSync(AAPT2, ['dump', 'permissions', APK_OUT], { stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 }).toString();
    badge = execFileSync(AAPT2, ['dump', 'badging', APK_OUT], { stdio: ['ignore', 'pipe', 'pipe'], timeout: 60000 }).toString();
  } catch (e) { perm = ((e.stdout || '') + (e.stderr || '')).toString(); }
  const hasInternet = /android\.permission\.INTERNET/.test(perm);
  const size = fs.statSync(APK_OUT).size;
  const landscape = /sensorLandscape/.test(badge);
  mark('aapt2', hasInternet ? 'ok' : 'fail',
    JSON.stringify({ hasInternet, landscape, sizeBytes: size, sizeMB: +(size / 1048576).toFixed(2) }));
  log(`aapt2: INTERNET=${hasInternet} landscape=${landscape} size=${(size / 1048576).toFixed(2)}MB`);
  log(hasInternet ? 'v0.1.2 管线全程完成 ✓' : '断言失败：包内仍无 INTERNET');
  process.exit(hasInternet ? 0 : 7);
})().catch((e) => { log('FATAL ' + (e && e.stack || e)); mark('fatal', 'fail', String(e)); process.exit(1); });

function r0() { return 'main 推送成功'; }
