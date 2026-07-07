#!/usr/bin/env python3
"""Test setup wizard APIs and bootinfo completeness."""
import json
import sys
import urllib.error
import urllib.request
import http.cookiejar

SITE = "http://127.0.0.1:8000"


def main():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

    def post(path, data=None):
        body = json.dumps(data or {}).encode()
        req = urllib.request.Request(
            SITE + path, data=body, headers={"Content-Type": "application/json"}
        )
        try:
            resp = opener.open(req)
            return resp.status, resp.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()

    def get(path):
        req = urllib.request.Request(SITE + path)
        try:
            resp = opener.open(req)
            return resp.status, resp.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()

    status, body = post("/api/method/login", {"usr": "Administrator", "pwd": "admin"})
    print(f"LOGIN: HTTP {status}")
    try:
        print(json.dumps(json.loads(body), indent=2)[:500])
    except json.JSONDecodeError:
        print(body[:500])

    apis = [
        "/api/method/frappe.desk.page.setup_wizard.setup_wizard.load_languages",
        "/api/method/frappe.desk.page.setup_wizard.setup_wizard.load_user_details",
        "/api/method/frappe.boot.get_bootinfo",
        "/api/method/frappe.auth.get_logged_user",
    ]

    boot_keys_expected = [
        "setup_complete",
        "setup_wizard_requires",
        "setup_wizard_completed_apps",
        "workspaces",
        "workspace_sidebar_item",
        "user",
        "lang",
        "apps_data",
    ]

    for api in apis:
        status, body = get(api)
        print(f"\n=== {api} === HTTP {status}")
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError as e:
            print(f"INVALID JSON: {e}")
            print(body[:800])
            continue

        if parsed.get("exc"):
            print(f"EXCEPTION: {parsed.get('exc_type')}")
            print(str(parsed.get("exc", ""))[:600])

        msg = parsed.get("message")
        if api.endswith("get_bootinfo") and isinstance(msg, dict):
            print("bootinfo keys present:")
            for k in boot_keys_expected:
                if k in msg:
                    v = msg[k]
                    if isinstance(v, dict):
                        print(f"  {k}: dict({len(v)} keys)")
                    elif isinstance(v, list):
                        print(f"  {k}: list(len={len(v)})")
                    else:
                        print(f"  {k}: {v!r}")
                else:
                    print(f"  {k}: MISSING")
        elif isinstance(msg, list):
            print(f"message: list(len={len(msg)}), sample={msg[:3]}")
        elif isinstance(msg, dict):
            print(f"message keys: {list(msg.keys())}")
            print(json.dumps(msg, indent=2)[:600])
        else:
            print(f"message: {msg!r}")

    status, body = get("/app/setup-wizard")
    print(f"\n=== /app/setup-wizard === HTTP {status}")
    if status >= 400:
        print(body[:800])
    elif "frappe.boot" in body:
        idx = body.find("frappe.boot = ")
        if idx >= 0:
            snippet = body[idx : idx + 2500]
            end = snippet.find(";\n")
            boot_str = snippet[len("frappe.boot = ") : end] if end > 0 else snippet
            try:
                boot = json.loads(boot_str)
                print(f"Embedded boot keys: {len(boot)}")
                for k in boot_keys_expected:
                    present = k in boot
                    print(f"  {k}: {'OK' if present else 'MISSING'}")
            except json.JSONDecodeError as e:
                print(f"Embedded boot JSON invalid: {e}")
                print(boot_str[:500])


if __name__ == "__main__":
    main()
    sys.exit(0)
