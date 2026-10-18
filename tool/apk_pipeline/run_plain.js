'use strict';
// 直接以纯文本错误格式编译 naga（脱离 cargo 的 json 掩盖），打印真实报错。
const { execFileSync } = require('child_process');
const env = { ...process.env };
env.PATH = 'C:\\LusicGal\\.toolchain\\rust\\rustc\\bin;C:\\LusicGal\\.toolchain\\rust\\cargo\\bin;C:\\LusicGal\\.toolchain\\android-ndk-r29\\toolchains\\llvm\\prebuilt\\windows-x86_64\\bin;' + process.env.PATH;
env.CARGO_HOME = 'C:\\LusicGal\\.toolchain\\cargo-home';
env.CCC_OVERRIDE_OPTIONS = '';
env.RUST_MIN_STACK = '67108864';
const args = process.argv.slice(2);
const cmd = args.shift();
try {
  const out = execFileSync(cmd, args, { env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  console.log(out);
} catch (e) {
  console.log('EXIT', e.status);
  console.log((e.stdout || '').slice(0, 4000));
  console.error((e.stderr || '').slice(0, 4000));
}
