"""Fyller i "Vad ska testas" i TestFlight med versionens avsnitt ur changelogen.

Körs av TestFlight-jobbet i .github/workflows/release.yml efter uppladdningen (docs/specs/2026-11-08-release.md).

    python3 scripts/testflight_notes.py --version 1.0.1 --build 301 --notes-file notes.md

Nyckeln läses från miljövariablerna ASC_KEY_ID, ASC_ISSUER_ID och ASC_KEY_PATH. Inga hemliga värden skrivs ut.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "se.hardyson.sophamtning"
MAX_LENGTH = 4000  # Apples gräns för whatsNew.


def plain_notes(markdown: str) -> str:
    """Release Pleases Markdown som ren text: rubriken med versionen bort, länkar och commit-referenser bort."""
    lines = []
    for line in markdown.splitlines():
        line = line.rstrip()
        if line.startswith("## "):
            continue  # "## [1.0.1](…) (2026-11-08)": versionen syns redan i TestFlight.
        # " ([#30](…))" och " ([c131d82](…))" efter en rad.
        line = re.sub(r"\s*\(\[[^\]]+\]\([^)]+\)\)", "", line)
        # Övriga länkar blir sin text.
        line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
        line = re.sub(r"\*\*([^*]+)\*\*", r"\1", line)
        if line.startswith("### "):
            line = line[4:]
        elif line.startswith(("* ", "- ")):
            line = "• " + line[2:]
        lines.append(line)
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()
    if len(text) > MAX_LENGTH:
        text = text[: MAX_LENGTH - 1].rstrip() + "…"
    return text


def token() -> str:
    import jwt  # Laddas här, så att plain_notes går att testa utan biblioteket.

    with open(os.environ["ASC_KEY_PATH"], encoding="utf-8") as f:
        key = f.read()
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def request(method: str, path: str, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:500]
        raise SystemExit(f"{method} {urllib.parse.urlsplit(url).path}: HTTP {error.code}: {detail}") from None
    return json.loads(raw) if raw else {}


def find_build(app_id: str, version: str, build: str, wait_minutes: int) -> dict:
    """Väntar tills bygget finns och är färdigbearbetat hos Apple."""
    query = urllib.parse.urlencode({
        "filter[app]": app_id,
        "filter[version]": build,
        "filter[preReleaseVersion.version]": version,
        "fields[builds]": "processingState",
    })
    deadline = time.time() + wait_minutes * 60
    while True:
        builds = request("GET", f"/builds?{query}")["data"]
        if builds:
            state = builds[0]["attributes"].get("processingState")
            print(f"Bygget {version} ({build}): {state}")
            if state == "VALID":
                return builds[0]
            if state in ("FAILED", "INVALID"):
                raise SystemExit(f"Apple kunde inte bearbeta bygget: {state}")
        else:
            print(f"Bygget {version} ({build}) syns inte än")
        if time.time() > deadline:
            raise SystemExit(f"Bygget var inte färdigbearbetat efter {wait_minutes} minuter")
        time.sleep(30)


def set_notes(app_id: str, build_id: str, notes: str) -> None:
    """Skriver texten på byggets alla språk. Saknas ett språk som appens testinformation har, skapas det."""
    existing = request("GET", f"/builds/{build_id}/betaBuildLocalizations")["data"]
    for loc in existing:
        request("PATCH", f"/betaBuildLocalizations/{loc['id']}", {
            "data": {"type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": notes}},
        })
        print(f"Uppdaterade {loc['attributes']['locale']}")
    done = {loc["attributes"]["locale"] for loc in existing}
    app_locales = [loc["attributes"]["locale"] for loc in request("GET", f"/apps/{app_id}/betaAppLocalizations")["data"]]
    for locale in app_locales or ["sv"]:
        if locale in done:
            continue
        request("POST", "/betaBuildLocalizations", {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": locale, "whatsNew": notes},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            },
        })
        print(f"Skapade {locale}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True, help="Appens version, till exempel 1.0.1")
    parser.add_argument("--build", required=True, help="Byggnumret")
    parser.add_argument("--notes-file", required=True, help="Versionens avsnitt ur changelogen, i Markdown")
    parser.add_argument("--wait-minutes", type=int, default=30)
    args = parser.parse_args()

    with open(args.notes_file, encoding="utf-8") as f:
        notes = plain_notes(f.read())
    if not notes:
        print("Ingen text att lägga in")
        return
    print("Vad ska testas:\n" + notes)

    apps = request("GET", "/apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID}))["data"]
    if not apps:
        raise SystemExit(f"Hittar ingen app med paket-id {BUNDLE_ID}")
    app_id = apps[0]["id"]
    build = find_build(app_id, args.version, args.build, args.wait_minutes)
    set_notes(app_id, build["id"], notes)


if __name__ == "__main__":
    sys.exit(main())
