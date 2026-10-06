"""OEN account linking page.

Signed-in Entra users (via Container Apps built-in auth) link their own OEN
login. Credentials are verified against OEN, then stored in Key Vault as
`oen-cred-<entra oid>`. The secret name is derived only from the
platform-injected principal header, never from user input.
"""
import hashlib
import hmac
import html
import json
import logging
import os
import secrets as pysecrets
from datetime import datetime, timezone

import httpx
from azure.core.exceptions import ResourceNotFoundError, HttpResponseError
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse

log = logging.getLogger("oen-link")
logging.basicConfig(level=logging.INFO)

KV_URL = os.environ["KEY_VAULT_URL"]
OEN_API = os.environ.get("OEN_API_BASE", "https://sandbox.api.n2n.globalpsa.com/api/")
OEN_WEB = os.environ.get("OEN_WEB_ORIGIN", "https://sandbox.n2n.globalpsa.com")
BUILD_ID = os.environ.get("BUILD_ID", "dev")
CSRF_KEY = os.environ.get("CSRF_KEY") or pysecrets.token_hex(32)
OEN_HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36",
    "Origin": OEN_WEB,
    "Referer": OEN_WEB + "/oen/",
}

cred = ManagedIdentityCredential(client_id=os.environ.get("AZURE_CLIENT_ID"))
kv = SecretClient(vault_url=KV_URL, credential=cred)
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def principal(request: Request):
    """Identity injected by Container Apps auth. Clients cannot spoof it:
    the platform strips incoming X-MS-CLIENT-PRINCIPAL-* headers."""
    oid = request.headers.get("x-ms-client-principal-id", "").lower()
    name = request.headers.get("x-ms-client-principal-name", "")
    if len(oid) != 36 or oid.count("-") != 4 or not all(c in "0123456789abcdef-" for c in oid):
        return None, None
    return oid, name


def secret_name(oid: str) -> str:
    return f"oen-cred-{oid}"


def csrf_token(oid: str) -> str:
    return hmac.new(CSRF_KEY.encode(), oid.encode(), hashlib.sha256).hexdigest()


def current_link(oid: str):
    try:
        p = kv.get_secret(secret_name(oid)).properties
        if not p.enabled:
            return None
        return {"username": (p.tags or {}).get("oen_user", ""), "updated": p.updated_on}
    except ResourceNotFoundError:
        return None
    except HttpResponseError as e:
        if "disabled" in str(e).lower():
            return None
        raise


def page(name, link, msg="", err=False, token=""):
    e = html.escape
    status = (
        f'<p class="ok">Linked to OEN user <b>{e(link["username"])}</b> '
        f'(updated {link["updated"]:%d %b %Y %H:%M} UTC).</p>' if link else
        '<p class="warn">No OEN account linked yet.</p>'
    )
    note = f'<p class="{"err" if err else "ok"}">{e(msg)}</p>' if msg else ""
    unlink = (
        f'<form method="post" action="/unlink"><input type="hidden" name="csrf" value="{token}">'
        '<button class="secondary">Unlink</button></form>' if link else ""
    )
    return HTMLResponse(f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Link OEN account</title>
<style>
:root{{--bg:#0f1720;--card:#16212c;--line:#263544;--text:#e6edf3;--muted:#8fa1b3;--accent:#2f81f7;--ok:#3fb950;--warn:#d29922;--err:#f85149}}
@media (prefers-color-scheme: light){{:root{{--bg:#f4f6f8;--card:#fff;--line:#d8dee4;--text:#1f2328;--muted:#59636e}}}}
body{{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 "Segoe UI",system-ui,sans-serif;display:grid;place-items:center;min-height:100vh}}
main{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:28px 32px;width:min(440px,92vw)}}
h1{{font-size:20px;margin:0 0 4px}} .sub{{color:var(--muted);margin:0 0 20px}}
label{{display:block;font-size:13px;color:var(--muted);margin:14px 0 4px}}
input{{width:100%;box-sizing:border-box;padding:9px 11px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--text);font:inherit}}
button{{margin-top:18px;padding:9px 16px;border-radius:8px;border:0;background:var(--accent);color:#fff;font:inherit;cursor:pointer}}
button.secondary{{background:transparent;border:1px solid var(--line);color:var(--text)}}
.ok{{color:var(--ok)}} .warn{{color:var(--warn)}} .err{{color:var(--err)}} small{{color:var(--muted)}}
</style></head><body><main>
<h1>Link your OEN account</h1><p class="sub">Signed in as {e(name)}</p>
{status}{note}
<form method="post" action="/link" autocomplete="off">
<input type="hidden" name="csrf" value="{token}">
<label>OEN username</label><input name="username" required maxlength="128">
<label>OEN password</label><input name="password" type="password" required maxlength="256">
<button>{"Update" if link else "Link"} account</button></form>
{unlink}
<p><small>Your password is checked against OEN and stored encrypted in Key Vault under your Entra identity only.
Copilot uses it to call OEN on your behalf. It is never shown again.</small></p>
</main></body></html>""")


@app.get("/healthz")
def healthz():
    kv_state = "unknown"
    try:
        kv.get_secret("oen-healthcheck-nonexistent")
        kv_state = "ok"
    except ResourceNotFoundError:
        kv_state = "ok"
    except Exception as ex:  # noqa: BLE001
        kv_state = f"error:{type(ex).__name__}:{str(ex)[:160]}"
    return {"ok": kv_state == "ok", "build_id": BUILD_ID, "key_vault": kv_state}


@app.get("/")
def index(request: Request):
    oid, name = principal(request)
    if not oid:
        return RedirectResponse("/.auth/login/aad?post_login_redirect_uri=/")
    return page(name, current_link(oid), token=csrf_token(oid))


@app.post("/link")
def link(request: Request, csrf: str = Form(...), username: str = Form(...), password: str = Form(...)):
    oid, name = principal(request)
    if not oid:
        return JSONResponse({"error": "not signed in"}, status_code=401)
    if not hmac.compare_digest(csrf, csrf_token(oid)):
        return JSONResponse({"error": "bad csrf"}, status_code=403)
    username = username.strip()
    try:
        r = httpx.post(OEN_API + "auth/signin", headers=OEN_HEADERS,
                       json={"username": username, "password": password}, timeout=20)
    except httpx.HTTPError as ex:
        log.warning("OEN unreachable for %s: %s", oid, type(ex).__name__)
        return page(name, current_link(oid), "Couldn't reach OEN. Try again shortly.", True, csrf_token(oid))
    if r.status_code != 200 or not r.headers.get("jwt-token"):
        log.info("OEN rejected link for %s (HTTP %s)", oid, r.status_code)
        return page(name, current_link(oid), f"OEN rejected that login (HTTP {r.status_code}). Nothing saved.", True, csrf_token(oid))
    kv.set_secret(
        secret_name(oid),
        json.dumps({"username": username, "password": password}),
        content_type="application/json",
        enabled=True,
        tags={"oen_user": username, "entra_upn": name[:200], "linked": datetime.now(timezone.utc).isoformat()},
    )
    log.info("Linked oid=%s to OEN user=%s", oid, username)
    return page(name, current_link(oid), "OEN account verified and linked.", False, csrf_token(oid))


@app.post("/unlink")
def unlink(request: Request, csrf: str = Form(...)):
    oid, name = principal(request)
    if not oid:
        return JSONResponse({"error": "not signed in"}, status_code=401)
    if not hmac.compare_digest(csrf, csrf_token(oid)):
        return JSONResponse({"error": "bad csrf"}, status_code=403)
    # Overwrite with an empty, disabled version (avoids soft-delete name conflicts on re-link).
    if current_link(oid):
        kv.set_secret(secret_name(oid), "{}", enabled=False, tags={"unlinked": datetime.now(timezone.utc).isoformat()})
    log.info("Unlinked oid=%s", oid)
    return page(name, None, "OEN account unlinked.", False, csrf_token(oid))
