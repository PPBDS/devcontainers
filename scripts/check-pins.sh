#!/usr/bin/env bash
#
# check-pins.sh — report every version this image pins against what upstream
# currently ships, plus the consumer pins that must move with each release.
# Read-only: it changes nothing. Run it before cutting a release (runbook
# step 1 in CLAUDE.md) so the bumps are chosen deliberately instead of
# noticed by accident. Dependabot cannot see Dockerfile ARG pins, Open VSX,
# the P3M snapshot, or the GitHub-HEAD course packages, which is why this
# script exists.
#
# Needs: bash, curl, python3, gh (logged in; used for GitHub release lookups
# and for reading the consumer repos' pins). Lives outside the Docker build
# context (.dockerignore keeps only the Dockerfile + requirements files).
#
# Output is one line per pin: "  <name>  <pinned> -> <latest>" with "  OK"
# when they match and "  BUMP?" when they differ. Nothing here is a verdict —
# a differing version is a prompt to read that tool's release notes, not an
# instruction to bump (vscode-R pre-releases, for example, are deliberately
# NOT followed; see the extension block in the Dockerfile).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="$here/Dockerfile"

arg() { grep -oE "^ARG $1=[^ ]+" "$dockerfile" | cut -d= -f2; }
json() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
row() { # name pinned latest
  local mark="BUMP?"; [[ "$2" == "$3" ]] && mark="OK"
  printf '  %-34s %-16s -> %-16s %s\n' "$1" "$2" "$3" "$mark"
}
gh_latest() { gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null | sed 's/^v//' || echo '?'; }
npm_latest() { curl -fsSL "https://registry.npmjs.org/$1/latest" | json 'd["version"]' 2>/dev/null || echo '?'; }
pypi_latest() { curl -fsSL "https://pypi.org/pypi/$1/json" | json 'd["info"]["version"]' 2>/dev/null || echo '?'; }
ovsx_latest() { curl -fsSL "https://open-vsx.org/api/$1" | json 'd["version"]' 2>/dev/null || echo '?'; }

echo "== Base image (digest-pinned; a differing digest means Rocker rebuilt :4.6)"
pinned_digest="$(grep -oE '^FROM .*@sha256:[0-9a-f]+' "$dockerfile" | grep -oE 'sha256:[0-9a-f]+')"
tok="$(curl -fsSL 'https://ghcr.io/token?scope=repository:rocker-org/devcontainer/tidyverse:pull' | json 'd["token"]')"
cur_digest="$(curl -fsSI -H "Authorization: Bearer $tok" \
  -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
  https://ghcr.io/v2/rocker-org/devcontainer/tidyverse/manifests/4.6 | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:"{print $2}')"
row "rocker tidyverse:4.6" "${pinned_digest:7:12}" "${cur_digest:7:12}"

echo "== System tools (Dockerfile ARGs)"
row "gh"            "$(arg GH_VERSION)"      "$(gh_latest cli/cli)"
row "quarto"        "$(arg QUARTO_VERSION)"  "$(gh_latest quarto-dev/quarto-cli)"
row "arf"           "$(arg ARF_VERSION)"     "$(gh_latest eitsupi/arf)"
row "uv (COPY --from)" "$(grep -oE 'astral-sh/uv:[0-9.]+' "$dockerfile" | cut -d: -f2)" "$(gh_latest astral-sh/uv)"
row "catboost (install_url)" "$(grep -oE 'catboost/releases/download/v[0-9.]+' "$dockerfile" | grep -oE '[0-9.]+$')" "$(gh_latest catboost/catboost)"
row "node major (vs newest LTS line)" "$(arg NODE_MAJOR)" "$(curl -fsSL https://nodejs.org/dist/index.json | json 'next(v["version"] for v in d if v["lts"]).lstrip("v").split(".")[0]' 2>/dev/null || echo '?')"

echo "== AI CLIs (agy has no pin and floats by design)"
row "claude-code"   "$(arg CLAUDE_CODE_VERSION)" "$(npm_latest @anthropic-ai/claude-code)"
row "codex"         "$(arg CODEX_VERSION)"       "$(npm_latest @openai/codex)"
row "grok"          "$(arg GROK_VERSION)"        "$(npm_latest @xai-official/grok)"
row "aider"         "$(arg AIDER_VERSION)"       "$(pypi_latest aider-chat)"
row "observable framework" "$(grep -oE '@observablehq/framework@[0-9.]+' "$dockerfile" | cut -d@ -f3)" "$(npm_latest @observablehq/framework)"

echo "== VS Code extensions (Open VSX; vscode-R against its newest STABLE GitHub release)"
row "PPBDS.vscode-r-tutorials" "$(arg RT_EXT_VERSION)"          "$(ovsx_latest PPBDS/vscode-r-tutorials)"
# vscode-R: compare against the newest STABLE release (GitHub releases with
# prerelease=false), not Open VSX's newest version, which is the dated 3.x
# pre-release channel we deliberately skip — that is how stable 3.2.1 went
# unnoticed on 2026-10-24 while the report kept showing a skipped 3.3.x.
row "REditorSupport.r (stable)" "$(arg VSCODE_R_VERSION)" "$(gh api repos/REditorSupport/vscode-R/releases --jq '[.[] | select(.prerelease==false)][0].tag_name' 2>/dev/null | sed 's/^v//' || echo '?')"
row "REditorSupport.r-syntax"  "$(arg R_SYNTAX_EXT_VERSION)"    "$(ovsx_latest REditorSupport/r-syntax)"
row "quarto.quarto"            "$(arg QUARTO_EXT_VERSION)"      "$(ovsx_latest quarto/quarto)"
row "ritwickdey.LiveServer"    "$(arg LIVESERVER_EXT_VERSION)"  "$(ovsx_latest ritwickdey/LiveServer)"
row "tomoki1207.pdf"           "$(arg PDF_EXT_VERSION)"         "$(ovsx_latest tomoki1207/pdf)"
row "mechatroner.rainbow-csv"  "$(arg RAINBOW_CSV_EXT_VERSION)" "$(ovsx_latest mechatroner/rainbow-csv)"

echo "== Python top-level pins (requirements.txt; recompile the lock after a bump)"
grep -E '^[A-Za-z]' "$here/requirements.txt" | while IFS='=' read -r p _ v; do
  row "$p" "$v" "$(pypi_latest "$p")"
done

echo "== Course packages: GitHub commits since COURSE_PKG_REFRESH ($(arg COURSE_PKG_REFRESH))"
since="$(arg COURSE_PKG_REFRESH | cut -c1-10)T00:00:00Z"
for r in PPBDS/learnr2 PPBDS/vscode.tutorials PPBDS/misc.tutorials PPBDS/ims.tutorials PPBDS/primer.data; do
  n="$(gh api "repos/$r/commits?since=$since&per_page=100" --jq length 2>/dev/null || echo '?')"
  last="$(gh api "repos/$r/commits?per_page=1" --jq '.[0].commit.committer.date[:10]' 2>/dev/null || echo '?')"
  printf '  %-34s %s new commit(s), last %s\n' "$r" "$n" "$last"
done

echo "== Consumer pins (the FIVE places; all must equal the latest release tag)"
latest_tag="$(gh_latest PPBDS/devcontainers)"
pin_of() { gh api "repos/$1/contents/$2" --jq .content 2>/dev/null | base64 -d | grep -oE 'ghcr\.io/ppbds/devcontainer:[0-9][0-9.]*' | head -1 | cut -d: -f2 || echo '?'; }
row "PPBDS/codespace-starter"  "$(pin_of PPBDS/codespace-starter .devcontainer/devcontainer.json)" "$latest_tag"
for r in misc.tutorials vscode.tutorials ims.tutorials; do
  row "PPBDS/$r (CI)" "$(pin_of PPBDS/$r .github/workflows/R-CMD-check.yaml)" "$latest_tag"
done
row "PPBDS/primer"             "$(pin_of PPBDS/primer .devcontainer/devcontainer.json)" "$latest_tag"

echo "== Lockstep: launcher's vscode-R pin must equal VSCODE_R_VERSION"
launcher_r="$(gh api repos/PPBDS/codespace-starter/contents/.devcontainer/devcontainer.json --jq .content 2>/dev/null | base64 -d | grep -oE 'reditorsupport\.r@[0-9.]+' | cut -d@ -f2 || echo '?')"
row "codespace-starter reditorsupport.r@" "$launcher_r" "$(arg VSCODE_R_VERSION)"
