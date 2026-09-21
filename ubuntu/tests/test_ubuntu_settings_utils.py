"""Unit tests for the data transformations used by ubuntu_setting.sh."""
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = spec_from_file_location("ubuntu_settings", ROOT / "installer/utils/ubuntu_settings.py")
assert SPEC and SPEC.loader
ubuntu_settings = module_from_spec(SPEC)
SPEC.loader.exec_module(ubuntu_settings)


class UbuntuSettingsUtilityTests(unittest.TestCase):
    def test_gvariant_append_preserves_existing_entries_and_is_idempotent(self):
        original = "@as ['/existing/', '/dev-setup-suspend/']"
        added = ubuntu_settings.append_gvariant_string(original, "/dev-setup-logout/")
        self.assertEqual(
            added,
            "['/existing/', '/dev-setup-suspend/', '/dev-setup-logout/']",
        )
        self.assertEqual(
            ubuntu_settings.append_gvariant_string(added, "/dev-setup-logout/"), added
        )
        self.assertEqual(ubuntu_settings.gvariant_string_list("@as []"), [])

    def test_upsert_managed_block_replaces_only_marked_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".bashrc"
            path.write_text("export PATH\n# >>> managed >>>\nold\n# <<< managed <<<\n")
            ubuntu_settings.upsert_managed_block(path, "# >>> managed >>>", "# <<< managed <<<", "new")
            self.assertEqual(
                path.read_text(), "export PATH\n\n# >>> managed >>>\nnew\n# <<< managed <<<\n"
            )

    def test_merge_xkb_option_keeps_existing_options_without_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "keyboard"
            target = Path(directory) / "updated-keyboard"
            source.write_text('XKBLAYOUT="us"\nXKBOPTIONS="compose:menu,ctrl:nocaps"\n')
            ubuntu_settings.merge_xkb_option(source, target, "ctrl:nocaps")
            self.assertEqual(
                target.read_text(), 'XKBLAYOUT="us"\nXKBOPTIONS="compose:menu,ctrl:nocaps"\n'
            )


if __name__ == "__main__":
    unittest.main()
