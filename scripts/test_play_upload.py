"""Tester för uppladdningen till Google Play. Kör: python3 -m unittest discover -s scripts"""

import os
import tempfile
import unittest
from unittest import mock

import play_upload
from play_upload import MAX_LENGTH, PlayError, play_notes, upload

RELEASE = """## [1.0.1](https://github.com/jesperhardyson/Sophamtning/compare/android-v1.0.0...android-v1.0.1) (2026-12-01)


### Rättat

* Widgeten visar rätt dag ([#95](https://github.com/jesperhardyson/Sophamtning/issues/95)) ([c131d82](https://github.com/jesperhardyson/Sophamtning/commit/c131d82))
* **widget:** Raden får plats ([#96](https://example.com/96))
"""


class Response:
    def __init__(self, status=200, body=None, headers=None):
        self.status_code = status
        self._body = body
        self.headers = headers or {}
        self.text = "" if body is None else str(body)

    def json(self):
        if self._body is None:
            raise ValueError("ingen JSON")
        return self._body


class FakeSession:
    """Ett fejkat Play Developer API, som sparar anropen."""

    def __init__(self, fail=None):
        self.calls = []
        self.fail = fail

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if self.fail and self.fail in url:
            return Response(403, {"error": {"code": 403, "message": "The caller does not have permission"}})
        if url.endswith("/edits"):
            return Response(200, {"id": "edit-1"})
        if "uploadType=resumable" in url:
            return Response(200, None, {"Location": "https://upload.example/session-1"})
        if url == "https://upload.example/session-1":
            return Response(200, {"versionCode": 4201, "sha1": "x"})
        if "/tracks/" in url:
            return Response(200, kwargs.get("json"))
        if url.endswith(":commit"):
            return Response(200, {"id": "edit-1"})
        return Response(404, {"error": {"message": "okänt anrop " + url}})


class PlayNotesTests(unittest.TestCase):
    def test_vad_ar_nytt_ar_ren_text_utan_lankar(self):
        self.assertEqual(
            play_notes(RELEASE),
            "Rättat\n\n• Widgeten visar rätt dag\n• widget: Raden får plats",
        )

    def test_testbyggets_text_blir_oforandrad_ren_text(self):
        notes = "Testbygge från main (abc1234)\n\n* ci: något ändrat\n* fix: Widgeten"
        self.assertEqual(
            play_notes(notes),
            "Testbygge från main (abc1234)\n\n• ci: något ändrat\n• fix: Widgeten",
        )

    def test_vad_ar_nytt_kortas_vid_hel_rad_till_500_tecken(self):
        rows = [f"* Rad {i:02d} med en ändring som tar lite plats" for i in range(30)]
        text = play_notes("### Nytt\n\n" + "\n".join(rows))
        self.assertLessEqual(len(text), MAX_LENGTH)
        self.assertTrue(text.endswith("\n…"))
        # Varje rad före "…" är hel.
        for line in text.splitlines()[2:-1]:
            self.assertRegex(line, r"^• Rad \d\d med en ändring som tar lite plats$")

    def test_kort_text_kortas_inte(self):
        self.assertFalse(play_notes("### Nytt\n\n* En rad").endswith("…"))

    def test_en_enda_for_lang_rad_kortas_vid_tecken(self):
        text = play_notes("* " + "a" * 800)
        self.assertEqual(len(text), MAX_LENGTH)
        self.assertTrue(text.endswith("…"))


class UploadTests(unittest.TestCase):
    def setUp(self):
        handle, self.aab = tempfile.mkstemp(suffix=".aab")
        os.write(handle, b"AAB")
        os.close(handle)

    def tearDown(self):
        os.remove(self.aab)

    def test_uppladdningen_gor_edit_bundle_track_och_commit(self):
        session = FakeSession()
        version_code = upload(session, "se.hardyson.sophamtning", self.aab, "internal", "Nytt\n\n• En rad")
        self.assertEqual(version_code, 4201)
        base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/se.hardyson.sophamtning"
        upload_base = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/se.hardyson.sophamtning"
        self.assertEqual(
            [(method, url) for method, url, _ in session.calls],
            [
                ("POST", base + "/edits"),
                ("POST", upload_base + "/edits/edit-1/bundles?uploadType=resumable"),
                ("PUT", "https://upload.example/session-1"),
                ("PUT", base + "/edits/edit-1/tracks/internal"),
                ("POST", base + "/edits/edit-1:commit"),
            ],
        )
        start = session.calls[1][2]
        self.assertEqual(start["headers"]["X-Upload-Content-Type"], "application/octet-stream")
        self.assertEqual(start["headers"]["X-Upload-Content-Length"], "3")
        sent = session.calls[2][2]
        self.assertEqual(sent["headers"]["Content-Type"], "application/octet-stream")
        self.assertEqual(sent["data"], b"AAB")
        self.assertEqual(session.calls[3][2]["json"], {
            "track": "internal",
            "releases": [{
                "versionCodes": ["4201"],
                "status": "completed",
                "releaseNotes": [{"language": "sv-SE", "text": "Nytt\n\n• En rad"}],
            }],
        })

    def test_fel_fran_apiet_stoppar_med_tydligt_meddelande(self):
        session = FakeSession(fail="/tracks/")
        with self.assertRaises(PlayError) as caught:
            upload(session, "se.hardyson.sophamtning", self.aab, "internal", "Text")
        message = str(caught.exception)
        self.assertIn("PUT", message)
        self.assertIn("/edits/edit-1/tracks/internal", message)
        self.assertIn("HTTP 403", message)
        self.assertIn("The caller does not have permission", message)
        # Editen görs aldrig färdig när ett steg fallerar.
        self.assertFalse(any(url.endswith(":commit") for _, url, _ in session.calls))

    def test_fel_om_utkast_till_app_ger_en_ledtrad(self):
        class DraftSession(FakeSession):
            def request(self, method, url, **kwargs):
                if "/tracks/" in url:
                    self.calls.append((method, url, kwargs))
                    return Response(400, {"error": {"message": "Only releases with status draft may be created on draft app."}})
                return super().request(method, url, **kwargs)

        with self.assertRaises(PlayError) as caught:
            upload(DraftSession(), "se.hardyson.sophamtning", self.aab, "internal", "Text")
        self.assertIn("docs/android-google-play.md", str(caught.exception))

    def test_tjanstkontot_saknas_stoppar_tydligt(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(PlayError) as caught:
                play_upload.service_account_path()
        self.assertIn("PLAY_SERVICE_ACCOUNT_PATH", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
