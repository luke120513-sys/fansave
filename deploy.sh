#!/bin/bash
# 飯省 自動部署：① Apps Script 後端（clasp，固定 deployment id → 網址不變）② 前端到 GitHub Pages（gh）
# ⓪ Cloudflare Worker 取價中繼
# 用法：bash deploy.sh            （第一次會自動建立 Apps Script 專案與 GitHub repo）
set -e
SITE=/workspace/fansave-site; GAS=$SITE/gas; STATE=$SITE/.deploy-state; REPO=${REPO:-fansave}
touch "$STATE"; . "$STATE"
OWNER=$(gh api user --jq .login)

[ "$SKIP_WORKER" = 1 ] || {
# ---------- ⓪ Cloudflare Worker（取價中繼；需 env CLOUDFLARE_API_TOKEN，不會印出）----------
CF_ACC=733769a0cf502b67c7fb3aab99dea5ee
curl -sf -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACC/workers/scripts/fansave-api" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -F 'metadata={"main_module":"worker.js","compatibility_date":"2026-10-01","keep_bindings":["secret_text"]};type=application/json' \
  -F "worker.js=@$SITE/worker/worker.js;type=application/javascript+module" >/dev/null && echo "Worker: https://fansave-api.luke120513.workers.dev/"
}

# ---------- ① Apps Script ----------
B=$(mktemp -d); cp "$GAS/Code.gs" "$GAS/appsscript.json" "$B"/; cd "$B"
[ -n "$PUSH_KEY" ] && sed -i "s/__PUSH_KEY__/$PUSH_KEY/" Code.gs
if [ -z "$SCRIPT_ID" ]; then
  clasp create --type standalone --title "飯省 FanSave 後端" --rootDir . >/dev/null
  SCRIPT_ID=$(python3 -c "import json;print(json.load(open('.clasp.json'))['scriptId'])")
  echo "SCRIPT_ID=$SCRIPT_ID" >> "$STATE"
  cp "$GAS/appsscript.json" .   # clasp create 會覆蓋 manifest
else
  echo "{\"scriptId\":\"$SCRIPT_ID\",\"rootDir\":\".\"}" > .clasp.json
fi
clasp push -f
if [ -z "$DEPLOY_ID" ]; then
  DEPLOY_ID=$(clasp deploy -d "fansave $(date +%F-%H%M)" | grep -oE 'AKfy[A-Za-z0-9_-]+' | head -1)
  echo "DEPLOY_ID=$DEPLOY_ID" >> "$STATE"
else
  clasp deploy -i "$DEPLOY_ID" -d "fansave $(date +%F-%H%M)" >/dev/null   # 同一個 id → /exec 網址不變
fi
API_URL="https://script.google.com/macros/s/$DEPLOY_ID/exec"; echo "API: $API_URL"
cd /; rm -rf "$B"

# ---------- ② 前端 GitHub Pages ----------
# 永遠先 clone 遠端最新（含 GitHub PR），再把本機 intentional 變更 overlay 上去。
# 禁止 force push；本機若落後遠端 VER → 拒絕覆蓋，避免洗掉 PR 功能。
W=$(mktemp -d); RURL="https://x-access-token:$(gh auth token)@github.com/$OWNER/$REPO.git"
if git clone -q "$RURL" "$W" 2>/dev/null; then
  :
else
  git -C "$W" init -q -b main; NEW=1
fi
cd "$W"

# 版本守衛：遠端 index.html 的 VER 新於本機時，拒絕用舊本機覆蓋
if [ -f index.html ] && [ -f "$SITE/index.html" ]; then
  RVER=$(grep -oE "VER='v[0-9.]+'" index.html | head -1 | tr -d "VER='")
  LVER=$(grep -oE "VER='v[0-9.]+'" "$SITE/index.html" | head -1 | tr -d "VER='")
  if [ -n "$RVER" ] && [ -n "$LVER" ] && [ "$RVER" != "$LVER" ]; then
    # 數字比較：把 v2.9.0 → 2 9 0，逐段比
    python3 - "$RVER" "$LVER" <<'PY' && {
import sys
def parts(v):
  v=v.lstrip('vV'); return [int(x) for x in v.split('.') if x.isdigit()]
r,l=parts(sys.argv[1]),parts(sys.argv[2])
# pad
n=max(len(r),len(l)); r+=[0]*(n-len(r)); l+=[0]*(n-len(l))
sys.exit(0 if r>l else 1)
PY
      echo "ERROR: local SITE VER=$LVER is behind GitHub VER=$RVER."
      echo "Sync /workspace/fansave-site from https://github.com/$OWNER/$REPO first, then redeploy."
      echo "Refusing to overlay stale local files (would wipe PR features)."
      cd /; rm -rf "$W"; exit 1
    }
  fi
fi

# 以遠端為底，overlay 本機工作樹（本機已與遠端同步或本機 VER 較新）
cp "$SITE"/{index.html,data.js,sw.js} .; cp "$SITE/manifest.json" .
mkdir -p screenshots; cp "$SITE"/screenshots/*.png screenshots/ 2>/dev/null || true
[ -f "$SITE/push-sw.js" ] && cp "$SITE/push-sw.js" .
mkdir -p icons; cp "$SITE"/icons/*.png icons/ 2>/dev/null || true
# 把 deploy.sh 一併進 repo，之後部署腳本也受版控
[ -f "$SITE/deploy.sh" ] && cp "$SITE/deploy.sh" .
python3 - "$API_URL" <<'PY'
import sys,re;s=open('index.html').read()
s=re.sub(r"var API=[^\n]*?; //","var API='%s'; //"%sys.argv[1],s,1);open('index.html','w').write(s)
PY
V=$(date +%s); sed -i "s/C='fansave-v[0-9]*'/C='fansave-v$V'/" sw.js; touch .nojekyll   # 新快取名 → 手機自動更新
if ! gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  gh repo create "$OWNER/$REPO" --public -d "飯省 FanSave：找 CP 值最高的飯店" >/dev/null; NEW=1
fi
git add -A
if git diff --cached --quiet; then
  echo "前端: 無變更，跳過 commit/push"
else
  git -c user.name=fansave-bot -c user.email=bot@fansave.local commit -qm "deploy $(date +%F_%T)"
  # 再次 pull --rebase 接上可能剛落地的遠端 commit；永不 force push
  git pull -q --rebase "$RURL" main 2>/dev/null || true
  git push -q "$RURL" HEAD:main
fi
[ -n "$NEW" ] && gh api -X POST "repos/$OWNER/$REPO/pages" -f "source[branch]=main" -f "source[path]=/" >/dev/null || true
cd /; rm -rf "$W"
echo "網站: https://$OWNER.github.io/$REPO/"
