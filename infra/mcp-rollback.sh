#!/bin/bash
# ROLLBACK: restore oen-mcp API definition + policy from the backup taken by mcp-backup.sh
set -e
S=bd15c49d-3894-4d25-a9ec-d07c06ada81a
B="https://management.azure.com/subscriptions/$S/resourceGroups/rg-psa-oen-apim/providers/Microsoft.ApiManagement/service/apim-psa-oen-hub"
V=2025-03-01-preview
D=${1:-$(cat /home/jtantra/.psa-oen/last-backup)}
echo "Restoring from $D"
python3 - "$D" > /tmp/mcp-restore.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1]+'/oen-mcp.api.json'))['properties']
keep={k:p[k] for k in ('displayName','path','protocols','type','mcpTools','subscriptionRequired','subscriptionKeyParameterNames') if k in p}
print(json.dumps({'properties':keep}))
PY
az rest --method put --url "$B/apis/oen-mcp?api-version=$V" --body @/tmp/mcp-restore.json --headers Content-Type=application/json -o none
python3 - "$D" > /tmp/mcp-pol.json <<'PY'
import json,sys
x=open(sys.argv[1]+'/oen-mcp.policy.json',encoding='utf-8-sig').read()
print(json.dumps({'properties':{'format':'rawxml','value':x}}))
PY
az rest --method put --url "$B/apis/oen-mcp/policies/policy?api-version=$V" --body @/tmp/mcp-pol.json --headers Content-Type=application/json -o none
echo "Restored. Current tools:"
az rest --method get --url "$B/apis/oen-mcp?api-version=$V" --query "properties.mcpTools[].name" -o tsv
