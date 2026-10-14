#!/usr/bin/env python3
"""Fatebound Siege server: checks one App Store purchase (IOS_PORT_SPEC_FOR_CLAUDE.md section 3).

server/iap_verify_apple.gd runs this once per purchase, as its own process (never blocking the game loop):
  python3 apple_jws.py --jws FILE --out FILE --root AppleRootCA-G3.cer
                       [--key P8 --issuer ID --key-id KID --bundle com.fatebound.game] [--api URL]
to check the server's In-App Purchase key against Apple without a purchase (0.31.133; run it on the server):
  sudo bash -c 'set -a; . /etc/fatebound-siege.env; python3 /srv/fatebound-siege/server/apple_jws.py --api-check \
      --key /etc/fatebound-siege/appstore-key.p8 --issuer "$SIEGE_APPSTORE_ISSUER" --key-id "$SIEGE_APPSTORE_KEY_ID"'
     asks Apple (production and sandbox) for a made-up transaction: 404 (or 400) = the key is accepted (Apple only
     judged the transaction id), 401 = Apple refused the key. Prints one line per environment; exit 0 when both accept it.
and once per Game Center account link (0.31.132, section 4):
  python3 apple_jws.py --gc FILE --out FILE [--bundle com.fatebound.game]
     FILE: {"id": teamPlayerID, "url": publicKeyURL, "sig": base64, "salt": base64, "ts": ms} from the phone's
     GKLocalPlayer.fetchItems(forIdentityVerificationSignature:). The key's certificate is fetched from Apple over
     HTTPS (an apple.com host only), must be in date, and its key must verify the RSA-SHA256 signature over
     teamPlayerID + bundle id + timestamp (8 bytes, big-endian) + salt.

1. The signed transaction (JWS, ES256) the phone sent: its x5c chain (leaf, intermediate) must chain to Apple Root CA - G3
   (the bundled public root, SHA-256 pinned below) at the transaction's signedDate, the leaf and intermediate must carry
   Apple's App Store receipt-signing marks (OIDs 1.2.840.113635.100.6.11.1 and .6.2.1), and the signature must verify
   with the leaf's key.
2. With an In-App Purchase key (--key/--issuer/--key-id): Apple's App Store Server API is asked for the same transaction
   (GET /inApps/v1/transactions/{transactionId}, production or sandbox by the transaction's environment, a JWT signed
   ES256 with the key) and its answer is checked the same way. Without a key: "api" is "off".
Writes one JSON object to --out:
  {"ok": true, "payload": {...}, "confirmed": {...} or null, "api": "ok" | "off" | "notfound" | "denied" | "unreachable"}
  {"ok": false, "why": "<reason>"}
The game rules (bundle id, product, refunds, the account's token) are checked by iap_verify_apple.gd.
Standard library plus the openssl command only: nothing to pip-install on the server. The key never leaves the file
and nothing is printed but the result.
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179"   # Apple Root CA - G3
LEAF_OID = bytes.fromhex("060a2a864886f76364060b01")          # 1.2.840.113635.100.6.11.1 (Mac App Store receipt signing)
INTERMEDIATE_OID = bytes.fromhex("060a2a864886f76364060201")  # 1.2.840.113635.100.6.2.1 (Apple WWDR intermediate)
API_PRODUCTION = "https://api.storekit.itunes.apple.com"
API_SANDBOX = "https://api.storekit-sandbox.itunes.apple.com"


class Bad(Exception):
    pass


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def unb64url(s):
    s = s.strip()
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def pem(der, kind="CERTIFICATE"):
    body = base64.encodebytes(der).decode().replace("\n", "")
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN %s-----\n%s\n-----END %s-----\n" % (kind, "\n".join(lines), kind)


def openssl(args, data=None):
    r = subprocess.run(["openssl"] + args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    return r.returncode, r.stdout, r.stderr


# ---------------- ECDSA signatures: JWS uses raw r||s (64 bytes), openssl uses DER ----------------
def _der_int(b):
    b = b.lstrip(b"\x00") or b"\x00"
    if b[0] & 0x80:
        b = b"\x00" + b
    return b"\x02" + bytes([len(b)]) + b


def raw_to_der(raw):
    if len(raw) != 64:
        raise Bad("signature length")
    body = _der_int(raw[:32]) + _der_int(raw[32:])
    return b"\x30" + bytes([len(body)]) + body


def der_to_raw(der):
    if len(der) < 8 or der[0] != 0x30:
        raise Bad("signature encoding")
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        if der[i] != 0x02:
            raise Bad("signature encoding")
        n = der[i + 1]
        v = der[i + 2:i + 2 + n].lstrip(b"\x00")
        if len(v) > 32:
            raise Bad("signature encoding")
        out += v.rjust(32, b"\x00")
        i += 2 + n
    return out


# ---------------- the signed transaction ----------------
def verify_jws(jws, root_der, work):
    """-> the payload of an Apple-signed JWS, or raises Bad."""
    parts = jws.strip().split(".")
    if len(parts) != 3:
        raise Bad("format")
    try:
        header = json.loads(unb64url(parts[0]))
        payload = json.loads(unb64url(parts[1]))
        sig = unb64url(parts[2])
    except (ValueError, TypeError):
        raise Bad("format")
    if not isinstance(header, dict) or not isinstance(payload, dict) or header.get("alg") != "ES256":
        raise Bad("algorithm")
    x5c = header.get("x5c")
    if not isinstance(x5c, list) or len(x5c) < 2:
        raise Bad("chain")
    try:
        leaf = base64.b64decode(x5c[0])
        inter = base64.b64decode(x5c[1])
        if len(x5c) > 2 and base64.b64decode(x5c[2]) != root_der:
            raise Bad("chain root")
    except (ValueError, TypeError):
        raise Bad("chain")
    if LEAF_OID not in leaf or INTERMEDIATE_OID not in inter:
        raise Bad("chain marks")
    at = int(payload.get("signedDate", 0)) // 1000 or int(time.time())
    files = {"root": pem(root_der), "inter": pem(inter), "leaf": pem(leaf)}
    paths = {}
    for k, v in files.items():
        paths[k] = os.path.join(work, k + ".pem")
        with open(paths[k], "w") as f:
            f.write(v)
    code, out, _ = openssl(["verify", "-attime", str(at), "-CAfile", paths["root"], "-untrusted", paths["inter"], paths["leaf"]])
    if code != 0 or not out.strip().endswith(b"OK"):
        raise Bad("chain")
    code, pub, _ = openssl(["x509", "-in", paths["leaf"], "-pubkey", "-noout"])
    if code != 0:
        raise Bad("chain")
    paths["pub"] = os.path.join(work, "pub.pem")
    paths["sig"] = os.path.join(work, "sig.der")
    with open(paths["pub"], "wb") as f:
        f.write(pub)
    with open(paths["sig"], "wb") as f:
        f.write(raw_to_der(sig))
    code, out, _ = openssl(["dgst", "-sha256", "-verify", paths["pub"], "-signature", paths["sig"]],
                           (parts[0] + "." + parts[1]).encode())
    if code != 0 or b"Verified OK" not in out:
        raise Bad("signature")
    return payload


# ---------------- the App Store Server API ----------------
def api_jwt(key_path, issuer, key_id, bundle, now):
    head = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1", "bid": bundle},
                               separators=(",", ":")).encode())
    signing = (head + "." + claims).encode()
    code, der, _ = openssl(["dgst", "-sha256", "-sign", key_path], signing)
    if code != 0:
        raise Bad("key")
    return head + "." + claims + "." + b64url(der_to_raw(der))


def confirm(api_base, tx_id, jwt):
    """-> ("ok", signedTransactionInfo) | ("notfound" | "denied" | "unreachable", None)"""
    req = urllib.request.Request("%s/inApps/v1/transactions/%s" % (api_base, tx_id),
                                 headers={"Authorization": "Bearer " + jwt, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            body = json.loads(r.read().decode())
            info = body.get("signedTransactionInfo", "") if isinstance(body, dict) else ""
            return ("ok", info) if info else ("unreachable", None)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return "notfound", None
        if e.code in (401, 403):
            return "denied", None
        return "unreachable", None
    except (urllib.error.URLError, OSError, ValueError):
        return "unreachable", None


def check(args):
    with open(args.root, "rb") as f:
        root_der = f.read()
    if hashlib.sha256(root_der).hexdigest() != (args.root_sha256 or ROOT_SHA256):
        return {"ok": False, "why": "root"}
    with open(args.jws) as f:
        jws = f.read().strip()
    with tempfile.TemporaryDirectory(prefix="fb-apple-") as work:
        try:
            payload = verify_jws(jws, root_der, work)
        except Bad as e:
            return {"ok": False, "why": str(e)}
        out = {"ok": True, "payload": payload, "confirmed": None, "api": "off"}
        if not (args.key and args.issuer and args.key_id):
            return out
        tx = str(payload.get("transactionId", ""))
        if not tx.isdigit():
            return {"ok": False, "why": "transaction id"}
        try:
            jwt = api_jwt(args.key, args.issuer, args.key_id, args.bundle, int(time.time()))
        except Bad:
            out["api"] = "denied"
            return out
        base = args.api or (API_PRODUCTION if payload.get("environment") == "Production" else API_SANDBOX)
        status, info = confirm(base.rstrip("/"), tx, jwt)
        out["api"] = status
        if status == "ok":
            try:
                out["confirmed"] = verify_jws(info, root_der, work)
            except Bad as e:
                return {"ok": False, "why": "api " + str(e)}
        return out


def api_check(args):
    if not (args.key and args.issuer and args.key_id):
        print("api-check needs --key, --issuer and --key-id")
        return 2
    try:
        jwt = api_jwt(args.key, args.issuer, args.key_id, args.bundle, int(time.time()))
    except Bad:
        print("the key file can't sign (is it the .p8 from App Store Connect?)")
        return 1
    ok = True
    for name, base in (("production", args.api or API_PRODUCTION), ("sandbox", args.api or API_SANDBOX)):
        req = urllib.request.Request("%s/inApps/v1/transactions/%s" % (base.rstrip("/"), "1000000000000001"),
                                     headers={"Authorization": "Bearer " + jwt, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                code, body = r.status, r.read(2048).decode(errors="replace")
        except urllib.error.HTTPError as e:
            code, body = e.code, e.read(2048).decode(errors="replace")
        except (urllib.error.URLError, OSError) as e:
            code, body = 0, str(e)
        try:
            err = json.loads(body) if body.strip().startswith("{") else {}
        except ValueError:
            err = {}
        detail = " (%s %s)" % (err.get("errorCode", ""), err.get("errorMessage", "")) if err.get("errorCode") else ""
        if code in (400, 404):                          # past the key check: Apple only judged the made-up id
            verdict = "key accepted -- Apple answered %d for a made-up transaction%s" % (code, detail)
        elif code in (401, 403):
            verdict = "key REFUSED (%d): check the key id, the issuer id and that it is an In-App Purchase key" % code
            ok = False
        elif code == 0:
            verdict = "Apple not reached: " + body
            ok = False
        else:
            verdict = "unexpected answer %d%s" % (code, detail)
            ok = False
        print("%-10s %s  (key %s, bundle %s)" % (name, verdict, args.key_id, args.bundle))
    return 0 if ok else 1


def check_gc(args):
    with open(args.gc) as f:
        g = json.load(f)
    try:
        team = str(g["id"])
        url = str(g["url"])
        sig = base64.b64decode(str(g["sig"]))
        salt = base64.b64decode(str(g["salt"]))
        ts = int(g["ts"])
    except (KeyError, ValueError, TypeError):
        return {"ok": False, "why": "format"}
    u = urllib.parse.urlparse(url)
    host = u.hostname or ""
    if not ((u.scheme == "https" and (host == "apple.com" or host.endswith(".apple.com")))
            or (args.gc_allow_http and u.scheme == "http" and host == "127.0.0.1")):
        return {"ok": False, "why": "url"}
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=10) as r:
            cert = r.read(65536)
    except (urllib.error.URLError, OSError, ValueError):
        return {"ok": False, "why": "unreachable"}
    with tempfile.TemporaryDirectory(prefix="fb-gc-") as work:
        cp = os.path.join(work, "gc.pem")
        with open(cp, "w") as f:
            f.write(cert.decode() if cert.startswith(b"-----BEGIN") else pem(cert))
        code, _, _ = openssl(["x509", "-in", cp, "-checkend", "0", "-noout"])
        if code != 0:
            return {"ok": False, "why": "certificate"}
        code, pub, _ = openssl(["x509", "-in", cp, "-pubkey", "-noout"])
        if code != 0:
            return {"ok": False, "why": "certificate"}
        paths = {"pub": os.path.join(work, "pub.pem"), "sig": os.path.join(work, "sig.bin")}
        with open(paths["pub"], "wb") as f:
            f.write(pub)
        with open(paths["sig"], "wb") as f:
            f.write(sig)
        data = team.encode() + args.bundle.encode() + ts.to_bytes(8, "big") + salt
        code, out, _ = openssl(["dgst", "-sha256", "-verify", paths["pub"], "-signature", paths["sig"]], data)
        if code != 0 or b"Verified OK" not in out:
            return {"ok": False, "why": "signature"}
    return {"ok": True}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jws", default="")
    ap.add_argument("--gc", default="")
    ap.add_argument("--gc-allow-http", action="store_true")   # tests: a local stand-in for Apple's key server
    ap.add_argument("--out", default="")
    ap.add_argument("--api-check", action="store_true")
    ap.add_argument("--root", default="")
    ap.add_argument("--root-sha256", default="")      # tests: their own root
    ap.add_argument("--key", default="")
    ap.add_argument("--issuer", default="")
    ap.add_argument("--key-id", default="")
    ap.add_argument("--bundle", default="com.fatebound.game")
    ap.add_argument("--api", default="")              # tests: a fake App Store Server API
    args = ap.parse_args()
    if args.api_check:
        return api_check(args)
    if not args.out:
        ap.error("--out is required")
    try:
        res = check_gc(args) if args.gc else check(args)
    except Exception as e:                              # (never a traceback with paths in it: the reason only)
        res = {"ok": False, "why": "helper " + type(e).__name__}
    tmp = args.out + ".part"
    with open(tmp, "w") as f:
        json.dump(res, f)
    os.replace(tmp, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
