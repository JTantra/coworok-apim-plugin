#!/bin/bash
B=https://apim-psa-oen-hub.azure-api.net/oen
TOK=$(bash $HOME/dev/live/psa-oen-api/infra/gw.sh token)
H=(-H "Authorization: Bearer $TOK")
t(){ curl -s -m 90 -o /tmp/r -w "%{http_code} %{time_total}s %{size_download}B" "${H[@]}" "$1"; }
echo "1 list PSASG Oct-2026 : $(t "$B/voyages?nodes=PSASG&from=2026-10-01&to=2026-10-31&limit=3")"
python3 -c "
import json;d=json.load(open('/tmp/r'));print('  total',d['totalVoyages'],'matched',d['matched'],'returned',d['returned'],'truncated',d['truncated'])
for v in d['voyages']: print('  ',v['voyId'],v['vessel'],v['service'],v['networkSavingsHrs'],v['atRisk'],v['matchedNodes'])"
echo "2 at-risk top 3 (cached token): $(t "$B/voyages?at_risk_only=true&limit=3")"
python3 -c "
import json;d=json.load(open('/tmp/r'));print('  matched',d['matched'],'sorted',d['sortedBy'])
for v in d['voyages']: print('  ',v['voyId'],v['vessel'],v['networkSavingsHrs'],v['atRiskReason'],'worst',v['worstNode'],'rec',v['recoveryNode'])"
VID=$(python3 -c "import json;print(json.load(open('/tmp/r'))['voyages'][0]['voyId'])")
echo "3 get_voyage $VID: $(t "$B/voyages/$VID")"; python3 -c "import json;d=json.load(open('/tmp/r'));r=d.get('result',d);print('  ',d.get('status'),r.get('vesselName'),r.get('vesselIMO'),r.get('vesselCapTeu'))"
echo "4 get_voyage_nodes $VID: $(t "$B/voyages/$VID/nodes")"; python3 -c "
import json;d=json.load(open('/tmp/r'));n=d if isinstance(d,list) else d.get('result',d);print('  nodes',len(n));p=n[0]['nodePerfPortTimeDTO'];print('  ',{k:p.get(k) for k in ['baseAssuredPortTimeQ','actAssuredPortTimeQ','aptSavingsQ','projAptSavingsQ','actGBPQ']})"
echo "5 MCP tools/call list_voyages:"
M=https://apim-psa-oen-hub.azure-api.net/oen-mcp/mcp
HH=(-H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
curl -s -m 60 -X POST $M "${HH[@]}" -D /tmp/h -o /dev/null -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"s","version":"1"}}}'
SID=$(grep -i mcp-session-id /tmp/h | cut -d' ' -f2 | tr -d '\r')
curl -s -m 90 -X POST $M "${HH[@]}" ${SID:+-H "mcp-session-id: $SID"} -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_voyages","arguments":{"at_risk_only":true,"limit":2}}}' > /tmp/m
python3 -c "
import json;t=open('/tmp/m').read()
if 'data:' in t: t=[l[5:] for l in t.splitlines() if l.startswith('data:')][-1]
r=json.loads(t)['result'];txt=r['content'][0]['text'];d=json.loads(txt);print('  isError',r.get('isError'),'matched',d['matched'],[v['vessel'] for v in d['voyages']])"
echo "6 no token: $(curl -s -m 30 -o /dev/null -w '%{http_code}' $B/voyages)"
