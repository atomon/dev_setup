"""Tests for Ubuntu GNOME settings without changing the desktop or system files."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'installer/ubuntu_setting.sh'


class UbuntuSettingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        (self.home / '.bashrc').write_text('HISTSIZE=1000\nHISTFILESIZE=2000\n')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'commands.log'
        self.settings = self.root / 'custom-keybindings'
        self.screenshot_settings = self.root / 'show-screenshot-ui'
        self.xkb_settings = self.root / 'xkb-options'
        self.log.touch()
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            XDG_STATE_HOME=str(self.root / 'state'),
            XDG_CURRENT_DESKTOP='ubuntu:GNOME',
            DBUS_SESSION_BUS_ADDRESS='unix:path=/tmp/fake-dbus',
            PATH=f'{self.bin}:{os.environ["PATH"]}',
            TEST_LOG=str(self.log),
            TEST_SETTINGS=str(self.settings),
            TEST_SCREENSHOT_SETTINGS=str(self.screenshot_settings),
            TEST_XKB_SETTINGS=str(self.xkb_settings),
            TEST_BINDINGS="['/existing/']",
            TEST_SCREENSHOT_BINDINGS="['Print']",
        )
        mocks = {
            'apt-get': ':',
            'dconf': '''if [[ $1 == dump ]]; then printf '[custom]\\n';
elif [[ $1 == load ]]; then cat >/dev/null; fi''',
            'gsettings': '''if [[ $1 == writable ]]; then echo true; exit 0; fi
if [[ $1 == get && $2 == org.gnome.settings-daemon.plugins.media-keys && $3 == custom-keybindings ]]; then
  if [[ -f $TEST_SETTINGS ]]; then cat "$TEST_SETTINGS"; else echo "$TEST_BINDINGS"; fi
elif [[ $1 == get && $2 == org.gnome.desktop.input-sources && $3 == xkb-options ]]; then
  if [[ -f $TEST_XKB_SETTINGS ]]; then cat "$TEST_XKB_SETTINGS"; else echo '@as []'; fi
elif [[ $1 == get && $2 == org.gnome.shell.keybindings && $3 == show-screenshot-ui ]]; then
  if [[ -f $TEST_SCREENSHOT_SETTINGS ]]; then cat "$TEST_SCREENSHOT_SETTINGS"; else echo "$TEST_SCREENSHOT_BINDINGS"; fi
elif [[ $1 == set && $2 == org.gnome.settings-daemon.plugins.media-keys && $3 == custom-keybindings ]]; then
  printf '%s\\n' "$4" > "$TEST_SETTINGS"
elif [[ $1 == set && $2 == org.gnome.shell.keybindings && $3 == show-screenshot-ui ]]; then
  printf '%s\\n' "$4" > "$TEST_SCREENSHOT_SETTINGS"
elif [[ $1 == set && $2 == org.gnome.desktop.input-sources && $3 == xkb-options ]]; then
  printf '%s\\n' "$4" > "$TEST_XKB_SETTINGS"
fi''',
            'install': '/usr/bin/install "$@"',
            'sudo': '''case $1 in
  apt-get|timedatectl|install|rm) exit 0 ;;
  cp) if [[ ${!#} == /etc/* ]]; then exit 0; fi; "$@" ;;
  *) "$@" ;;
esac''',
            'timedatectl': '''if [[ $1 == show ]]; then echo false; fi''',
            'vivaldi': 'echo Vivaldi 1.0',
        }
        for name, body in mocks.items():
            path = self.bin / name
            path.write_text(f'#!/bin/bash\nprintf "%s\\n" "{name} $*" >> "$TEST_LOG"\n{body}\n')
            path.chmod(0o755)

    def execute(self, *args):
        return subprocess.run(['bash', str(SCRIPT), *args], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_applies_idempotent_personal_settings_and_preserves_shortcuts(self):
        first = self.execute()
        self.assertEqual(first.returncode, 0, first.stderr)
        bashrc = (self.home / '.bashrc').read_text()
        self.assertEqual(bashrc.count('# >>> dev_setup ubuntu_setting >>>'), 1)
        self.assertIn('HISTSIZE=20000', bashrc)
        self.assertIn("HISTTIMEFORMAT='%F %T '", bashrc)
        self.assertIn("alias reload='exec $SHELL -l'", (self.home / '.bash_aliases').read_text())
        self.assertTrue((self.home / 'Apps').is_dir())
        self.assertTrue((self.home / '.config/autostart/gnome-terminal.desktop').is_file())
        self.assertTrue((self.home / '.config/autostart/vivaldi.desktop').is_file())
        bindings = self.settings.read_text()
        self.assertIn('/existing/', bindings)
        self.assertIn('/dev-setup-suspend/', bindings)
        self.assertIn('/dev-setup-logout/', bindings)
        screenshot_bindings = self.screenshot_settings.read_text()
        self.assertIn('Print', screenshot_bindings)
        self.assertIn('<Super><Shift>s', screenshot_bindings)
        self.assertEqual(self.execute().returncode, 0)
        self.assertEqual((self.home / '.bashrc').read_text().count('# >>> dev_setup ubuntu_setting >>>'), 1)
        log = self.log.read_text()
        self.assertIn('gnome-session-quit --reboot', log)
        self.assertIn('<Super>s', log)
        self.assertNotIn('dconf-editor', log)
        self.assertNotIn('timedatectl set-local-rtc', log)

    def test_local_rtc_requires_explicit_option(self):
        result = self.execute('--local-rtc')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('timedatectl set-local-rtc true', self.log.read_text())

    def test_dry_run_does_not_create_or_change_user_files(self):
        original = (self.home / '.bashrc').read_text()
        result = self.execute('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / '.bashrc').read_text(), original)
        self.assertFalse((self.root / 'state').exists())
        self.assertFalse((self.home / '.config/autostart').exists())

    def test_applies_when_no_custom_shortcut_exists(self):
        self.env['TEST_BINDINGS'] = '@as []'
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('/dev-setup-suspend/', self.settings.read_text())

    def test_undo_restores_bash_configuration(self):
        self.assertEqual(self.execute().returncode, 0)
        result = self.execute('--undo')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / '.bashrc').read_text(), 'HISTSIZE=1000\nHISTFILESIZE=2000\n')
        self.assertFalse((self.home / '.bash_aliases').exists())
        self.assertIn('timedatectl set-local-rtc false', self.log.read_text())


if __name__ == '__main__':
    unittest.main()
