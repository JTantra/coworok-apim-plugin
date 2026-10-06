#!/bin/bash
# TEST: initialize + tools/list + one real tools/call via the MCP endpoint with a user token.
B=https://apim-psa-oen-hub.azure-api.net/oen-mcp/mcp
TOK=$(bash /home/jtantra/dev/live/psa-oen-api/infra/gw.sh token)
H=(-H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
curl -s -m 60 -X POST $B "${H[@]}" -D /tmp/h -o /dev/null -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}'
echo "initialize: $(head -1 /tmp/h | tr -d '\r')"
SID=$(grep -i mcp-session-id /tmp/h | cut -d' ' -f2 | tr -d '\r')
curl -s -m 60 -X POST $B "${H[@]}" ${SID:+-H "mcp-session-id: $SID"} -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' -o /dev/null
curl -s -m 60 -X POST $B "${H[@]}" ${SID:+-H "mcp-session-id: $SID"} -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' > /tmp/tl
curl -s -m 90 -X POST $B "${H[@]}" ${SID:+-H "mcp-session-id: $SID"} -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_voyages","arguments":{"at_risk_only":true,"limit":2}}}' > /tmp/tc
python3 - <<'PY'
import json
def body(f):
    t=open(f).read()
    if 'data:' in t: t=[l[5:] for l in t.splitlines() if l.startswith('data:')][-1]
    return json.loads(t)
tl=body('/tmp/tl')
for x in tl['result']['tools']: print('tool', x['name'], 'annotations=', x.get('annotations'))
tc=body('/tmp/tc')
if 'error' in tc: print('CALL ERROR', tc['error']); raise SystemExit(1)
r=tc['result']; txt=r['content'][0]['text']
d=json.loads(txt)
print('tools/call OK isError=',r.get('isError'),'matched=',d.get('matched'),'returned=',d.get('returned'),'first=',[v.get('vesselName') for v in d.get('voyages',[])][:2])
PY
