'use strict';
// 慢速推送看护（令牌疑似失效后的低成本兜底）：10 分钟一次，24h 窗。
// 若实为长浪（非令牌失效），浪退自动接上 v012_release.js 的完整管线。
const { execFileSync } = require('child_process');
const GIT = 'C:\\LusicGal\\.toolchain\\mingit\\cmd\\git.exe';
const TOK = process.env.LGT;
const REPO = `https://x-access-token:${TOK}@github.com/sunxibing114514/LusicGal.git`;
const dl = Date.now() + 24 * 3600 * 1000;
const log = (m) => console.log(new Date().toISOString().slice(11, 19), m);
while (Date.now() < dl) {
  let out = '';
  try {
    out = execFileSync(GIT, ['-c', 'http.sslBackend=openssl', 'push', REPO, 'main'], {
      cwd: 'C:\\LusicGal',
      env: { ...process.env, GIT_CONFIG_GLOBAL: 'C:\\LusicGal\\.toolchain\\gitconfig' },
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 90000,
    }).toString();
  } catch (e) {
    out = (e.stdout || '') + (e.stderr || '');
  }
  if (!/fatal/i.test(out)) { log('PUSH OK: ' + out.trim()); process.exit(0); }
  else log('fail: ' + out.trim().split('\n').pop().slice(0, 110));
  require('child_process').execSync(
    'powershell -NoProfile -Command Start-Sleep -Seconds 600');
}
log('TIMEOUT 24h');
process.exit(3);
