#!/bin/bash
# Backup MCP server API (oen-mcp) definition + all policies, for rollback.
S=bd15c49d-3894-4d25-a9ec-d07c06ada81a
B="https://management.azure.com/subscriptions/$S/resourceGroups/rg-psa-oen-apim/providers/Microsoft.ApiManagement/service/apim-psa-oen-hub"
V=2025-03-01-preview
D=/home/jtantra/dev/live/psa-oen-api/infra/backup/$(date +%Y%m%d-%H%M%S)
mkdir -p $D
az rest --method get --url "$B/apis/oen-mcp?api-version=$V" > $D/oen-mcp.api.json
az rest --method get --url "$B/apis/oen-mcp/policies/policy?api-version=$V&format=rawxml" > $D/oen-mcp.policy.json 2>$D/oen-mcp.policy.err || true
az rest --method get --url "$B/apis/oen-mcp/operations?api-version=$V" > $D/oen-mcp.ops.json 2>/dev/null || true
az rest --method get --url "$B/policies/policy?api-version=$V&format=rawxml" > $D/global.policy.json
az rest --method get --url "$B/apis/oen/policies/policy?api-version=$V&format=rawxml" > $D/oen.policy.json
echo $D > /home/jtantra/.psa-oen/last-backup
ls -la $D
python3 -c "
import json;a=json.load(open('$D/oen-mcp.api.json'));p=a['properties'];print('type',p.get('type'),'path',p.get('path'));print(json.dumps({k:v for k,v in p.items() if k not in('description',)},indent=1)[:2500])"
cat $D/oen-mcp.policy.err 2>/dev/null | head -3
python3 -c "import json;print(json.load(open('$D/oen-mcp.policy.json'))['properties']['value'])" 2>/dev/null
