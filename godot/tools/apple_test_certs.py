#!/usr/bin/env python3
"""Test material for the App Store purchase checks (tests/apple_iap_test.gd): a stand-in "Apple" -- a root CA, an
intermediate and a leaf carrying Apple's App Store marks (the OIDs server/apple_jws.py looks for), an In-App Purchase
style API key -- and transactions signed like Apple's. Nothing here is Apple's; it only proves the checks work.
  python3 tools/apple_test_certs.py make DIR            -> DIR/{root.cer, root.sha256, leaf.key, chain.json, api.p8, api.pub}
  python3 tools/apple_test_certs.py sign DIR PAYLOAD    -> prints a JWS (ES256, x5c = leaf, intermediate, root)
      PAYLOAD: a JSON object, or @file; "--other-root" signs with a second, unrelated root (a bad chain)
  python3 tools/apple_test_certs.py verify-jwt DIR JWT  -> exit 0 if JWT is ES256-signed by DIR/api.p8 (the fake API's check)
Standard library plus the openssl command.
"""
import base64
import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "server"))
import apple_jws  # noqa: E402

EXT = """[inter]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
1.2.840.113635.100.6.2.1 = ASN1:NULL
[leaf]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
1.2.840.113635.100.6.11.1 = ASN1:NULL
"""


def run(args, data=None):
    r = subprocess.run(["openssl"] + args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        raise SystemExit("openssl %s: %s" % (" ".join(args[:2]), r.stderr.decode()))
    return r.stdout


def make_ca(d, tag):
    j = lambda n: os.path.join(d, n)  # noqa: E731
    with open(j("ext.cnf"), "w") as f:
        f.write(EXT)
    for n in ("root", "inter", "leaf"):
        run(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", j(tag + n + ".key")])
    run(["req", "-new", "-x509", "-key", j(tag + "root.key"), "-subj", "/CN=Test Root %s/O=Fatebound tests" % tag, "-days", "3650",
         "-set_serial", "1", "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign",
         "-out", j(tag + "root.pem")])
    for n, issuer, ext in (("inter", "root", "inter"), ("leaf", "inter", "leaf")):
        run(["req", "-new", "-key", j(tag + n + ".key"), "-subj", "/CN=Test %s %s/O=Fatebound tests" % (n, tag), "-out", j(tag + n + ".csr")])
        run(["x509", "-req", "-in", j(tag + n + ".csr"), "-CA", j(tag + issuer + ".pem"), "-CAkey", j(tag + issuer + ".key"),
             "-set_serial", "2" if n == "inter" else "3", "-days", "3000", "-extfile", j("ext.cnf"), "-extensions", ext,
             "-out", j(tag + n + ".pem")])
    ders = {}
    for n in ("root", "inter", "leaf"):
        ders[n] = run(["x509", "-in", j(tag + n + ".pem"), "-outform", "DER"])
    return ders


def make(d):
    os.makedirs(d, exist_ok=True)
    j = lambda n: os.path.join(d, n)  # noqa: E731
    ders = make_ca(d, "")
    other = make_ca(d, "x")
    with open(j("root.cer"), "wb") as f:
        f.write(ders["root"])
    with open(j("root.sha256"), "w") as f:
        f.write(hashlib.sha256(ders["root"]).hexdigest())
    chain = {k: base64.b64encode(v).decode() for k, v in ders.items()}
    chain["x"] = {k: base64.b64encode(v).decode() for k, v in other.items()}
    with open(j("chain.json"), "w") as f:
        json.dump(chain, f)
    run(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", j("api.ec")])
    run(["pkcs8", "-topk8", "-nocrypt", "-in", j("api.ec"), "-out", j("api.p8")])
    run(["ec", "-in", j("api.ec"), "-pubout", "-out", j("api.pub")])
    print("TEST_APPLE_OK")


def sign(d, payload, other_root=False):
    j = lambda n: os.path.join(d, n)  # noqa: E731
    chain = json.load(open(j("chain.json")))
    c = chain["x"] if other_root else chain
    tag = "x" if other_root else ""
    head = apple_jws.b64url(json.dumps({"alg": "ES256", "x5c": [c["leaf"], c["inter"], c["root"]]}, separators=(",", ":")).encode())
    body = apple_jws.b64url(json.dumps(payload, separators=(",", ":")).encode())
    der = run(["dgst", "-sha256", "-sign", j(tag + "leaf.key")], (head + "." + body).encode())
    return head + "." + body + "." + apple_jws.b64url(apple_jws.der_to_raw(der))


def verify_jwt(d, jwt):
    parts = jwt.split(".")
    if len(parts) != 3:
        return False
    sig = os.path.join(d, "jwt.sig")
    with open(sig, "wb") as f:
        f.write(apple_jws.raw_to_der(apple_jws.unb64url(parts[2])))
    r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", os.path.join(d, "api.pub"), "-signature", sig],
                       input=(parts[0] + "." + parts[1]).encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return r.returncode == 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "make":
        make(sys.argv[2])
    elif cmd == "sign":
        raw = sys.argv[3]
        p = json.load(open(raw[1:])) if raw.startswith("@") else json.loads(raw)
        print(sign(sys.argv[2], p, "--other-root" in sys.argv))
    elif cmd == "verify-jwt":
        sys.exit(0 if verify_jwt(sys.argv[2], sys.argv[3]) else 1)
    else:
        raise SystemExit(__doc__)
