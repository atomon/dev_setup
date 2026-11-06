"""No network, package installation, or desktop setting changes."""
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / 'bin'
        self.bin.mkdir()
        self.log = self.work / 'commands.log'
        self.log.touch()
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        XDG_CACHE_HOME=str(self.work / 'cache'),
                        XDG_DATA_HOME=str(self.work / 'data'),
                        TEST_LOG=str(self.log), TEST_ARCH='arm64',
                        TEST_SWIFT='6.2', TEST_CMAKE='4.1.0', TEST_TARGET='aarch64')
        mocks = {
            'dpkg': 'if [[ $1 == --print-architecture ]]; then echo "$TEST_ARCH"; else /usr/bin/dpkg "$@"; fi',
            'dpkg-query': 'exit 1',
            'swift': 'printf "Swift version %s\\nTarget: %s-unknown-linux-gnu\\n" "$TEST_SWIFT" "$TEST_TARGET"',
            'cmake': 'if [[ $1 == --version ]]; then echo "cmake version $TEST_CMAKE"; elif [[ $1 == --build && ${TEST_FAIL_BUILD:-} == yes ]]; then exit 42; fi',
            'sudo': 'if [[ ${TEST_FAIL_APT:-} == yes ]]; then exit 43; fi',
            'git': 'if [[ $* == *rev-parse* ]]; then echo "${TEST_COMMIT:-596108c126449abcce2716a3e20d80106fb83890}"; fi',
            'curl': 'while (( $# )); do if [[ $1 == -o ]]; then touch "$2"; break; fi; shift; done',
            'gpg': 'if [[ $* == *--verify* && ${TEST_BAD_SIGNATURE:-} == yes ]]; then exit 44; fi',
            'tar': '''while (( $# )); do if [[ $1 == -C ]]; then dest=$2; break; fi; shift; done
mkdir -p "$dest/bin" "$dest/usr/bin"
printf '#!/bin/bash\\necho "Swift version 6.2"\\necho "Target: aarch64-unknown-linux-gnu"\\n' > "$dest/usr/bin/swift"
printf '#!/bin/bash\\necho "cmake version 4.1.3"\\n' > "$dest/bin/cmake"
chmod +x "$dest/usr/bin/swift" "$dest/bin/cmake"''',
            'sha256sum': 'cat >/dev/null; [[ ${TEST_BAD_HASH:-} != yes ]]',
            'vulkaninfo': '''if [[ ${TEST_VULKAN_GPU:-} == yes ]]; then
printf 'GPU0:\n    deviceType = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU\n'
else
printf 'GPU0:\n    deviceType = PHYSICAL_DEVICE_TYPE_CPU\n'
fi''',
        }
        for name, body in mocks.items():
            p = self.bin / name
            p.write_text(f'#!/bin/bash\nprintf "%s\\n" "{name} $*" >> "$TEST_LOG"\n{body}\n')
            p.chmod(0o755)

    def hazkey(self, **changes):
        # Replace only the session boundary; installation control flow stays real.
        command = '''source "$1"
        ime_require_session() { :; }
        hazkey_configure_user() { echo configured >> "$TEST_LOG"; }
        ime_select_fcitx5() { echo activated >> "$TEST_LOG"; }
        ime_configure_environment() { echo environment >> "$TEST_LOG"; }
        ime_configure_login_environment() { echo login-environment >> "$TEST_LOG"; }
        hazkey_configure_autostart() { echo autostart >> "$TEST_LOG"; }
hazkey_main
'''
        return subprocess.run(['bash', '-c', command, 'test', str(ROOT / 'installer/hazkey.sh')],
                              env=self.env | changes, capture_output=True, text=True)

    def test_arm_builds_zenzai_and_keeps_mozc(self):
        result = self.hazkey()
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        self.assertIn('-DGGML_CPU_ARM_ARCH=armv8-a', log)
        self.assertIn('-DHAZKEY_SERVER_ENABLE_ZENZAI=ON', log)
        self.assertIn('fcitx5-mozc', log)
        self.assertIn('--install', log)
        self.assertFalse(any(line.startswith('curl ') for line in log.splitlines()))
        self.assertIn('activated', log)
        self.assertIn('environment', log)
        self.assertIn('login-environment', log)
        self.assertIn('autostart', log)

    def test_hazkey_registers_autostart(self):
        result = self.hazkey()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('autostart', self.log.read_text())

    def test_backend_is_detected_once_and_shared_by_install_and_configuration(self):
        command = '''source "$1"
        ime_require_session() { :; }
        ime_update_packages() { :; }
        ime_install_packages() { :; }
        hazkey_select_zenzai_backend() { echo detect >> "$TEST_LOG"; printf '%s\\n' Vulkan0; }
        hazkey_install() { printf 'install %s %s\\n' "$@" >> "$TEST_LOG"; }
        hazkey_configure_user() { printf 'configure %s\\n' "$1" >> "$TEST_LOG"; }
        hazkey_configure_input_method() { :; }
        hazkey_print_next_steps() { :; }
        hazkey_main
'''
        result = subprocess.run(['bash', '-c', command, 'test', str(ROOT / 'installer/hazkey.sh')],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(),
                         ['dpkg --print-architecture', 'detect', 'install arm64 Vulkan0',
                          'configure Vulkan0'])

    def test_autostart_entry_is_installed_for_xdg_config_home(self):
        config_home = self.work / 'config'
        result = subprocess.run(
            ['bash', '-c', 'source "$1"; hazkey_configure_autostart', 'test',
             str(ROOT / 'installer/hazkey.sh')],
            env=self.env | {'HOME': str(self.work / 'home'),
                            'XDG_CONFIG_HOME': str(config_home)},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        entry = config_home / 'autostart/fcitx5.desktop'
        self.assertEqual(entry.read_text(), (ROOT / 'installer/DB/fcitx5.desktop').read_text())

    def test_environment_is_installed_for_xdg_config_home(self):
        config_home = self.work / 'config'
        result = subprocess.run(
            ['bash', '-c', 'source "$1"; ime_configure_environment', 'test',
             str(ROOT / 'installer/hazkey.sh')],
            env=self.env | {'HOME': str(self.work / 'home'),
                            'XDG_CONFIG_HOME': str(config_home)},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        environment = config_home / 'environment.d/90-fcitx5.conf'
        self.assertEqual(environment.read_text(),
                         (ROOT / 'installer/DB/fcitx5-environment.conf').read_text())

    def test_environment_is_backed_up_before_replacement(self):
        config_home = self.work / 'config'
        environment = config_home / 'environment.d/90-fcitx5.conf'
        environment.parent.mkdir(parents=True)
        original = 'QT_IM_MODULE=ibus\n'
        environment.write_text(original)
        result = subprocess.run(
            ['bash', '-c', 'source "$1"; ime_configure_environment', 'test',
             str(ROOT / 'installer/hazkey.sh')],
            env=self.env | {'HOME': str(self.work / 'home'),
                            'XDG_CONFIG_HOME': str(config_home)},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list(environment.parent.glob('90-fcitx5.conf.before-hazkey.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)

    def test_login_environment_is_installed(self):
        result = subprocess.run(
            ['bash', '-c', 'source "$1"; ime_configure_login_environment', 'test',
             str(ROOT / 'installer/hazkey.sh')],
            env=self.env | {'HOME': str(self.work / 'home')},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        pam_environment = self.work / 'home/.pam_environment'
        self.assertEqual(pam_environment.read_text(),
                         (ROOT / 'installer/DB/fcitx5-pam_environment').read_text())

    def test_login_environment_is_backed_up_before_replacement(self):
        home = self.work / 'home'
        home.mkdir()
        pam_environment = home / '.pam_environment'
        original = 'QT_IM_MODULE OVERRIDE=ibus\n'
        pam_environment.write_text(original)
        result = subprocess.run(
            ['bash', '-c', 'source "$1"; ime_configure_login_environment', 'test',
             str(ROOT / 'installer/hazkey.sh')],
            env=self.env | {'HOME': str(home)},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list(home.glob('.pam_environment.before-hazkey.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)

    def test_arm_build_enables_vulkan_for_a_detected_gpu(self):
        result = self.hazkey(TEST_VULKAN_GPU='yes')
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        self.assertIn('-DGGML_VULKAN=ON', log)
        self.assertIn('libvulkan-dev glslc', log)

    def test_amd64_downloads_and_cleans_temporary_file(self):
        result = self.hazkey(TEST_ARCH='amd64')
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        download = next(line for line in log.splitlines() if line.startswith('curl '))
        path = Path(download.split(' -o ', 1)[1])
        self.assertFalse(path.parent.exists())
        self.assertIn('_amd64.deb', log)
        self.assertIn('sha256sum --check', log)
        self.assertNotIn('git clone', log)
        self.assertIn('activated', log)

    def test_preflight_rejects_unsupported_platform(self):
        result = self.hazkey(TEST_ARCH='riscv64')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('sudo ', self.log.read_text())

    def test_missing_versions_are_installed_automatically(self):
        result = self.hazkey(TEST_SWIFT='6.1', TEST_CMAKE='3.28', TEST_TARGET='x86_64')
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        self.assertIn('swift-6.2-RELEASE', log)
        self.assertIn('cmake-4.1.3-linux-aarch64.tar.gz', log)
        self.assertIn('gpg --homedir', log)
        self.assertIn('--verify', log)
        self.assertIn('configured', log)
        self.assertIn('activated', log)
        self.log.write_text('')
        result = self.hazkey(TEST_SWIFT='6.1', TEST_CMAKE='3.28', TEST_TARGET='x86_64')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(line.startswith('curl ') for line in self.log.read_text().splitlines()))

    def test_bad_cmake_checksum_prevents_extraction(self):
        result = self.hazkey(TEST_CMAKE='3.28', TEST_BAD_HASH='yes')
        self.assertNotEqual(result.returncode, 0)
        log = self.log.read_text()
        self.assertNotIn('tar -xzf', log)
        self.assertNotIn('activated', log)

    def test_bad_swift_signature_prevents_extraction(self):
        result = self.hazkey(TEST_SWIFT='6.1', TEST_BAD_SIGNATURE='yes')
        self.assertEqual(result.returncode, 44, result.stderr)
        log = self.log.read_text()
        self.assertNotIn('tar -xzf', log)
        self.assertNotIn('activated', log)

    def test_failures_never_activate_input_method(self):
        for changes in ({'TEST_FAIL_APT': 'yes'}, {'TEST_FAIL_BUILD': 'yes'},
                        {'TEST_COMMIT': 'wrong'},
                        {'TEST_ARCH': 'amd64', 'TEST_BAD_HASH': 'yes'}):
            with self.subTest(**changes):
                self.log.write_text('')
                result = self.hazkey(**changes)
                self.assertNotEqual(result.returncode, 0)
                log = self.log.read_text()
                self.assertNotIn('activated', log)
                self.assertNotIn('--install', log)
                self.assertNotIn('fcitx5-mozc', log)

    def test_bad_model_download_preserves_existing_model(self):
        target = self.work / 'data/hazkey/zenzai/zenzai.gguf'
        target.parent.mkdir(parents=True)
        target.write_bytes(b'existing-custom-model')
        result = subprocess.run(
            ['bash', '-c', 'source "$1"; hazkey_install_model', 'test',
             str(ROOT / 'installer/hazkey.sh')],
            env=self.env | {'TEST_BAD_HASH': 'yes'}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_bytes(), b'existing-custom-model')
        self.assertEqual(list(target.parent.iterdir()), [target])

    def test_existing_valid_model_is_not_downloaded_again(self):
        target = self.work / 'data/hazkey/zenzai/zenzai.gguf'
        target.parent.mkdir(parents=True)
        target.touch()
        result = subprocess.run(
            ['bash', '-c', 'source "$1"; hazkey_install_model', 'test',
             str(ROOT / 'installer/hazkey.sh')], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(line.startswith('curl ') for line in self.log.read_text().splitlines()))

    def launcher(self, *args, path=None):
        return subprocess.run(['bash', str(path or ROOT / 'install.sh'), *args],
                              cwd=self.work, input='', capture_output=True, text=True)

    def test_selection_is_ordered_deduplicated_and_independent_of_cwd(self):
        result = self.launcher('--dry', '-i', 'hazkey', 'mozc', 'hazkey')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([line.split()[0] for line in result.stdout.splitlines()], ['mozc', 'hazkey'])
        result = self.launcher('--dry', '-i', 'ghostty')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ghostty  -->  ./installer/ghostty.sh', result.stdout)
        result = self.launcher('--dry', '-i', 'tmux_agent_sidebar')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('tmux_agent_sidebar  -->  ./installer/tmux_agent_sidebar.sh', result.stdout)
        result = self.launcher('--dry', '-i', 'byobu', 'tmux_agent_sidebar')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([line.split()[0] for line in result.stdout.splitlines()],
                         ['byobu', 'tmux_agent_sidebar'])
        result = self.launcher('--all', '--dry')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('hazkey', result.stdout)
        self.assertNotIn('byobu  -->', result.stdout)
        self.assertNotIn('tmux_agent_sidebar', result.stdout)
        self.assertIn('ghostty', result.stdout)
        self.assertIn('installer/python.sh', result.stdout)
        self.assertNotIn('utils/python/', result.stdout)
        result = self.launcher('--dry', '-i', 'astronvim')
        self.assertEqual([line.split()[0] for line in result.stdout.splitlines()],
                         ['python', 'nodejs', 'astronvim'])

    def test_invalid_arguments_fail(self):
        for args in ((), ('-i',), ('-i', '--dry'), ('-i', 'unknown'), ('--unknown',)):
            with self.subTest(args=args):
                self.assertNotEqual(self.launcher(*args).returncode, 0)

    def test_launcher_reports_child_failure(self):
        shutil.copyfile(ROOT / 'install.sh', self.work / 'install.sh')
        (self.work / 'installer').mkdir()
        child = self.work / 'installer/hazkey.sh'
        child.write_text('exit 42\n')
        result = self.launcher('-i', 'hazkey', path=self.work / 'install.sh')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Installation failed: hazkey', result.stderr)
        child.write_text('echo child-output\nexit 0\n')
        result = self.launcher('-q', '-i', 'hazkey', path=self.work / 'install.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('child-output', result.stdout)
        self.assertIn('Installed: hazkey', result.stdout)

    def test_astronvim_is_skipped_when_runtime_dependency_fails(self):
        shutil.copyfile(ROOT / 'install.sh', self.work / 'install.sh')
        installer_dir = self.work / 'installer'
        installer_dir.mkdir()
        (installer_dir / 'python.sh').write_text('exit 42\n')
        (installer_dir / 'nodejs.sh').write_text('exit 0\n')
        (installer_dir / 'astronvim.sh').write_text('echo invoked > "$TEST_MARKER"\n')
        marker = self.work / 'astronvim-invoked'
        result = subprocess.run(
            ['bash', str(self.work / 'install.sh'), '-i', 'astronvim'],
            cwd=self.work, env=os.environ | {'TEST_MARKER': str(marker)},
            input='', capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(marker.exists())
        self.assertIn('Skipping astronvim', result.stderr)


class AstroNvimInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.log = self.work / 'commands.log'
        self.log.touch()
        self.installer = ROOT / 'installer/astronvim.sh'
        self.env = os.environ | {
            'HOME': str(self.work),
            'TEST_LOG': str(self.log),
            'XDG_SESSION_TYPE': 'wayland',
        }

    def run_function(self, body, **changes):
        command = f'''source "$1"
{body}
'''
        return subprocess.run(
            ['bash', '-c', command, 'test', str(self.installer)],
            env=self.env | changes, capture_output=True, text=True)

    def test_apt_installs_all_astronvim_feature_dependencies(self):
        result = self.run_function(r'''
sudo() { printf '%s\n' "$*" >> "$TEST_LOG"; }
install_apt_requirements
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        install = self.log.read_text().splitlines()[-1]
        self.assertIn('--no-install-recommends', install)
        for package in ('build-essential', 'ripgrep', 'tree-sitter-cli', 'gdu',
                        'btm', 'wl-clipboard', 'lazygit', 'openssh-client',
                        'xdg-utils'):
            self.assertIn(package, install)
        for package in ('python3', 'nodejs', 'node-gyp', 'npm'):
            self.assertNotIn(package, install)

    def test_requirement_verification_includes_default_feature_commands(self):
        result = self.run_function(r'''
command() {
  if [[ $1 == -v ]]; then
    printf '%s\n' "$2" >> "$TEST_LOG"
    return 0
  fi
  builtin command "$@"
}
verify_requirements
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.log.read_text().splitlines(),
            ['git', 'ssh', 'xdg-open', 'rg', 'cc', 'make', 'tree-sitter',
             'lazygit', 'gdu', 'btm', 'python', 'python3', 'node', 'npm',
             'wl-copy'])


class PythonInstallerTests(unittest.TestCase):
    def test_uv_installs_default_python_commands_for_astronvim(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            uv = root / 'uv'
            log = root / 'commands.log'
            uv.write_text('''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$TEST_LOG"
if [[ $1 == python && $2 == find ]]; then printf '/managed/python\\n'; fi
if [[ $1 == --version ]]; then printf 'uv 1.0\\n'; fi
''')
            uv.chmod(0o755)
            command = '''source "$1"
install_python "$2"
'''
            result = subprocess.run(
                ['bash', '-c', command, 'test',
                 str(ROOT / 'installer/python.sh'), str(uv)],
                env=os.environ | {'HOME': str(root), 'TEST_LOG': str(log)},
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text().splitlines()[0],
                             'python install --default 3.13')


class DockerInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.log = Path(self.temp.name) / 'commands.log'
        self.log.touch()
        self.env = dict(os.environ, TEST_LOG=str(self.log))

    def run_flow(self, docker_is_present):
        command = r'''
source "$1"
require_ubuntu() { :; }
docker_is_installed() { [[ $TEST_DOCKER_PRESENT == yes ]]; }
install_docker_engine() { echo install >> "$TEST_LOG"; }
start_docker_service() { echo service >> "$TEST_LOG"; }
verify_docker_installation() { echo verify-new >> "$TEST_LOG"; }
verify_existing_docker() { echo verify-existing >> "$TEST_LOG"; }
ensure_docker_group_membership() { echo group >> "$TEST_LOG"; }
setup_docker
ensure_docker_group_membership
'''
        return subprocess.run(
            ['bash', '-c', command, 'test', str(ROOT / 'installer/docker.sh')],
            env=self.env | {'TEST_DOCKER_PRESENT': 'yes' if docker_is_present else 'no'},
            capture_output=True, text=True)

    def test_fresh_install_runs_installation_and_verification(self):
        result = self.run_flow(docker_is_present=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ['install', 'service', 'verify-new', 'group'])

    def test_existing_docker_is_preserved(self):
        result = self.run_flow(docker_is_present=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ['verify-existing', 'group'])


class GhosttyInstallerTests(unittest.TestCase):
    def test_community_package_url_matches_only_the_requested_asset(self):
        release_json = '''
{"body":"https://github.com/mkasberg/ghostty-ubuntu/releases/download/no/ghostty_bad_amd64_24.04.deb",
 "browser_download_url":"https://github.com/mkasberg/ghostty-ubuntu/releases/download/1.3.1-0-ppa2/ghostty_1.3.1-0~ppa2_amd64_24.04.deb",
 "other":"https://github.com/mkasberg/ghostty-ubuntu/releases/download/1.3.1-0-ppa2/ghostty_1.3.1-0~ppa2_arm64_24.04.deb"}
'''
        command = '''source "$1"
curl() { printf '%s' "$TEST_RELEASE_JSON"; }
latest_deb_url amd64
'''
        result = subprocess.run(['bash', '-c', command, 'test',
                                 str(ROOT / 'installer/ghostty.sh')],
                                env=os.environ | {'TEST_RELEASE_JSON': release_json},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(),
                         'https://github.com/mkasberg/ghostty-ubuntu/releases/download/'
                         '1.3.1-0-ppa2/ghostty_1.3.1-0~ppa2_amd64_24.04.deb')


class ByobuInstallerTests(unittest.TestCase):
    """byobu installer・byobu-resume・復元 helper の検証"""

    INSTALLER = ROOT / 'installer/byobu.sh'
    RESTORE_HELPER = ROOT / 'installer/utils/byobu_restore_after_attach.sh'
    RESTORE_FAILURE = 'display-message -d 0 byobu-resume: restore did not finish'
    RESTORE_TMUX_CASES = '''  'show-environment -g DEV_SETUP_BYOBU_RESUME_SESSION') printf 'DEV_SETUP_BYOBU_RESUME_SESSION=1\\n' ;;
  'show-option -gqv @resurrect-dir') printf '%s\\n' "$TEST_RESURRECT" ;;
  'show-option -gqv @resurrect-restore-script-path') printf '%s\\n' "$TEST_RESTORE" ;;
  'list-sessions -F #{session_name}') printf '2\\n' ;;
  'has-session -t =1') exit 1 ;;
'''

    def restore_env(self, root: Path, last: str, tmux_cases: str = '') -> dict[str, str]:
        """復元 helper 用の保存データ・restore.sh・tmux モックの作成

        Args:
            root: 作業ディレクトリ
            last: tmux-resurrect の last ファイルの内容
            tmux_cases: 共通の応答に追加する tmux モックの case 節

        Returns:
            helper 実行用の環境変数
        """
        bin_dir = root / 'bin'
        resurrect = root / 'resurrect'
        for directory in (root / 'home', bin_dir, resurrect):
            directory.mkdir()
        (resurrect / 'last').write_text(last)
        restore = root / 'restore.sh'
        restore.write_text('#!/usr/bin/env bash\ntouch "$TEST_RESTORED"\n')
        restore.chmod(0o700)
        tmux = bin_dir / 'tmux'
        tmux.write_text(f'''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$TEST_TMUX_LOG"
case "$*" in
{self.RESTORE_TMUX_CASES}{tmux_cases}esac
''')
        tmux.chmod(0o700)
        return os.environ | {
            'HOME': str(root / 'home'),
            'PATH': f'{bin_dir}:{os.environ["PATH"]}',
            'TEST_TMUX_LOG': str(root / 'tmux.log'),
            'TEST_RESURRECT': str(resurrect),
            'TEST_RESTORE': str(restore),
            'TEST_RESTORED': str(root / 'restored'),
        }

    def run_restore(self, env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
        """引数を付けた復元 helper の実行"""
        return subprocess.run(['bash', str(self.RESTORE_HELPER), *args], env=env,
                              capture_output=True, text=True)

    def test_macos_installers_avoid_double_dash_after_chmod_mode(self) -> None:
        """macOS の chmod がファイル名として扱う、モードの後ろの -- を使っていないこと"""
        for script in ('installer/byobu.sh', 'installer/tmux_agent_sidebar.sh', 'installer/utils/byobu_common.sh',
                       'installer/utils/byobu_restore_after_attach.sh', 'installer/utils/byobu_resume.sh'):
            with self.subTest(script=script):
                text = (ROOT / script).read_text()
                self.assertEqual(re.findall(r'(?m)^[^#\n]*\bchmod\s+[0-7]{3,4}\s+--\s.*$', text), [])

    def test_byobu_script_configures_private_user_scoped_session_restore(self) -> None:
        """利用者専用の復元設定・plugin の固定版検証・未変更 checkout に限った置き換え・macOS の Homebrew 経路"""
        result = subprocess.run(['bash', '-n', str(self.INSTALLER)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.INSTALLER.read_text()
        for expected in ('sudo apt-get install -y byobu', "RESURRECT_VERSION='v4.0.0'",
                         "CONTINUUM_VERSION='v3.1.0'", 'Run this installer as the target user, without sudo.'):
            self.assertIn(expected, text)

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            home = root / 'home'
            data = root / 'data'
            bin_dir = root / 'bin'
            log = root / 'commands.log'
            home.mkdir()
            bin_dir.mkdir()
            log.touch()
            mocks = {
                'apt-get': ':',
                'brew': '[[ ${HOMEBREW_NO_ANALYTICS:-} == 1 ]]',
                'byobu-tmux': ':',
                'sudo': '[[ $1 == -v ]] && exit 0; "$@"',
                'uname': '[[ $1 == -s ]] && echo "${TEST_UNAME:-Linux}"',
                'tmux': '[[ $1 == -V ]] && echo "tmux 3.4"',
                'git': '''if [[ $1 == clone ]]; then
    destination=${!#}
    mkdir -p "$destination/.git"
elif [[ $1 == -C && $3 == rev-parse ]]; then
    if [[ ${TEST_PLUGIN_COMMIT:-} == bad || ( ${TEST_PLUGIN_COMMIT:-} == old && ${2%/*} == */tmux-plugins ) ]]; then
        echo bad
    elif [[ $2 == *tmux-resurrect* ]]; then
        echo e87d7d592cac97fa38c12395ebec042c154a1844
    else
        echo 46e0e0023476018ddb4cc0d44783eede27e5a8ec
    fi
elif [[ $1 == -C && $3 == remote ]]; then
    echo "https://github.com/tmux-plugins/${2##*/}.git"
elif [[ $1 == -C && $3 == status ]]; then
    printf '%s' "${TEST_PLUGIN_STATUS:-}"
elif [[ $1 == -C && $3 == rev-list ]]; then
    echo "${TEST_PLUGIN_LOCAL_COMMITS:-0}"
fi''',
            }
            for name, body in mocks.items():
                command = bin_dir / name
                command.write_text(f'#!/usr/bin/env bash\nprintf "{name} %s\\n" "$*" >> "$TEST_LOG"\n{body}\n')
                command.chmod(0o755)
            env = os.environ | {'HOME': str(home), 'XDG_DATA_HOME': str(data),
                                'TEST_LOG': str(log), 'TMUX': '',
                                'PATH': f'{bin_dir}:{os.environ["PATH"]}'}

            def run_installer(**changes: str) -> subprocess.CompletedProcess[str]:
                """環境変数を追加した installer の実行"""
                return subprocess.run(['bash', str(self.INSTALLER)], env=env | changes,
                                      capture_output=True, text=True)

            def clone_count() -> int:
                """これまでの git clone の実行回数"""
                return sum(line.startswith('git clone') for line in log.read_text().splitlines())

            result = run_installer()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('WARNING: Saved pane contents are unencrypted', result.stdout)
            self.assertIn(f'NOTE: {home}/.local/bin is not in PATH', result.stdout)
            self.assertIn('next login', result.stdout)
            config = home / '.byobu/.tmux.conf'
            config_text = config.read_text()
            for line in ('# >>> dev_setup byobu-session-restore >>>', 'set -g mouse on',
                         'set -g prefix M-a', 'unbind-key -n C-a', 'bind-key M-a send-prefix',
                         'set -s extended-keys on', 'set -sq extended-keys-format csi-u',
                         "set -s terminal-features[100] 'xterm-ghostty:extkeys'",
                         f"set -g @resurrect-dir '{data}/tmux/resurrect'",
                         'set -g @resurrect-processes false', 'set -g @resurrect-capture-pane-contents on',
                         'set -g @continuum-save-interval 3', 'set -g @continuum-save-interval 0',
                         'set -g @continuum-restore off', 'set -g @continuum-boot off',
                         'after-new-session[900]', '/byobu-session-restore/restore-after-attach.sh 3"',
                         '#{DEV_SETUP_BYOBU_RESUME_SESSION}'):
                self.assertIn(line, config_text)
            for line in ('@resurrect-save-shell-history', '@continuum-save-last-timestamp',
                         '@dev_setup-restore-after-attach-done'):
                self.assertNotIn(line, config_text)
            for path in (data / 'byobu-session-restore/restore-after-attach.sh',
                         home / '.local/bin/byobu-resume', data / 'tmux/resurrect'):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
            self.assertEqual(clone_count(), 2)
            result = run_installer(PATH=f'{home}/.local/bin:{env["PATH"]}')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(clone_count(), 2)
            self.assertFalse(list(home.glob('.byobu/.tmux.conf.before-byobu-session-restore.*')))
            self.assertNotIn('macos-option-as-alt', result.stdout)
            self.assertNotIn('is not in PATH', result.stdout)

            other_block = '# >>> dev_setup other >>>\nset -g @other on\n# <<< dev_setup other <<<\n'
            config.write_text(config_text + other_block)
            result = run_installer()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('Backed up', result.stdout)
            self.assertEqual(config.read_text(), config_text + other_block)

            calls = len(log.read_text().splitlines())
            result = run_installer(TEST_UNAME='Darwin')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('macos-option-as-alt', result.stdout)
            self.assertIn('~/.zprofile', result.stdout)
            darwin_calls = log.read_text().splitlines()[calls:]
            self.assertIn('brew install byobu', darwin_calls)
            self.assertFalse([call for call in darwin_calls if call.startswith(('sudo ', 'apt-get '))])
            result = run_installer(TEST_UNAME='FreeBSD')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Unsupported OS: FreeBSD', result.stderr)

            plugins = data / 'tmux-plugins'
            marker = plugins / 'tmux-resurrect/previous-version'
            marker.touch()
            result = run_installer(TEST_PLUGIN_COMMIT='bad')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('does not match the expected', result.stderr)
            self.assertTrue(config.exists())
            self.assertTrue(marker.exists())
            self.assertFalse(list(plugins.glob('.*')))

            result = run_installer(TEST_PLUGIN_COMMIT='old', TEST_PLUGIN_STATUS=' M resurrect.tmux')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('has local changes, local-only commits, or another origin', result.stderr)
            self.assertTrue(marker.exists())

            result = run_installer(TEST_PLUGIN_COMMIT='old', TEST_PLUGIN_LOCAL_COMMITS='1')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('local-only commits', result.stderr)
            self.assertTrue(marker.exists())

            clones = clone_count()
            result = run_installer(TEST_PLUGIN_COMMIT='old')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Updated tmux-resurrect to v4.0.0', result.stdout)
            self.assertFalse(marker.exists())
            self.assertFalse(list(plugins.glob('.*')))
            self.assertEqual(clone_count(), clones + 2)

    def test_pristine_checkout_detects_local_only_history(self) -> None:
        """実際の git での、ローカルだけの commit・stash・reflog だけの commit の検出"""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            env = os.environ | {'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1',
                                'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@t',
                                'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@t'}

            def git(*args: str) -> None:
                """作業ディレクトリでの git の実行"""
                subprocess.run(['git', *args], cwd=root, env=env, check=True, capture_output=True)

            git('init', '-q', 'upstream')
            git('-C', 'upstream', 'commit', '-q', '--allow-empty', '-m', 'pinned')
            git('-C', 'upstream', 'tag', 'v1')
            repository = f'file://{root}/upstream'
            local = ['commit', '-q', '--allow-empty', '-m', 'local']
            back_to_tag = ['switch', '-q', '--detach', 'v1']
            states = {
                'pristine': [],
                'detached-commit': [local],
                'branch-commit': [['switch', '-q', '-c', 'mine'], local, back_to_tag],
                'stash': [['stash', '-q']],
                'reflog-only': [local, back_to_tag],
            }
            for name, steps in states.items():
                with self.subTest(state=name):
                    git('clone', '-q', '--depth', '1', '--branch', 'v1', repository, name)
                    if name == 'stash':
                        (root / name / 'local').write_text('change\n')
                        git('-C', name, 'add', 'local')
                    for step in steps:
                        git('-C', name, *step)
                    result = subprocess.run(
                        ['bash', '-c', 'source "$1"; is_pristine_checkout "$2" "$3"', 'test',
                         str(self.INSTALLER), str(root / name), repository],
                        env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, name == 'pristine', result.stderr)

    def test_byobu_restore_waits_for_client_and_reuses_saved_session_name(self) -> None:
        """保存 session 名の引き継ぎ・保存間隔の再開・未完了時の通知"""
        result = subprocess.run(['bash', '-n', str(self.RESTORE_HELPER)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

        with tempfile.TemporaryDirectory() as temp:
            env = self.restore_env(Path(temp), 'state\t1\t\n')
            log = Path(env['TEST_TMUX_LOG'])
            restored = Path(env['TEST_RESTORED'])
            for args, interval in ((('5',), '5'), ((), '3')):
                with self.subTest(args=args):
                    restored.unlink(missing_ok=True)
                    log.write_text('')
                    result = self.run_restore(env, *args)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(restored.exists())
                    calls = log.read_text()
                    self.assertIn('rename-session -t =2 1', calls)
                    self.assertIn(f'set-option -g @continuum-save-interval {interval}', calls)
                    self.assertNotIn('display-message', calls)

            Path(env['TEST_RESTORE']).write_text('#!/usr/bin/env bash\nexit 42\n')
            for args, returncode in ((('5',), 42), (('x',), 1)):
                with self.subTest(args=args):
                    log.write_text('')
                    result = self.run_restore(env, *args)
                    self.assertEqual(result.returncode, returncode, result.stderr)
                    calls = log.read_text()
                    self.assertNotIn('set-option -g @continuum-save-interval', calls)
                    self.assertIn(self.RESTORE_FAILURE, calls)

    def test_byobu_restore_replaces_saved_sidebar_with_one_fresh_sidebar(self) -> None:
        """保存済み sidebar pane の破棄と window ごとに1つの sidebar 再生成"""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sidebar_dir = root / 'sidebar'
            sidebar_dir.mkdir()
            (sidebar_dir / 'agent-sidebar.conf').touch()
            sidebar = sidebar_dir / 'sidebar-bin'
            sidebar.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$TEST_SIDEBAR_LOG"\n')
            sidebar.chmod(0o700)
            sidebar_log = root / 'sidebar.log'
            last = ('pane\t1\t0\t1\t:*\t0\ttitle\t:/tmp\t0\ttmux-agent-sidebar\t:\n'
                    'pane\t1\t0\t1\t:*\t1\ttitle\t:/tmp\t1\tbash\t:\n'
                    'pane\t1\t1\t0\t:-\t0\ttitle\t:/work\t0\ttmux-agent-sidebar.real\t:\n'
                    'pane\t1\t1\t0\t:-\t1\ttitle\t:/work\t1\tbash\t:\n'
                    'state\t1\t\n')
            tmux_cases = '''  'show-option -gqv @agent_sidebar_dir') printf '%s\\n' "$TEST_SIDEBAR_DIR" ;;
  'show-option -gqv @agent_sidebar_bin') printf '%s\\n' "$TEST_SIDEBAR_BIN" ;;
  'show-option -gqv @sidebar_auto_create') printf 'on\\n' ;;
  'list-panes -a -F #{pane_id}|#{@pane_role}') printf '%%90|sidebar\\n%%91|\\n' ;;
  'display-message -p -t 1:0.0 #{window_panes}') printf '2\\n' ;;
  'display-message -p -t 1:1.0 #{window_panes}') printf '2\\n' ;;
  'list-windows -a -F #{window_id}|#{pane_current_path}') printf '@1|/tmp\\n@2|/work\\n' ;;
'''
            env = self.restore_env(root, last, tmux_cases) | {
                'TEST_SIDEBAR_LOG': str(sidebar_log),
                'TEST_SIDEBAR_DIR': str(sidebar_dir),
                'TEST_SIDEBAR_BIN': str(sidebar),
            }
            result = self.run_restore(env, '3')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(Path(env['TEST_RESTORED']).exists())
            calls = Path(env['TEST_TMUX_LOG']).read_text()
            self.assertIn('kill-pane -t %90', calls)
            self.assertIn('kill-pane -t 1:0.0', calls)
            self.assertIn('kill-pane -t 1:1.0', calls)
            self.assertNotIn('pane_start_command', calls)
            self.assertEqual(sidebar_log.read_text(),
                             'toggle --create-only @1 /tmp\ntoggle --create-only @2 /work\n')

    def test_byobu_resume_explicitly_requests_latest_snapshot(self):
        resume = ROOT / 'installer/utils/byobu_resume.sh'
        result = subprocess.run(['bash', '-n', str(resume)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            home = root / 'home'
            data = root / 'data'
            bin_dir = root / 'bin'
            log = root / 'commands.log'
            (data / 'tmux/resurrect').mkdir(parents=True)
            home.mkdir()
            bin_dir.mkdir()
            (data / 'tmux/resurrect/last').write_text(
                'pane\t7\t0\t1\t:*\t0\ttitle\t:/tmp\t1\tbash\t:\n'
                'state\t\t\n')

            tmux = bin_dir / 'tmux'
            tmux.write_text('''#!/usr/bin/env bash
printf 'tmux %s\\n' "$*" >> "$TEST_LOG"
[[ $1 != list-sessions ]]
''')
            tmux.chmod(0o700)
            byobu = bin_dir / 'byobu-tmux'
            byobu.write_text('''#!/usr/bin/env bash
printf 'byobu %s resume=%s\\n' "$*" "${DEV_SETUP_BYOBU_RESUME_SESSION:-}" >> "$TEST_LOG"
''')
            byobu.chmod(0o700)
            env = os.environ | {
                'HOME': str(home),
                'XDG_DATA_HOME': str(data),
                'TEST_LOG': str(log),
                'PATH': f'{bin_dir}:{os.environ["PATH"]}',
                'TMUX': '',
            }
            result = subprocess.run(['bash', str(resume)], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('byobu  resume=7', log.read_text())

            tmux.write_text('''#!/usr/bin/env bash
printf 'tmux %s\\n' "$*" >> "$TEST_LOG"
[[ $1 == list-sessions ]] && exit 0
[[ $1 == has-session ]] && exit 1
''')
            tmux.chmod(0o700)
            log.write_text('')
            result = subprocess.run(['bash', str(resume)], env=env,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('already running without saved session 7', result.stderr)
            self.assertNotIn('byobu ', log.read_text())


class TmuxAgentSidebarInstallerTests(unittest.TestCase):
    LINUX_X86_64_SHA256 = 'e06495a327a074c6e38c3d7697f061bdb6d19f04b67d9fc30137d34d9318e344'
    DARWIN_AARCH64_SHA256 = '61c7faf1b37ae72614889914ce016378b0e48461d74d6faf360193ed648c23a3'

    def test_scripts_are_syntax_valid_and_keep_changes_in_the_user_home(self):
        installer = ROOT / 'installer/tmux_agent_sidebar.sh'
        hooks = ROOT / 'installer/tmux_agent_sidebar_hooks.sh'
        for script in (installer, hooks):
            result = subprocess.run(['bash', '-n', str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotRegex(script.read_text(), r'(^|\n)\s*sudo\b')
        text = installer.read_text()
        self.assertIn("SIDEBAR_VERSION='v0.13.0'", text)
        self.assertIn("SIDEBAR_COMMIT='d89fe2025cd3f7149b0c8af9d48f15eab5fc2a3a'", text)
        self.assertIn('XDG_DATA_HOME', text)
        self.assertIn('$HOME/.byobu', text)
        self.assertIn(f"SIDEBAR_DARWIN_AARCH64_SHA256='{self.DARWIN_AARCH64_SHA256}'", text)
        self.assertIn('shasum -a 256', text)

    def test_installer_writes_only_user_scoped_byobu_configuration(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bin_dir = root / 'bin'
            home = root / 'home'
            data = root / 'data'
            bin_dir.mkdir()
            home.mkdir()
            commands = root / 'commands.log'
            commands.touch()
            mocks = {
                'byobu-tmux': ':',
                'tmux': 'if [[ $1 == -V ]]; then echo "tmux 3.4"; fi',
                'uname': '[[ $1 == -s ]] && echo "${TEST_UNAME:-Linux}"; [[ $1 == -m ]] && echo "${TEST_ARCH:-x86_64}"; true',
                'git': '''if [[ $1 == clone ]]; then
    destination=${!#}
    mkdir -p "$destination/.git" "$destination/.opencode/plugins"
    touch "$destination/tmux-agent-sidebar.tmux" "$destination/hook.sh" \\
        "$destination/.opencode/plugins/tmux-agent-sidebar.js"
elif [[ $1 == -C && $3 == rev-parse ]]; then
    if [[ -n ${TEST_OLD_CHECKOUT:-} && ${2%/*} == "$XDG_DATA_HOME" ]]; then
        echo old
    else
        echo d89fe2025cd3f7149b0c8af9d48f15eab5fc2a3a
    fi
elif [[ $1 == -C && $3 == remote ]]; then
    echo https://github.com/hiroppy/tmux-agent-sidebar.git
elif [[ $1 == -C && $3 == status ]]; then
    printf '%s' "${TEST_PLUGIN_STATUS:-}"
elif [[ $1 == -C && $3 == rev-list ]]; then
    echo 0
fi''',
                'curl': 'while (( $# )); do [[ $1 == --output ]] && { touch "$2"; break; }; shift; done',
                'sha256sum': 'printf "%s  %s\\n" "${TEST_SHA256:-' + self.LINUX_X86_64_SHA256 + '}" "${!#}"',
            }
            for name, body in mocks.items():
                command = bin_dir / name
                command.write_text(f'#!/usr/bin/env bash\nprintf "{name} %s\\n" "$*" >> "$TEST_LOG"\n{body}\n')
                command.chmod(0o755)
            env = os.environ | {'HOME': str(home), 'XDG_DATA_HOME': str(data),
                                'CLAUDE_CONFIG_DIR': str(home / '.claude'),
                                'TEST_LOG': str(commands),
                                'PATH': f'{bin_dir}:{os.environ["PATH"]}'}
            installer = ROOT / 'installer/tmux_agent_sidebar.sh'
            binary = data / 'tmux-agent-sidebar/bin/tmux-agent-sidebar'
            real_binary = binary.with_name('tmux-agent-sidebar.real')
            cached = home / '.claude/plugins/cache/hiroppy/tmux-agent-sidebar/0.13.0/bin/tmux-agent-sidebar'
            cached.parent.mkdir(parents=True)
            cached.write_text('unwrapped binary from an older install\n')
            old_log = Path(f'/tmp/tmux-agent-activity_dev_setup_test_{os.getpid()}.log')
            old_log.write_text('')
            old_log.chmod(0o664)
            self.addCleanup(old_log.unlink, missing_ok=True)

            def run_installer(**changes: str) -> subprocess.CompletedProcess[str]:
                """環境変数を追加した installer の実行"""
                return subprocess.run(['bash', str(installer)], env=env | changes, capture_output=True, text=True)

            def downloads() -> list[str]:
                """これまでの curl の呼び出し"""
                return [line for line in commands.read_text().splitlines() if line.startswith('curl ')]

            result = run_installer()
            self.assertEqual(result.returncode, 0, result.stderr)
            config = home / '.byobu/.tmux.conf'
            self.assertIn('# >>> dev_setup tmux-agent-sidebar >>>', config.read_text())
            self.assertIn('set -g @sidebar_auto_create on', config.read_text())
            self.assertIn('set -g @sidebar_bottom_height 20', config.read_text())
            self.assertIn(f"set -g @agent_sidebar_dir '{data}/tmux-agent-sidebar'", config.read_text())
            self.assertIn(str(data / 'tmux-agent-sidebar/tmux-agent-sidebar.tmux'), config.read_text())
            self.assertEqual(len(downloads()), 1)
            self.assertRegex(downloads()[0], r'--output .*/bin/\.tmux-agent-sidebar\..* \S+/tmux-agent-sidebar-linux-x86_64$')
            self.assertFalse(list(home.glob('.byobu/.tmux.conf.before-tmux-agent-sidebar.*')))
            self.assertEqual(stat.S_IMODE(binary.stat().st_mode), 0o755)
            self.assertIn(f"exec '{real_binary}'", binary.read_text())
            self.assertEqual(stat.S_IMODE(old_log.stat().st_mode), 0o600)
            self.assertEqual(cached.read_text(), binary.read_text())
            self.assertIn(f'Updated the Claude Code plugin cache: {cached}', result.stdout)

            # A verified binary is not downloaded again, and a block followed by
            # another managed block stays where it is.
            other_block = '# >>> dev_setup other >>>\nset -g @other on\n# <<< dev_setup other <<<\n'
            config.write_text(config.read_text() + other_block)
            config_text = config.read_text()
            result = run_installer()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(downloads()), 1)
            self.assertNotIn('Backed up', result.stdout)
            self.assertNotIn('plugin cache', result.stdout)
            self.assertEqual(config.read_text(), config_text)

            result = run_installer(TEST_OLD_CHECKOUT='1', TEST_PLUGIN_STATUS=' M hook.sh')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('has local changes, local-only commits, or another origin', result.stderr)
            result = run_installer(TEST_OLD_CHECKOUT='1')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Updated tmux-agent-sidebar to v0.13.0', result.stdout)
            self.assertFalse(list(data.glob('.*')))
            self.assertEqual(len(downloads()), 2)

            real_binary.unlink()
            result = run_installer(TEST_SHA256='bad')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('checksum verification failed', result.stderr)
            result = run_installer(TEST_UNAME='Darwin', TEST_ARCH='arm64', TEST_SHA256=self.DARWIN_AARCH64_SHA256)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertRegex(downloads()[-1], r'/tmux-agent-sidebar-darwin-aarch64$')
            result = run_installer(TEST_UNAME='FreeBSD')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Unsupported platform: FreeBSD', result.stderr)

            # Only the hook subcommand, which writes the activity log, runs owner-only.
            real_binary.write_text('#!/bin/sh\n: > "$TEST_OUT/$1"\n')
            for subcommand, mode in (('hook', 0o600), ('toggle', 0o664)):
                with self.subTest(subcommand=subcommand):
                    result = subprocess.run(['bash', '-c', 'umask 002; exec "$0" "$@"', str(binary), subcommand],
                                            env=env | {'TEST_OUT': str(root)}, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(stat.S_IMODE((root / subcommand).stat().st_mode), mode)

    def test_hook_script_reports_supported_agents(self):
        result = subprocess.run(
            ['bash', str(ROOT / 'installer/tmux_agent_sidebar_hooks.sh'), '--help'],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('codex', result.stdout)
        self.assertIn('claude', result.stdout)
        self.assertIn('opencode', result.stdout)

    def test_hook_script_merges_codex_and_links_opencode_in_user_home(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            home = root / 'home'
            data = root / 'data'
            home.mkdir()
            binary = data / 'tmux-agent-sidebar/bin/tmux-agent-sidebar'
            bridge = data / 'tmux-agent-sidebar/.opencode/plugins/tmux-agent-sidebar.js'
            binary.parent.mkdir(parents=True)
            bridge.parent.mkdir(parents=True)
            binary.write_text('''#!/usr/bin/env bash
if [[ $1 == setup && $2 == codex ]]; then
    printf '%s\\n' '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"bash hook.sh codex session-start"}]}]}}'
fi
''')
            binary.chmod(0o755)
            bridge.touch()
            codex_dir = home / '.codex'
            codex_dir.mkdir()
            (codex_dir / 'config.toml').write_text(
                '[features]\n'
                'codex_hooks = false\n'
                'multi_agent = true\n'
            )
            env = os.environ | {'HOME': str(home), 'XDG_DATA_HOME': str(data),
                                'XDG_CONFIG_HOME': str(root / 'config')}
            script = ROOT / 'installer/tmux_agent_sidebar_hooks.sh'
            result = subprocess.run(['bash', str(script), '--agent', 'codex'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            config = (home / '.codex/config.toml').read_text()
            self.assertIn('hooks = true', config)
            self.assertNotIn('codex_hooks', config)
            self.assertIn('multi_agent = true', config)
            hooks = (home / '.codex/hooks.json').read_text()
            self.assertEqual(hooks.count('bash hook.sh codex session-start'), 1)
            result = subprocess.run(['bash', str(script), '--agent', 'codex'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((home / '.codex/hooks.json').read_text().count('bash hook.sh codex session-start'), 1)
            result = subprocess.run(['bash', str(script), '--agent', 'opencode'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / 'config/opencode/plugins/tmux-agent-sidebar.js').resolve(), bridge)


if __name__ == '__main__':
    unittest.main()
