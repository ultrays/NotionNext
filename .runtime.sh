#!/usr/bin/env bash
# ============================================================
# 沙箱运行时一键重建脚本（幂等，可重复执行）
# 用途：环境被清理后，重建 n8n + 博客所需的依赖与辅助脚本
# 用法：bash /workspace/.runtime.sh
# ============================================================
set -e
export PATH=/root/.nvm/versions/node/v22.16.0/bin:$PATH
export npm_config_proxy=http://127.0.0.1:18080
export npm_config_https_proxy=http://127.0.0.1:18080
export npm_config_http_proxy=http://127.0.0.1:18080
N8N_G=/root/.nvm/versions/node/v22.16.0/lib/node_modules

# ---------- 1) 重建 /tmp 预加载脚本 ----------
cat > /tmp/notion-ua-preload.cjs <<'EOF'
// Notion 请求 UA 注入：Cloudflare 会拦截 Node 默认 UA（NotionNext 抓取 www.notion.so 用）
const realFetch = global.fetch
if (realFetch && !global.__notionUaPatched) {
  global.__notionUaPatched = true
  const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  global.fetch = function (input, init = {}) {
    try {
      const url = typeof input === 'string' ? input : (input && input.url) || ''
      if (url.includes('notion.so')) {
        init.headers = new Headers(init.headers || (input && input.headers) || undefined)
        if (!init.headers.has('User-Agent')) init.headers.set('User-Agent', UA)
      }
    } catch (e) { /* 忽略 */ }
    return realFetch.call(this, input, init)
  }
}
EOF

cat > /tmp/ga-preload.cjs <<'EOF'
// global-agent v3 preload 包装：让 Node 的 http/https（axios/got/rss-parser 等）走代理
try {
  const ga = require('/root/.nvm/versions/node/v22.16.0/lib/node_modules/global-agent')
  if (ga && typeof ga.bootstrap === 'function') ga.bootstrap()
} catch (e) {
  // 静默失败，不影响主进程
}
EOF
echo "[1/5] 预加载脚本已就绪"

# ---------- 2) n8n + global-agent（约 6 分钟，跳过原生编译） ----------
if [ ! -d "$N8N_G/n8n" ]; then
  echo "[2/5] 安装 n8n（--ignore-scripts）..."
  npm install -g n8n --ignore-scripts --silent
  npm install -g global-agent --silent
else
  echo "[2/5] n8n 已安装，跳过"
fi

# ---------- 3) sqlite3 预编译二进制 ----------
SQ3="$N8N_G/n8n/node_modules/sqlite3/lib/binding/node-v127-linux-x64/node_sqlite3.node"
if [ ! -f "$SQ3" ]; then
  echo "[3/5] 下载 sqlite3 预编译二进制..."
  curl -sL --max-time 120 -o /tmp/sqlite3.tgz \
    "https://github.com/TryGhost/node-sqlite3/releases/download/v5.1.7/sqlite3-v5.1.7-napi-v6-linux-x64.tar.gz"
  mkdir -p /tmp/sq3 "$(dirname "$SQ3")"
  tar xzf /tmp/sqlite3.tgz -C /tmp/sq3
  cp /tmp/sq3/build/Release/node_sqlite3.node "$SQ3"
else
  echo "[3/5] sqlite3 二进制已就绪，跳过"
fi

# ---------- 4) 导入工作流（仅在数据库不存在时） ----------
if [ ! -f /root/.n8n/database.sqlite ]; then
  echo "[4/5] 导入 AI 资讯工作流..."
  n8n import:workflow --input=/workspace/n8n-ai-news-workflow.json
else
  echo "[4/5] n8n 数据库已存在，跳过导入"
fi

# ---------- 5) 博客依赖 ----------
if [ ! -d /workspace/node_modules/.bin ]; then
  echo "[5/5] 安装博客依赖（约 3-5 分钟）..."
  (cd /workspace && npm install --silent)
else
  echo "[5/5] 博客依赖已就绪，跳过"
fi

echo "SETUP_DONE"
