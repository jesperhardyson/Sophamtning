"""Tester för texten till TestFlight och App Store. Kör: python3 -m unittest discover -s scripts"""

import unittest

from release_notes import MAX_LENGTH, plain_notes

RELEASE = """## [1.0.1](https://github.com/jesperhardyson/Sophamtning/compare/v1.0.0...v1.0.1) (2026-11-08)


### Rättat

* Källistan hämtas direkt efter en appuppdatering ([#30](https://github.com/jesperhardyson/Sophamtning/issues/30)) ([c131d82](https://github.com/jesperhardyson/Sophamtning/commit/c131d82))
* **widget:** Raden får plats ([#32](https://example.com/32)) ([abc1234](https://example.com/c))

### Nytt

* Sökfält bland områden ([#33](https://example.com/33))
"""


class PlainNotesTests(unittest.TestCase):
    def test_tar_bort_versionsrubrik_lankar_och_referenser(self):
        self.assertEqual(
            plain_notes(RELEASE),
            "Rättat\n\n"
            "• Källistan hämtas direkt efter en appuppdatering\n"
            "• widget: Raden får plats\n\n"
            "Nytt\n\n"
            "• Sökfält bland områden",
        )

    def test_tom_text_blir_tom(self):
        self.assertEqual(plain_notes("## [1.0.2](x) (2026-11-09)\n\n"), "")

    def test_lang_text_kortas_till_apples_grans(self):
        text = plain_notes("### Nytt\n\n" + "\n".join(f"* Rad {i} med lite text" for i in range(400)))
        self.assertLessEqual(len(text), MAX_LENGTH)
        self.assertTrue(text.endswith("…"))


if __name__ == "__main__":
    unittest.main()
