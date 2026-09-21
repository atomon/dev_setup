import configparser
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'installer/utils/configure_hazkey.py'
spec = importlib.util.spec_from_file_location('configure_hazkey', MODULE)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

DETECTOR = Path(__file__).resolve().parents[1] / 'installer/utils/detect_vulkan_backend.py'
detector_spec = importlib.util.spec_from_file_location('detect_vulkan_backend', DETECTOR)
detector = importlib.util.module_from_spec(detector_spec)
detector_spec.loader.exec_module(detector)


def parse(text):
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    config.read_string(text)
    return config


class ConfigTests(unittest.TestCase):
    def test_discrete_gpu_is_preferred_and_cpu_is_excluded(self):
        summary = '''GPU0:
    deviceType = PHYSICAL_DEVICE_TYPE_CPU
GPU1:
    deviceType = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
GPU2:
    deviceType = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
'''
        self.assertEqual(detector.select_gpu_index(summary), 2)

    def test_no_hardware_vulkan_device_returns_none(self):
        summary = '''GPU0:
    deviceType = PHYSICAL_DEVICE_TYPE_CPU
'''
        self.assertIsNone(detector.select_gpu_index(summary))

    def test_new_profile_retains_jis_and_us_variant(self):
        text = setup.fcitx_profile(None, lambda: ['jp', 'us-altgr-intl'])
        profile = parse(text)
        self.assertEqual(profile['Groups/0']['Default Layout'], 'jp')
        self.assertEqual(profile['Groups/0']['DefaultIM'], 'hazkey')
        self.assertEqual([profile[s]['Name'] for s in profile.sections() if '/Items/' in s],
                         ['keyboard-jp', 'keyboard-us-altgr-intl', 'hazkey', 'mozc'])
        self.assertEqual(setup.fcitx_profile(text), text)

    def test_existing_group_preserves_layout_order_and_default(self):
        initial = '''[Groups/0]
Name=Work
Default Layout=de
DefaultIM=mozc
[Groups/0/Items/0]
Name=keyboard-de
Layout=
[Groups/0/Items/1]
Name=mozc
Layout=jp
[GroupOrder]
0=Work
'''
        text = setup.fcitx_profile(initial)
        profile = parse(text)
        self.assertEqual(profile['Groups/0']['DefaultIM'], 'mozc')
        self.assertEqual(profile['Groups/0']['Default Layout'], 'de')
        self.assertEqual(profile['Groups/0/Items/1']['Layout'], 'jp')
        self.assertEqual(profile['Groups/0/Items/2']['Name'], 'hazkey')
        self.assertEqual(setup.fcitx_profile(text), text)

    def test_zenzai_enabled_without_losing_custom_settings(self):
        original = [{'profileName': 'Work', 'numSuggestions': 7,
                     'zenzai_enable': False, 'zenzaiBackendDeviceName': 'Vulkan0',
                     'zenzaiInferLimit': 5, 'enabledTables': [{'name': 'Custom'}]}]
        text = setup.hazkey_config(json.dumps(original))
        profile = json.loads(text)[0]
        self.assertTrue(profile['zenzaiEnable'])
        self.assertEqual(profile['zenzaiBackendDeviceName'], 'CPU')
        self.assertEqual(profile['numSuggestions'], 7)
        self.assertEqual(profile['zenzaiInferLimit'], 5)
        self.assertEqual(profile['enabledTables'], original[0]['enabledTables'])
        self.assertNotIn('zenzai_enable', profile)
        self.assertEqual(setup.hazkey_config(text), text)

    def test_fresh_hazkey_config_has_input_table_and_prediction(self):
        profile = json.loads(setup.hazkey_config(None))[0]
        self.assertEqual(profile['enabledTables'][0]['filename'], 'Romaji')
        self.assertEqual(profile['suggestionListMode'], 3)
        self.assertTrue(profile['zenzaiEnable'])

    def test_gpu_backend_is_written_when_selected(self):
        profile = json.loads(setup.hazkey_config(None, 'Vulkan2'))[0]
        self.assertEqual(profile['zenzaiBackendDeviceName'], 'Vulkan2')

    def test_backup_and_repeat_do_not_rewrite_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / 'hazkey/config.json'
            path.parent.mkdir()
            original = '[{"profileName":"Mine", "zenzaiEnable":false}]'
            path.write_text(original)
            with patch.object(setup, 'keyboard_layouts', return_value=['jp']):
                setup.configure(root)
                backups = list(path.parent.glob('*.before-hazkey.*'))
                self.assertEqual(len(backups), 1)
                self.assertEqual(backups[0].read_text(), original)
                before = {p: p.stat().st_mtime_ns for p in root.rglob('*') if p.is_file()}
                setup.configure(root)
                self.assertEqual(before, {p: p.stat().st_mtime_ns for p in root.rglob('*') if p.is_file()})

    def test_malformed_existing_config_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / 'hazkey/config.json'
            path.parent.mkdir()
            path.write_text('not-json')
            with self.assertRaises(ValueError):
                setup.configure(root)
            self.assertEqual(path.read_text(), 'not-json')
            self.assertFalse((root / 'fcitx5/profile').exists())

    def test_malformed_fcitx_config_does_not_partially_update_hazkey(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'fcitx5').mkdir()
            (root / 'fcitx5/profile').write_text('[Groups/0]\nName=MissingLayout\n')
            with self.assertRaises(ValueError):
                setup.configure(root)
            self.assertFalse((root / 'hazkey/config.json').exists())


if __name__ == '__main__':
    unittest.main()
