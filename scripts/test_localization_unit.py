import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def catalog(language):
    data = (ROOT / "Sources/DictationCore/Resources" / (language + ".lproj") / "Localizable.strings").read_text()
    pairs = re.findall(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");', data)
    result = {json.loads(key): json.loads(value) for key, value in pairs}
    assert len(result) == len(pairs), "Duplicate localization key"
    return result


class LocalizationTests(unittest.TestCase):
    def test_both_languages_cover_all_keys_and_formats(self):
        en, ru = catalog("en"), catalog("ru")
        self.assertEqual(en.keys(), ru.keys())
        for key in en:
            self.assertTrue(en[key] and ru[key], key)
            self.assertEqual(en[key].count("%@"), ru[key].count("%@"), key)
        for source in (ROOT / "Sources").rglob("*.swift"):
            for key in re.findall(r'(?:text|key|format)\("([a-z]+\.[\w.]+)"', source.read_text()):
                if key.endswith("."):
                    continue
                self.assertIn(key, en, str(source))


if __name__ == "__main__":
    unittest.main()
