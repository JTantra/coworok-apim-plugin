#!/usr/bin/env bash
# PSA OEN CI/CD — two independent paths.
#   APIM path   : tools live in APIM; Cowork reads tools/list at runtime (manifest 1.29, no tools.json).
#                 Changing a tool = edit infra/apim-oen.bicep or infra/policies/*.xml, run with --apim. No repackage.
#   Plugin path : skill/manifest changes only. Repackage + publish when plugin/appPackage differs from last publish.
# Usage: cicd/pipeline.sh [--apim] [--force-publish]
#   --apim           redeploy infra/apim-oen.bicep first
#   --force-publish  publish even if plugin/appPackage is unchanged (version must still be higher)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); PKG=$ROOT/plugin/appPackage; C=$ROOT/cicd
STAMP=$C/.last-published.sha256
APIM=0; FORCE=0
for a in "$@"; do case $a in --apim|--apply-apim) APIM=1;; --force-publish|--force) FORCE=1;; esac; done

echo "== 1. APIM (source of truth for tools)"
if [ $APIM = 1 ]; then bash "$ROOT/infra/gw.sh" apim >/dev/null && echo "apim-oen.bicep deployed"; else echo "skipped (no --apim)"; fi

echo "== 2. gate live MCP server: tools/list annotations + tools/call"
python3 "$C/check_mcp.py" "$(bash "$ROOT/infra/gw.sh" token)"

echo "== 3. plugin changed since last publish?"
HASH=$(cd "$PKG" && find . -type f ! -name '*Zone.Identifier' | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
if [ $FORCE = 0 ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$HASH" ]; then
  echo "plugin/appPackage unchanged - nothing to publish"; exit 0
fi
VER=$(python3 -c "import json;print(json.load(open('$PKG/manifest.json'))['version'])")
echo "changed -> publishing v$VER (bump manifest.json version before running if this version is already live)"

echo "== 4. validate + zip"
bash "$ROOT/plugin/zip-plugin.sh" | tail -1
ZIP=$ROOT/plugin/dist/psa-oen-cowork-plugin-$VER.zip

echo "== 5. publish via Agents Toolkit (title service)"
export PATH=$HOME/.nvm/versions/node/v24.16.0/bin:$PATH
atk install --file-path "$ZIP" --scope Shared --interactive false
echo "$HASH" > "$STAMP"
