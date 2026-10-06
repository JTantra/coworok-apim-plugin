#!/bin/bash
B=https://apim-psa-oen-hub.azure-api.net
echo "== no token"; curl -s -m 30 -o /dev/null -w "%{http_code}\n" "$B/oen/voyages?limit=1"
TOK=$(bash /home/jtantra/dev/live/psa-oen-api/infra/gw.sh token 2>&1)
case "$TOK" in ey*) echo "token ok";; *) echo "TOKEN ERROR: $TOK" | head -5; exit 1;; esac
echo "== list_voyages (user token)"
curl -s -m 60 -w "\nHTTP %{http_code} %{time_total}s\n" -H "Authorization: Bearer $TOK" "$B/oen/voyages?limit=2&nodes=PSASG" | cut -c1-900
echo "== mcp tools/list"
curl -s -m 60 -X POST "$B/oen-mcp/mcp" -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}' -D /tmp/h | head -c 400; echo
grep -i mcp-session-id /tmp/h
SID=$(grep -i mcp-session-id /tmp/h | cut -d' ' -f2 | tr -d '\r')
curl -s -m 60 -X POST "$B/oen-mcp/mcp" -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" ${SID:+-H "mcp-session-id: $SID"} \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | grep -o '"name":"[a-z_]*"' | sort -u
