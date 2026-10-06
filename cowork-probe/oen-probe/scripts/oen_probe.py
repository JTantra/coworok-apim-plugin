import argparse, json, os, socket, sys, urllib.request, urllib.error
BASE = "https://sandbox.api.n2n.globalpsa.com/api/"
def call(path, method="GET", body=None, token=None):
    h = {"Content-Type": "application/json", "creatorOrgCode": "ONE",
         "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36",
         "Origin": "https://sandbox.n2n.globalpsa.com", "Referer": "https://sandbox.n2n.globalpsa.com/oen/"}
    if token: h["Authorization"] = token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.headers, json.loads(r.read() or b"null")
def main():
    p = argparse.ArgumentParser()
    p.add_argument("--user", default=os.environ.get("OEN_USER"))
    p.add_argument("--password", default=os.environ.get("OEN_PASS"))
    a = p.parse_args()
    print("python", sys.version.split()[0])
    if not a.user or not a.password:
        print("RESULT: NO_CREDENTIALS"); return
    try:
        print("dns", socket.gethostbyname("sandbox.api.n2n.globalpsa.com"))
    except Exception as e:
        print("RESULT: DNS_BLOCKED", repr(e)); return
    try:
        hdr, _ = call("auth/signin", "POST", {"username": a.user, "password": a.password})
        tok = hdr.get("jwt-token")
        if not tok: print("RESULT: SIGNIN_NO_TOKEN"); return
        _, v = call("svc/getAllVoyages", token=tok)
        if isinstance(v, dict):
            v = v.get("result", v.get("data", v))
        print("RESULT: OK voyages =", len(v) if isinstance(v, list) else str(v)[:300])
    except urllib.error.HTTPError as e:
        print("RESULT: HTTP_ERROR", e.code, e.reason)
    except Exception as e:
        print("RESULT: CONNECT_ERROR", repr(e))
if __name__ == "__main__":
    main()
