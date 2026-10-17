import configparser
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'installer/utils/configure_hazkey.py'
spec = importlib.util.spec_from_file_location('configure_hazkey', MODULE)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

DETECTOR = Path(__file__).resolve().parents[1] / 'installer/utils/detect_vulkan_backend.py'
detector_spec = importlib.util.spec_from_file_location('detect_vulkan_backend', DETECTOR)
detector = importlib.util.module_from_spec(detector_spec)
detector_spec.loader.exec_module(detector)


def parse(text: str) -> configparser.ConfigParser:
    """profile の解析結果"""
    config = setup._FcitxConfig()
    config.read_string(text)
    return config


def item_names(profile: configparser.ConfigParser) -> list[str]:
    """profile に登録された項目名（セクション順）"""
    return [profile[s]['Name'] for s in profile.sections() if '/Items/' in s]


def write_profile(config_home: Path, text: str) -> Path:
    """テスト用 profile の作成"""
    path = config_home / 'fcitx5/profile'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def run_cli(config_home: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    """隔離した XDG_CONFIG_HOME での configure_hazkey.py 実行（実環境の設定は不変）"""
    return subprocess.run(
        ['/usr/bin/python3', str(MODULE), '--zenzai-backend', 'CPU', *args],
        env={'XDG_CONFIG_HOME': str(config_home), 'PATH': '/usr/bin:/bin'},
        capture_output=True,
        text=True,
        check=check,
    )


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
        self.assertEqual(
            item_names(profile), ['keyboard-jp', 'keyboard-us-altgr-intl', 'hazkey', 'mozc']
        )
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

    def test_layout_option_creates_profile_without_detection(self):
        def detect():
            raise AssertionError('auto detection must not run when --layout is given')

        profile = parse(setup.fcitx_profile(None, detect, layout='us'))
        self.assertEqual(profile['Groups/0']['Default Layout'], 'us')
        self.assertEqual(item_names(profile), ['keyboard-us', 'hazkey', 'mozc'])

    def test_layout_option_switches_existing_default_keyboard(self):
        # システム既定が JIS の PC で /etc/default/keyboard から生成された profile
        initial = '''[Groups/0]
Name=Default
Default Layout=jp
DefaultIM=keyboard-jp
[Groups/0/Items/0]
Name=keyboard-jp
Layout=
[Groups/0/Items/1]
Name=hazkey
Layout=
[Groups/0/Items/2]
Name=mozc
Layout=jp
[GroupOrder]
0=Default
'''
        text = setup.fcitx_profile(initial, layout='us')
        profile = parse(text)
        self.assertEqual(profile['Groups/0']['Default Layout'], 'us')
        self.assertEqual(profile['Groups/0']['DefaultIM'], 'keyboard-us')
        self.assertEqual(item_names(profile), ['keyboard-us', 'hazkey', 'mozc'])
        self.assertEqual(profile['Groups/0/Items/2']['Layout'], 'jp')
        self.assertEqual(setup.fcitx_profile(text, layout='us'), text)
        self.assertEqual(setup.fcitx_profile(text), text)

    def test_layout_option_keeps_other_listed_keyboards(self):
        initial = '''[Groups/0]
Name=Default
Default Layout=jp
DefaultIM=hazkey
[Groups/0/Items/0]
Name=keyboard-jp
Layout=
[Groups/0/Items/1]
Name=keyboard-us
Layout=
[GroupOrder]
0=Default
'''
        profile = parse(setup.fcitx_profile(initial, layout='us'))
        self.assertEqual(profile['Groups/0']['Default Layout'], 'us')
        self.assertEqual(item_names(profile), ['keyboard-jp', 'keyboard-us', 'hazkey', 'mozc'])

    def test_layout_names_are_checked_against_xkb_rules(self):
        with tempfile.TemporaryDirectory() as temp:
            rules = Path(temp) / 'evdev.lst'
            rules.write_text(
                '! model\n  pc105  Generic\n! layout\n  us   English (US)\n'
                '  jp   Japanese\n! variant\n  alt-intl   us: English (US, alt. intl.)\n'
                '  dvorak   us: English (Dvorak)\n! option\n  ctrl:nocaps  Caps\n'
            )
            self.assertEqual(setup.xkb_layout('us', rules), 'us')
            self.assertEqual(setup.xkb_layout('us+dvorak', rules), 'us-dvorak')
            self.assertEqual(setup.xkb_layout('us-alt-intl', rules), 'us-alt-intl')
            for name in ('', 'US', 'en', 'jp+dvorak', 'us-nonexistent', 'us dvorak', 'pc105'):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    setup.xkb_layout(name, rules)

    def test_cli_layout_option_validates_before_writing(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            original = (
                '[Groups/0]\nName=Default\nDefault Layout=jp\nDefaultIM=hazkey\n'
                '[Groups/0/Items/0]\nName=keyboard-jp\nLayout=\n'
            )
            profile = write_profile(root, original)
            # ホストの XKB ルール一覧の有無によらず不正な形式
            self.assertNotEqual(run_cli(root, '--layout', 'US', check=False).returncode, 0)
            self.assertEqual(profile.read_text(), original)
            self.assertFalse((root / 'hazkey/config.json').exists())
            run_cli(root, '--layout', 'us')
            self.assertEqual(parse(profile.read_text())['Groups/0']['Default Layout'], 'us')

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

    def test_input_history_is_kept_unless_disabled(self):
        self.assertTrue(json.loads(setup.hazkey_config(None))[0]['useInputHistory'])
        original = [
            {'profileName': 'Off', 'useInputHistory': False},
            {'profileName': 'On', 'useInputHistory': True},
        ]
        profiles = json.loads(setup.hazkey_config(json.dumps(original)))
        self.assertEqual([p['useInputHistory'] for p in profiles], [False, True])

    def test_input_history_can_be_disabled_for_every_profile(self):
        original = [
            {'profileName': 'Snake', 'use_input_history': True, 'numSuggestions': 7},
            {'profileName': 'Camel', 'useInputHistory': True, 'stopStoreNewHistory': True},
        ]
        text = setup.hazkey_config(json.dumps(original), disable_input_history=True)
        snake, camel = json.loads(text)
        self.assertIs(snake['useInputHistory'], False)
        self.assertNotIn('use_input_history', snake)
        self.assertEqual(snake['numSuggestions'], 7)
        self.assertIs(camel['useInputHistory'], False)
        self.assertTrue(camel['stopStoreNewHistory'])
        self.assertEqual(setup.hazkey_config(text, disable_input_history=True), text)
        fresh = json.loads(setup.hazkey_config(None, disable_input_history=True))[0]
        self.assertIs(fresh['useInputHistory'], False)

    def test_cli_option_disables_input_history_only_when_applied(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            write_profile(
                root, '[Groups/0]\nName=Default\nDefault Layout=jp\nDefaultIM=keyboard-jp\n'
            )
            config = root / 'hazkey/config.json'
            run_cli(root, '--no-input-history', '--check')
            self.assertFalse(config.exists())
            run_cli(root, '--no-input-history')
            self.assertIs(json.loads(config.read_text())[0]['useInputHistory'], False)

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
