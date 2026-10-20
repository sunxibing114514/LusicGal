'use strict';
// 401 浪期间的长效推送看护：git push(内联令牌) + /user 探针交替重试。
// 成功（push exit=0）即退出 0；3 小时仍失败退出 3。
const { execFileSync } = require('child_process');
const GIT = 'C:\\LusicGal\\.toolchain\\mingit\\cmd\\git.exe';
const TOK = process.env.LGT;
const REPO = `https://x-access-token:${TOK}@github.com/sunxibing114514/LusicGal.git`;
const dl = Date.now() + 3 * 3600 * 1000;
const log = (m) => console.log(new Date().toISOString().slice(11, 19), m);
async function probeUser() {
  try {
    const r = await fetch('https://api.github.com/user', {
      headers: { 'User-Agent': 'lg', Authorization: 'Bearer ' + TOK },
    });
    return r.status;
  } catch (e) { return 'ERR ' + e.message; }
}
(async () => {
  while (Date.now() < dl) {
    let out = '';
    try {
      out = execFileSync(GIT, ['-c', 'http.sslBackend=openssl', 'push', REPO, 'main'], {
        cwd: 'C:\\LusicGal',
        env: { ...process.env, GIT_CONFIG_GLOBAL: 'C:\\LusicGal\\.toolchain\\gitconfig' },
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: 60000,
      }).toString();
    } catch (e) {
      out = (e.stdout || '') + (e.stderr || '');
    }
    if (/refs\/heads\/main|up to date/i.test(out) && !/fatal/i.test(out.split('\n').pop())) {
      log('PUSH OK: ' + out.trim().split('\n').pop());
      process.exit(0);
    }
    const last = out.trim().split('\n').pop() || '(empty)';
    const api = await probeUser();
    log('push fail: ' + last.slice(0, 140) + ' | /user=' + api);
    await new Promise(z => setTimeout(z, 60000));
  }
  log('TIMEOUT 3h');
  process.exit(3);
})();
