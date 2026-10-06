#!/bin/bash
# usage: mcp-calls.sh [minutes]  -> MCP calls seen by APIM (App Insights): method, tool, args
AID=$(az monitor app-insights component show -a appi-psa-oen -g rg-psa-oen-apim --subscription bd15c49d-3894-4d25-a9ec-d07c06ada81a --query appId -o tsv)
Q=$(cat <<KQL
requests
| where timestamp > ago(${1:-15}m)
| extend b = tostring(customDimensions['Request-Body'])
| extend j = parse_json(b)
| project t = format_datetime(timestamp, 'HH:mm:ss'), ip = client_IP, rc = resultCode, ms = round(duration), path = name,
          method = tostring(j.method), tool = tostring(j.params.name), args = substring(tostring(j.params.arguments), 0, 200), q = tostring(split(url, '?')[1])
| order by t asc
KQL
)
az monitor app-insights query --app "$AID" --analytics-query "$Q" -o json --query "tables[0].rows" | python3 -c '
import json,sys
for r in json.load(sys.stdin): print("  ".join(str(x) for x in r if x not in ("",None)))'
