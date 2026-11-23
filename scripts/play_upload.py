"""Laddar upp en AAB till Google Play med Play Developer API v3.

Skriptet skapar en edit, laddar upp bundlen, sätter spåret (till exempel intern testning) med "Vad är nytt" på sv-SE och
status completed, och gör commit på editen. Fallerar ett steg görs ingen commit, och inget ändras i Play Console.
Körs av jobbet Google Play i release.yml. Se docs/specs/2026-11-08-release.md och docs/android-google-play.md.

    python3 scripts/play_upload.py upload --aab app-release.aab --track internal --notes-file notes.md \\
        --package se.hardyson.sophamtning

Tjänstkontots JSON-nyckel läses från filen i PLAY_SERVICE_ACCOUNT_PATH. Inga hemliga värden skrivs ut. Med
--status draft blir versionen ett utkast, som släpps för hand i Play Console.
"""

import argparse
import os
import sys
import time

from release_notes import plain_notes

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD_API = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
LANGUAGE = "sv-SE"
MAX_LENGTH = 500  # Play Consoles gräns för "Vad är nytt" per språk.
RETRY_DELAY = 10  # Sekunder före det andra försöket efter ett tillfälligt fel.


class PlayError(Exception):
    """Ett fel som stoppar uppladdningen, med ett meddelande som går att läsa i loggen."""


def play_notes(markdown: str) -> str:
    """Changelogens avsnitt som ren text, som i TestFlight, högst 500 tecken. Längre text kortas vid en hel rad."""
    text = plain_notes(markdown)
    if len(text) <= MAX_LENGTH:
        return text
    kept = []
    for line in text.splitlines():
        if len("\n".join(kept + [line, "…"])) > MAX_LENGTH:
            break
        kept.append(line)
    while kept and not kept[-1].strip():
        kept.pop()
    if not kept:
        # En enda rad som är för lång kortas vid ett tecken.
        return text[: MAX_LENGTH - 1].rstrip() + "…"
    return "\n".join(kept + ["…"])


def _path(url: str) -> str:
    return url.split("?")[0].replace(API, "").replace(UPLOAD_API, "")


def _hint(detail: str) -> str:
    if "draft app" in detail:
        return (
            "\nAppen är fortfarande ett utkast i Play Console. Det första bygget laddas upp och släpps i intern "
            "testning för hand, se docs/android-google-play.md."
        )
    if "changesNotSentForReview" in detail or "cannot be sent for review" in detail:
        return (
            "\nPlay Console har ändringar som måste skickas för granskning för hand. Öppna Publiceringsöversikt i "
            "Play Console, skicka ändringarna för granskning och ladda upp igen med taggen, se "
            "docs/android-google-play.md."
        )
    return ""


def call(session, method: str, url: str, **kwargs):
    """Ett anrop till API:t. Ett tillfälligt fel (HTTP 5xx eller nätet) prövas en gång till. Ett fel blir PlayError med
    metod, sökväg, status och Googles meddelande."""
    for attempt in (1, 2):
        try:
            # requests.RequestException ärver OSError, så nätfel fångas utan att requests behöver laddas här.
            response = session.request(method, url, timeout=300, **kwargs)
        except OSError as error:
            if attempt == 1:
                print(f"{method} {_path(url)}: nätet svarade inte ({type(error).__name__}), försöker igen")
                time.sleep(RETRY_DELAY)
                continue
            raise PlayError(
                f"{method} {_path(url)}: nätet svarade inte två gånger: {type(error).__name__}: {error}"
            ) from None
        if response.status_code >= 500 and attempt == 1:
            print(f"{method} {_path(url)}: HTTP {response.status_code}, försöker igen")
            time.sleep(RETRY_DELAY)
            continue
        break
    if response.status_code >= 400:
        try:
            detail = response.json().get("error", {}).get("message") or response.text
        except ValueError:
            detail = response.text
        detail = str(detail)
        raise PlayError(f"{method} {_path(url)}: HTTP {response.status_code}: {detail[:500]}" + _hint(detail))
    return response


def upload(session, package: str, aab: str, track: str, notes: str, status: str = "completed") -> int:
    """Gör hela uppladdningen och ger bundlens versionCode. [status] är completed, eller draft för ett utkast."""
    base = f"{API}/{package}/edits"
    edit = call(session, "POST", base).json()["id"]
    print("Edit skapad")

    # Bundlen laddas upp med en återupptagbar uppladdning, som klarar stora filer.
    with open(aab, "rb") as f:
        content = f.read()
    start = call(
        session, "POST", f"{UPLOAD_API}/{package}/edits/{edit}/bundles?uploadType=resumable",
        headers={"X-Upload-Content-Type": "application/octet-stream", "X-Upload-Content-Length": str(len(content))},
    )
    location = start.headers.get("Location") or start.headers.get("location")
    if not location:
        raise PlayError("Play gav ingen adress för uppladdningen av bundlen")
    bundle = call(session, "PUT", location, data=content, headers={"Content-Type": "application/octet-stream"}).json()
    version_code = int(bundle["versionCode"])
    print(f"Bundlen uppladdad, versionCode {version_code}")

    release = {"versionCodes": [str(version_code)], "status": status}
    if notes:
        release["releaseNotes"] = [{"language": LANGUAGE, "text": notes}]
    call(session, "PUT", f"{base}/{edit}/tracks/{track}", json={"track": track, "releases": [release]})
    print(f"Spåret {track} satt, status {status}")

    call(session, "POST", f"{base}/{edit}:commit")
    print(f"Klart: versionCode {version_code} i spåret {track}")
    return version_code


def service_account_path() -> str:
    path = os.environ.get("PLAY_SERVICE_ACCOUNT_PATH", "")
    if not path or not os.path.isfile(path):
        raise PlayError("PLAY_SERVICE_ACCOUNT_PATH saknas, eller pekar inte på tjänstkontots JSON-fil")
    return path


def authorized_session():
    # Laddas här, så att resten går att testa utan biblioteken.
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account

    try:
        credentials = service_account.Credentials.from_service_account_file(service_account_path(), scopes=[SCOPE])
    except ValueError:
        raise PlayError("Tjänstkontots JSON-fil går inte att läsa. Kontrollera secreten PLAY_SERVICE_ACCOUNT_JSON.") from None
    return AuthorizedSession(credentials)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["upload"])
    parser.add_argument("--aab", required=True, help="Den signerade bundlen")
    parser.add_argument("--track", default="internal", help="Spåret, till exempel internal")
    parser.add_argument("--notes-file", required=True, help="Versionens avsnitt ur changelogen, i Markdown")
    parser.add_argument("--package", required=True, help="Paketnamnet, se.hardyson.sophamtning")
    parser.add_argument("--status", choices=["completed", "draft"], default="completed",
                        help="completed släpps direkt i spåret, draft blir ett utkast som släpps i Play Console")
    args = parser.parse_args()

    with open(args.notes_file, encoding="utf-8") as f:
        notes = play_notes(f.read())
    print("Vad är nytt:\n" + (notes or "(ingen text)"))
    from google.auth.exceptions import GoogleAuthError

    try:
        upload(authorized_session(), args.package, args.aab, args.track, notes, args.status)
    except PlayError as error:
        raise SystemExit(f"Uppladdningen till Google Play misslyckades: {error}") from None
    except GoogleAuthError as error:
        # Googles svar när tjänstkontot inte godtas. Nyckeln själv finns inte i meddelandet.
        raise SystemExit(f"Tjänstkontot godtogs inte av Google: {type(error).__name__}: {error}") from None


if __name__ == "__main__":
    sys.exit(main())
