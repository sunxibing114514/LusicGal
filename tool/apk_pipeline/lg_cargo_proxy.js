#!/usr/bin/env node
// lg_cargo_proxy.js — LusicGal Windows 管线的本地 crates 代理。
// 本机 schannel 全坏（cargo/curl/git 的 TLS 握手在 AcquireCredentialsHandle
// 就 SEC_E_NO_CREDENTIALS），唯一活口是 node 的 OpenSSL 栈。本脚本在
// 127.0.0.1 上开纯 HTTP 服务，把 cargo 的 sparse 索引与 .crate 下载转发
// 到 rsproxy.cn（全量镜像 crates.io），并落盘缓存。
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 9999;
const UP = 'https://rsproxy.cn';
const CACHE = path.join(__dirname, 'cargo-mirror');
fs.mkdirSync(path.join(CACHE, 'index'), { recursive: true });
fs.mkdirSync(path.join(CACHE, 'crates'), { recursive: true });

// 覆写 config.json：下载模板指回本代理（否则 cargo 会直连 rsproxy → schannel 死）。
const CONFIG_JSON = JSON.stringify({
  dl: `http://127.0.0.1:${PORT}/crates/{crate}/{version}/download`,
  'auth-required': false,
});

async function pump(res, body) {
  for await (const chunk of body) res.write(chunk);
  res.end();
}

http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
    if (req.method !== 'GET') { res.writeHead(405).end(); return; }

    // 索引 config.json → 本地覆写
    if (url.pathname === '/index/config.json') {
      res.writeHead(200, { 'content-type': 'application/json' }).end(CONFIG_JSON);
      return;
    }
    // sparse 索引文件（含 1/2/3 字前缀目录）
    if (url.pathname.startsWith('/index/')) {
      const cacheFile = path.join(CACHE, decodeURIComponent(url.pathname));
      if (fs.existsSync(cacheFile)) {
        res.writeHead(200, { 'content-type': 'text/plain' })
          .end(fs.readFileSync(cacheFile));
        return;
      }
      const upstream = await fetch(UP + url.pathname);
      if (!upstream.ok) { res.writeHead(upstream.status).end(); return; }
      const body = await upstream.arrayBuffer();
      fs.mkdirSync(path.dirname(cacheFile), { recursive: true });
      fs.writeFileSync(cacheFile, Buffer.from(body));
      res.writeHead(200, { 'content-type': 'text/plain' }).end(Buffer.from(body));
      return;
    }
    // .crate 下载（流式转发并缓存；上游走 /api/v1 路由）
    if (url.pathname.startsWith('/crates/')) {
      const cacheFile = path.join(CACHE, url.pathname);
      if (fs.existsSync(cacheFile)) {
        const buf = fs.readFileSync(cacheFile);
        res.writeHead(200, { 'content-type': 'application/octet-stream' }).end(buf);
        return;
      }
      const upstream = await fetch(`${UP}/api/v1${url.pathname}`);
      if (!upstream.ok || !upstream.body) { res.writeHead(upstream.status || 502).end(); return; }
      res.writeHead(200, { 'content-type': 'application/octet-stream' });
      const chunks = [];
      for await (const c of upstream.body) { chunks.push(c); res.write(c); }
      res.end();
      fs.mkdirSync(path.dirname(cacheFile), { recursive: true });
      fs.writeFileSync(cacheFile, Buffer.concat(chunks));
      return;
    }
    res.writeHead(404).end();
  } catch (e) {
    try { res.writeHead(502).end(String(e)); } catch {}
  }
}).listen(PORT, '127.0.0.1', () => {
  console.log(`lg_cargo_proxy listening on http://127.0.0.1:${PORT} → ${UP}`);
});
