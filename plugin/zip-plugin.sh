#!/usr/bin/env bash
# Zip the Teams / M365 app package (Cowork plugin) for upload.
# Usage: ./plugin/zip-plugin.sh            -> plugin/dist/psa-oen-cowork-plugin-<version>.zip
# Edit files in plugin/appPackage/ (manifest.json, tools.json, skills/...), bump "version" in manifest.json, then run this.
set -euo pipefail
cd "$(dirname "$0")"
PKG=appPackage
OUT=dist
mkdir -p "$OUT"

# Sanity checks
python3 - "$PKG" <<'PY'
import json, re, sys, pathlib
pkg = pathlib.Path(sys.argv[1])
m = json.loads((pkg / "manifest.json").read_text(encoding="utf-8"))
for f in (m["icons"]["color"], m["icons"]["outline"]):
    assert (pkg / f).exists(), f"missing icon {f}"
for c in m.get("agentConnectors", []):
    mtd = c["toolSource"]["remoteMcpServer"].get("mcpToolDescription")
    if mtd:  # optional from manifest 1.29; required (with file in zip) on 1.28
        tf = mtd["file"]
        assert (pkg / tf).exists(), f"missing {tf}"
        json.loads((pkg / tf).read_text(encoding="utf-8"))
    else:
        assert float(m["manifestVersion"]) >= 1.29, "mcpToolDescription is required below manifest 1.29"
    ref = c["toolSource"]["remoteMcpServer"]["authorization"].get("referenceId", "")
    assert ref, "authorization.referenceId is empty"
for s in m.get("agentSkills", []):
    d = pkg / s["folder"]
    md = (d / "SKILL.md").read_text(encoding="utf-8")
    fm = re.match(r"^---\n(.*?)\n---\n", md, re.S); assert fm, f"{d}/SKILL.md frontmatter"
    name = re.search(r"^name:\s*(.+)$", fm.group(1), re.M).group(1).strip()
    assert name == d.name, f"skill name {name} != folder {d.name}"
    desc = re.search(r"^description:\s*(.+)$", fm.group(1), re.M).group(1).strip()
    assert desc[:1] in "\"'" or ": " not in desc, f"{d}/SKILL.md description contains ': ' - quote it"
    for link in re.findall(r"\]\((references/[^)]+)\)", md):
        assert (d / link).exists(), f"missing {d}/{link}"
print(f"ok  {m['name']['short']} v{m['version']}  id {m['id']}")
PY

VER=$(python3 -c 'import json;print(json.load(open("appPackage/manifest.json"))["version"])')
ZIP="$OUT/psa-oen-cowork-plugin-$VER.zip"
rm -f "$ZIP"
# manifest.json must sit at the zip root (zip the CONTENTS of appPackage, not the folder)
(cd "$PKG" && zip -qrX "../$ZIP" . -x '*.DS_Store' -x '*Zone.Identifier')
unzip -l "$ZIP"
echo "Built $ZIP"
