#!/usr/bin/env bash
# 发布/刷新 grok-build 镜像 release —— 纯 curl + GITHUB_TOKEN 直调 GitHub Releases API
# (不依赖 gh CLI，避免认证/仓库上下文问题)。
# 环境变量: GH_REPO TAG VERSION HEAD_SHA HEAD_SHORT HEAD_DATE LATEST FORCE UPSTREAM_URL
# 输入:     dist/ 下 6 个平台二进制
set -uo pipefail

BIN_DIR="${BIN_DIR:-dist}"
TAG="${TAG:?TAG required}"
GH="${GH_REPO:?GH_REPO required}"
LATEST="${LATEST:-auto}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [ -z "$TOKEN" ]; then echo "::error::未提供 GITHUB_TOKEN/GH_TOKEN"; exit 1; fi
API="https://api.github.com"
AUTH="Authorization: Bearer ${TOKEN}"
ACCEPT="Accept: application/vnd.github+json"
CT="Content-Type: application/json"
UA="User-Agent: hermes-grok"

cd "$(dirname "$0")/.."

echo "== 校验 6 平台资产 =="
EXPECTED="grok-darwin-arm64 grok-darwin-x64 grok-linux-arm64 grok-linux-x64 grok-win32-arm64.exe grok-win32-x64.exe"
MISSING=""
for a in $EXPECTED; do [ -f "$BIN_DIR/$a" ] || MISSING="$MISSING $a"; done
if [ -n "$MISSING" ]; then
  echo "::error::缺少平台资产:$MISSING"
  ls -la "$BIN_DIR" || true
  exit 1
fi

( cd "$BIN_DIR" && sha256sum ./grok-* > SHA256SUMS )

NOTES="$(cat <<EOF
xAI [grok-build](${UPSTREAM_URL:-https://github.com/xai-org/grok-build}) 的 GitHub Actions 镜像构建 — \`${VERSION}\`

- 上游 commit: \`${HEAD_SHA}\` (\`${HEAD_SHORT}\`, ${HEAD_DATE})
- 构建时间: $(date -u '+%Y-%m-%d %H:%M UTC')
- 平台 (6): linux x64/arm64 · darwin x64/arm64 · win32 x64/arm64
- 触发: 每 2h 定时轮询上游 main；commit 变化时自动刷新本 release；也可 workflow_dispatch 手动构建
- 安装: 下载对应平台二进制（\`chmod +x\` 后直接运行）；官方渠道: \`curl -fsSL https://x.ai/cli/install.sh | bash\`
EOF
)"

FILES="$(find "$BIN_DIR" -maxdepth 1 -type f | sort)"
echo "== 待上传文件: =="
echo "$FILES"

api_get() { # $1=url
  curl -fsS -H "$AUTH" -H "$ACCEPT" -H "$UA" "$1"
}
api_post() { # $1=url  $2=body-file(可选)
  if [ -n "${2:-}" ]; then
    curl -fsS -X POST -H "$AUTH" -H "$ACCEPT" -H "$CT" -H "$UA" --data-binary "@$2" "$1"
  else
    curl -fsS -X POST -H "$AUTH" -H "$ACCEPT" -H "$CT" -H "$UA" -d '{}' "$1"
  fi
}
api_patch() {
  curl -fsS -X PATCH -H "$AUTH" -H "$ACCEPT" -H "$CT" -H "$UA" --data-binary "@$1" "$2"
}
api_delete() {
  curl -fsS -X DELETE -H "$AUTH" -H "$ACCEPT" -H "$UA" "$1" -o /dev/null
}
upload_asset() { # $1=file  $2=upload_url
  local f="$1" u="$2" name
  name="$(basename "$f")"
  curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/octet-stream" \
       -H "$ACCEPT" -H "$UA" --data-binary "@$f" "${u}?name=${name}" -o /tmp/up.json \
    || { echo "::error::上传失败 ${name}"; head -c 300 /tmp/up.json 2>/dev/null; return 1; }
  echo "  上传 ${name} OK"
}

echo "== 获取默认分支 =="
DEFAULT_BRANCH="$(api_get "$API/repos/$GH" | python3 -c 'import json,sys; print(json.load(sys.stdin)["default_branch"])')"
echo "default_branch=${DEFAULT_BRANCH}"

# 检查 tag 是否已存在
echo "== 检查 release ${TAG} =="
REL_JSON=""
if REL_JSON="$(api_get "$API/repos/$GH/releases/tags/$TAG" 2>/tmp/rel-err)"; then
  EXISTING=yes
else
  EXISTING=""
  echo "  (不存在, 将创建)"
fi

if [ -n "$EXISTING" ]; then
  echo "== 刷新已有 release ${TAG} =="
  REL_ID="$(echo "$REL_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  UPLOAD_URL="$(echo "$REL_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["upload_url"].split("{")[0])')"
  # 删除旧资产
  echo "$REL_JSON" | python3 -c 'import json,sys; [print(a["id"], a["name"]) for a in json.load(sys.stdin).get("assets",[])]' | while read -r aid aname; do
    [ -n "$aid" ] && api_delete "$API/repos/$GH/releases/assets/$aid" && echo "  删除旧资产 ${aname}"
  done
  # 更新 body
  python3 -c "import json,sys; print(json.dumps({'body': sys.stdin.read()}))" <<<"$NOTES" > /tmp/body.json
  api_patch /tmp/body.json "$API/repos/$GH/releases/$REL_ID" >/tmp/patch.json || { echo "::error::PATCH release 失败"; head -c 300 /tmp/patch.json; exit 1; }
else
  echo "== 创建新 release ${TAG} =="
  python3 -c "import json,sys
body={'tag_name':'$TAG','target_commitish':'$DEFAULT_BRANCH','name':'$TAG','body':open('/dev/stdin').read()}
print(json.dumps(body))" <<<"$NOTES" > /tmp/create.json
  api_post "$API/repos/$GH/releases" /tmp/create.json > /tmp/rel.json \
    || { echo "::error::创建 release 失败"; head -c 300 /tmp/rel.json 2>/dev/null; exit 1; }
  REL_ID="$(python3 -c 'import json,sys; print(json.load(open("/tmp/rel.json"))["id"])')"
  UPLOAD_URL="$(python3 -c 'import json,sys; print(json.load(open("/tmp/rel.json"))["upload_url"].split("{")[0])')"
fi

echo "== 上传资产到 release $REL_ID =="
for f in $FILES; do
  upload_asset "$f" "$UPLOAD_URL" || exit 1
done

echo "== Latest 徽标 =="
if [ "$LATEST" = "keep" ]; then
  echo "  保持不变"
else
  python3 -c "print('{\"make_latest\":true}')" > /tmp/ml.json
  if api_patch /tmp/ml.json "$API/repos/$GH/releases/$REL_ID" >/tmp/ml-resp.json 2>/dev/null; then
    echo "  已设为 Latest"
  else
    echo "  (make_latest 不可用/无需)"
  fi
fi

echo "== 完成 =="
api_get "$API/repos/$GH/releases/$REL_ID" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("release:", d["tag_name"], "| assets:", [a["name"] for a in d.get("assets",[])])'
echo "URL: https://github.com/$GH/releases/tag/$TAG"
