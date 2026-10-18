#!/usr/bin/env node
// LusicGal Windows 管线：三个存档目录锚点补丁（scripts/patch_engines.sh 的
// node 等价实现 —— 单锚点单文件替换，幂等，标记 LUSICGAL_SAVE_DIR）。
'use strict';
const fs = require('fs');

const UP = 'C:/LusicGal/third_party/upstream';

function patch(file, mark, anchor, repl) {
  let s = fs.readFileSync(file, 'utf8');
  if (s.includes(mark)) return console.log('SKIP ', file);
  if (!s.includes(anchor)) { console.error('FAIL-ANCHOR', file); process.exit(1); }
  fs.writeFileSync(file, s.replace(anchor, repl));
  console.log('OK   ', file);
}

// siglus-rs：original_save.rs::save_dir → LUSICGAL_SAVE_DIR 优先
patch(`${UP}/siglus-rs/crates/siglus_scene_vm/src/original_save.rs`,
  'LUSICGAL_SAVE_DIR',
  'pub fn save_dir(project_dir: &Path) -> PathBuf {\n    project_dir.join("savedata")\n}',
  'pub fn save_dir(project_dir: &Path) -> PathBuf {\n    if let Some(dir) = std::env::var_os("LUSICGAL_SAVE_DIR") {\n        return std::path::PathBuf::from(dir);\n    }\n    project_dir.join("savedata")\n}');

// sena-rs：runtime.rs::portable_save_dir → LUSICGAL_SAVE_DIR 优先
{
  const f = `${UP}/sena-rs/crates/pal-vm/src/runtime.rs`;
  const mark = 'LUSICGAL_SAVE_DIR';
  const anchor = 'fn portable_save_dir(root: &Path) -> PathBuf {\n    root.join("save").join("sena_rs")\n}';
  const repl = 'fn portable_save_dir(root: &Path) -> PathBuf {\n    if let Some(dir) = std::env::var_os("LUSICGAL_SAVE_DIR") {\n        return PathBuf::from(dir);\n    }\n    root.join("save").join("sena_rs")\n}';
  let s = fs.readFileSync(f, 'utf8');
  if (s.includes(mark)) console.log('SKIP ', f);
  else if (!s.includes(anchor)) { console.error('FAIL-ANCHOR', f); process.exit(1); }
  else { fs.writeFileSync(f, s.replace(anchor, repl)); console.log('OK   ', f); }
}

// rfvp：utils/file.rs::desktop_storage → LUSICGAL_SAVE_DIR 优先
patch(`${UP}/rfvp/crates/rfvp/src/utils/file.rs`,
  'LUSICGAL_SAVE_DIR',
  'pub fn desktop_storage() -> std::sync::Arc<dyn crate::host_api::RfvpStorage> {\n    std::sync::Arc::new(crate::host_api::std_fs::StdDir::new(\n        app_base_path().get_path().clone(),\n    ))\n}',
  'pub fn desktop_storage() -> std::sync::Arc<dyn crate::host_api::RfvpStorage> {\n    let base = std::env::var_os("LUSICGAL_SAVE_DIR")\n        .map(std::path::PathBuf::from)\n        .unwrap_or_else(|| app_base_path().get_path().clone());\n    std::sync::Arc::new(crate::host_api::std_fs::StdDir::new(base))\n}');

console.log('锚点补丁完成。');
