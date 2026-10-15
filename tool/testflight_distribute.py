#!/usr/bin/env python3
"""Distribute an uploaded build on TestFlight — internal AND external.

`xcrun altool --upload-package` only uploads. This waits for App Store Connect
to finish processing the build, then:

  1. sets the "What to Test" note (en-US) from --notes,
  2. adds the build to EVERY beta group of the app (internal and external),
  3. submits it for Beta App Review, which external testers need.

Idempotent: a group that already has the build, or a build already submitted,
is not an error. Uses the App Store Connect API with an ES256 JWT.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (path to AuthKey_*.p8), ASC_APP_ID.
Args: --version 1.0.2 --build 7 [--notes "..."] [--timeout-min 45]
Needs: pip install pyjwt cryptography requests
"""
import argparse
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    with open(os.environ["ASC_KEY_PATH"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, **kw):
    r = requests.request(method, API + path,
                         headers={"Authorization": f"Bearer {token()}"},
                         timeout=60, **kw)
    if r.status_code >= 400:
        return r.status_code, r.json() if r.content else {}
    return r.status_code, (r.json() if r.content else {})


def find_build(app, version, build):
    code, body = call("GET", "/builds", params={
        "filter[app]": app, "filter[version]": build,
        "filter[preReleaseVersion.version]": version, "limit": 5})
    if code >= 400:
        sys.exit(f"build lookup failed: {code} {body}")
    data = body.get("data", [])
    return data[0] if data else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--notes", default="")
    p.add_argument("--timeout-min", type=int, default=45)
    a = p.parse_args()
    app = os.environ["ASC_APP_ID"]

    deadline = time.time() + a.timeout_min * 60
    while True:
        b = find_build(app, a.version, a.build)
        state = b["attributes"]["processingState"] if b else "NOT_FOUND"
        print(f"build {a.version} ({a.build}): {state}", flush=True)
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            sys.exit(f"processing ended {state}")
        if time.time() > deadline:
            sys.exit("timed out waiting for processing")
        time.sleep(60)
    bid = b["id"]

    if a.notes:
        code, body = call("GET", f"/builds/{bid}/betaBuildLocalizations")
        locs = body.get("data", []) if code < 400 else []
        en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
        attrs = {"whatsNew": a.notes[:4000]}
        if en:
            call("PATCH", f"/betaBuildLocalizations/{en['id']}", json={"data": {
                "type": "betaBuildLocalizations", "id": en["id"],
                "attributes": attrs}})
        else:
            call("POST", "/betaBuildLocalizations", json={"data": {
                "type": "betaBuildLocalizations",
                "attributes": {**attrs, "locale": "en-US"},
                "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        print("what-to-test note set")

    code, body = call("GET", f"/apps/{app}/betaGroups", params={"limit": 50})
    if code >= 400:
        sys.exit(f"group lookup failed: {code} {body}")
    groups = body.get("data", [])
    for g in groups:
        internal = g["attributes"].get("isInternalGroup")
        code, body = call("POST", f"/betaGroups/{g['id']}/relationships/builds",
                          json={"data": [{"type": "builds", "id": bid}]})
        ok = code < 400 or code == 409
        print(f"{'internal' if internal else 'external'} group "
              f"'{g['attributes']['name']}': {'added' if ok else f'{code} {body}'}")

    if any(not g["attributes"].get("isInternalGroup") for g in groups):
        code, body = call("POST", "/betaAppReviewSubmissions", json={"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        if code < 400:
            print("submitted for Beta App Review (external testers get it once approved)")
        elif code == 409:
            print("already submitted for Beta App Review")
        else:
            sys.exit(f"beta review submission failed: {code} {body}")
    else:
        print("no external group exists; nothing to submit for review")


if __name__ == "__main__":
    main()
