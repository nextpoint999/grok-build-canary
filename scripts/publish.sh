#!/usr/bin/env bash
# 发布或刷新 grok-build 镜像 release（在 GitHub Actions publish job 中运行）。
#
# 必需环境变量: GH_REPO TAG VERSION HEAD_SHA HEAD_SHORT HEAD_DATE
# 可选:         FORCE LATEST UPSTREAM_URL
# 输入:         dist/ 下 6 个平台二进制（grok-<platform>-<arch>[.exe]）
#
# 语义:
#   - release 不存在 → gh release create（重试 3 次）
#   - release 已存在 → 删除旧资产 + 上传新资产 + 更新 body（不动 published_at，
#     Latest 徽标不回退）
#   - LATEST: auto/set → PATCH make_latest=true 钉住本 release；keep → 不动
set -euo pipefail

BIN_DIR="${BIN_DIR:-dist}"
TAG="${TAG:?TAG required}"
LATEST="${LATEST:-auto}"
FORCE="${FORCE:-}"

cd "$(dirname "$0")/.."

# 1. 校验 6 个平台资产齐全
EXPECTED="grok-darwin-arm64 grok-darwin-x64 grok-linux-arm64 grok-linux-x64 grok-win32-arm64.exe grok-win32-x64.exe"
MISSING=""
for a in $EXPECTED; do
  [ -f "$BIN_DIR/$a" ] || MISSING="$MISSING $a"
done
if [ -n "$MISSING" ]; then
  echo "[error] 缺少平台资产:$MISSING"
  ls -la "$BIN_DIR" || true
  exit 1
fi

# 2. 校验和（只针对文件，find 时不会再扫到目录）
( cd "$BIN_DIR" && sha256sum ./grok-* > SHA256SUMS )

# 3. release notes（body 中记录 40 位 commit SHA，detect job 靠它判断是否需要刷新）
NOTES="$(cat <<EOF
xAI [grok-build](${UPSTREAM_URL:-https://github.com/xai-org/grok-build}) 的 GitHub Actions 镜像构建 — \`${VERSION}\`

- 上游 commit: \`${HEAD_SHA}\` (\`${HEAD_SHORT}\`, ${HEAD_DATE})
- 构建时间: $(date -u '+%Y-%m-%d %H:%M UTC')
- 平台 (6): linux x64/arm64 · darwin x64/arm64 · win32 x64/arm64
- 触发: 每 2h 定时轮询上游 main；commit 变化时自动刷新本 release；也可 workflow_dispatch 手动构建
- 安装: 下载对应平台二进制（\`chmod +x\` 后直接运行）；官方渠道: \`curl -fsSL https://x.ai/cli/install.sh | bash\`
EOF
)"

DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name')"

# 4. release 是否存在（带重试，防 GitHub 临时 500）
RELEASE_EXISTS=""
for _try in 1 2 3; do
  if gh release view "$TAG" >/dev/null 2>&1; then RELEASE_EXISTS="yes"; break; fi
  echo "[warn] gh release view ${TAG} 失败/不存在（第 ${_try} 次）"
  sleep 5
done

FILES=$(find "$BIN_DIR" -maxdepth 1 -type f | sort)
echo "[info] 上传文件:"; echo "$FILES"

if [ -n "$RELEASE_EXISTS" ]; then
  echo "[info] 刷新已有 release: ${TAG}${FORCE:+ (force)}"
  gh release view "$TAG" --json assets -q '.assets[].name' | while read -r a; do
    [ -n "$a" ] && gh release delete-asset "$TAG" "$a" --yes >/dev/null
  done
  gh release upload "$TAG" $FILES --clobber
  gh release edit "$TAG" --notes "$NOTES"
else
  echo "[info] 创建新 release: ${TAG}"
  CREATED=""
  for _try in 1 2 3; do
    if gh release create "$TAG" $FILES --target "$DEFAULT_BRANCH" --title "$TAG" --notes "$NOTES"; then
      CREATED="yes"; break
    fi
    echo "[warn] gh release create ${TAG} 失败（第 ${_try} 次），10s 后重试"
    sleep 10
  done
  [ -n "$CREATED" ] || { echo "[error] gh release create 重试 3 次仍失败"; exit 1; }
fi

# 5. Latest 徽标
case "$LATEST" in
  keep) echo "[info] latest 徽标保持不变" ;;
  *)
    REL_ID="$(gh release view "$TAG" --json id -q '.id')"
    if gh api -X PATCH "repos/${GH_REPO}/releases/${REL_ID}" -f make_latest=true >/dev/null 2>&1; then
      echo "[info] 已将该 release 设为 Latest"
    else
      echo "[warn] make_latest 失败（该 release 为 pre-release/draft 时无法设为 latest）"
    fi
    ;;
esac

echo "[done] release ${TAG} 处理完成"
gh release view "$TAG" --json tagName,assets -q '{tag: .tagName, assets: [.assets[].name]}'
