#!/usr/bin/env node
// LusicGal GitHub Release 发布器：建 release + 流式上传 APK 资产。
// 用法：node publish_release.js <apk文件> <tag> <release名> <body>
// 令牌经环境变量 LG_TOKEN（绝不写死/入库/入日志）。
'use strict';
const fs = require('fs');

const [,, apkPath, tag, name, body] = process.argv;
const TOKEN = process.env.LG_TOKEN;
if (!apkPath || !tag || !TOKEN) {
  console.error('用法: node publish_release.js <apk> <tag> [name] [body]（LG_TOKEN 环境变量必需）');
  process.exit(2);
}
const REPO = 'sunxibing114514/LusicGal';
const API = `https://api.github.com/repos/${REPO}`;
const H = {
  'Authorization': `Bearer ${TOKEN}`,
  'Accept': 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'LusicGalBuilder',
};

(async () => {
  // 1) 建（或复用）release。
  let rel;
  const res = await fetch(`${API}/releases`, {
    method: 'POST', headers: H,
    body: JSON.stringify({
      tag_name: tag,
      target_commitish: 'main',
      name: name || tag,
      body: body || '',
    }),
  });
  const j = await res.json().catch(() => ({}));
  if (res.status === 422 || res.status === 409) {
    // 已存在：列出找同名 tag。
    const list = await fetch(`${API}/releases`, { headers: H });
    const arr = await list.json();
    rel = arr.find(r => r.tag_name === tag);
    console.log(`release 已存在：#${rel.id}（${rel.tag_name}）`);
  } else if (res.ok) {
    rel = j;
    console.log(`✓ release 已建：#${rel.id}（${rel.tag_name}）`);
  } else {
    throw new Error(`建 release 失败 HTTP ${res.status}: ${JSON.stringify(j).slice(0, 300)}`);
  }

  // 2) 流式上传资产（420MB 不能进内存）。
  const stat = fs.statSync(apkPath);
  const upBase = `https://uploads.github.com/repos/${REPO}/releases/${rel.id}/assets`;
  const url = `${upBase}?name=${encodeURIComponent(require('path').basename(apkPath))}`;
  const { Readable } = require('stream');
  const webStream = Readable.toWeb(fs.createReadStream(apkPath));
  const up = await fetch(url, {
    method: 'POST',
    headers: { ...H, 'Content-Type': 'application/vnd.android.package-archive',
               'Content-Length': String(stat.size) },
    body: webStream,
    duplex: 'half',
  });
  const uj = await up.json().catch(() => ({}));
  if (!up.ok) throw new Error(`上传失败 HTTP ${up.status}: ${JSON.stringify(uj).slice(0, 300)}`);
  console.log(`✓ 资产已传：${uj.name}（${(uj.size / 1048576).toFixed(1)}MB，${(uj.browser_download_url)}）`);
})().catch(e => { console.error('✗', e.message); process.exit(1); });
