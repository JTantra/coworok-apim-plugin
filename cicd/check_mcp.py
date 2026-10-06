#!/usr/bin/env python3
"""Gate the live APIM MCP server (source of truth for tools). No files written.
Fails if tools/list is empty, any tool lacks annotations.readOnlyHint=true / destructiveHint=false
(Cowork would then prompt for approval), or a list_voyages tools/call fails."""
import json, sys, requests

URL = "https://apim-psa-oen-hub.azure-api.net/oen-mcp/mcp"
H = {"Authorization": f"Bearer {sys.argv[1]}", "Content-Type": "application/json", "Accept": "application/json, text/event-stream"}


def rpc(body, sid=None):
    r = requests.post(URL, headers=dict(H, **({"mcp-session-id": sid} if sid else {})), json=body, timeout=90)
    r.raise_for_status(); t = r.text
    if "data:" in t:
        t = [l[5:] for l in t.splitlines() if l.startswith("data:")][-1]
    return r.headers.get("mcp-session-id", sid), (json.loads(t) if t.strip() else None)


sid, _ = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "cicd", "version": "1"}}})
rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
_, res = rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, sid)
tools = res["result"]["tools"]
bad = [t["name"] for t in tools
       if (t.get("annotations") or {}).get("readOnlyHint") is not True
       or (t.get("annotations") or {}).get("destructiveHint") is not False]
for t in tools:
    print(f"  tool {t['name']:<18} annotations={t.get('annotations')}")
if not tools: sys.exit("FAIL: tools/list returned no tools")
if bad: sys.exit(f"FAIL: missing readOnlyHint=true/destructiveHint=false (Cowork will prompt): {bad}")
_, c = rpc({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "list_voyages", "arguments": {"at_risk_only": True, "limit": 1}}}, sid)
if "error" in c or c["result"].get("isError"):
    sys.exit(f"FAIL: tools/call list_voyages: {c.get('error') or c['result']}")
print(f"OK: {len(tools)} tools annotated, tools/call list_voyages succeeded")
