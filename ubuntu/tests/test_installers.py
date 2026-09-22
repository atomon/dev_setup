"""No network, package installation, or desktop setting changes."""
import os
from pathlib import Path
import shutil
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


class TmuxAgentSidebarInstallerTests(unittest.TestCase):
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
        self.assertIn('sha256sum --check --status', text)

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
                'git': '''if [[ $1 == clone ]]; then
    destination=${!#}
    mkdir -p "$destination/.git" "$destination/.opencode/plugins"
    touch "$destination/tmux-agent-sidebar.tmux" "$destination/hook.sh" \\
        "$destination/.opencode/plugins/tmux-agent-sidebar.js"
elif [[ $1 == -C ]]; then
    echo d89fe2025cd3f7149b0c8af9d48f15eab5fc2a3a
fi''',
                'curl': 'while (( $# )); do [[ $1 == --output ]] && { touch "$2"; break; }; shift; done',
                'sha256sum': '[[ $1 == --check ]] && { cat >/dev/null; exit 0; }',
            }
            for name, body in mocks.items():
                command = bin_dir / name
                command.write_text(f'#!/usr/bin/env bash\nprintf "{name} %s\\n" "$*" >> "$TEST_LOG"\n{body}\n')
                command.chmod(0o755)
            env = os.environ | {'HOME': str(home), 'XDG_DATA_HOME': str(data),
                                'TEST_LOG': str(commands),
                                'PATH': f'{bin_dir}:{os.environ["PATH"]}'}
            installer = ROOT / 'installer/tmux_agent_sidebar.sh'
            result = subprocess.run(['bash', str(installer)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            config = home / '.byobu/.tmux.conf'
            self.assertIn('# >>> dev_setup tmux-agent-sidebar >>>', config.read_text())
            self.assertIn(str(data / 'tmux-agent-sidebar/tmux-agent-sidebar.tmux'), config.read_text())
            self.assertFalse(list(home.glob('.byobu/.tmux.conf.before-tmux-agent-sidebar.*')))
            result = subprocess.run(['bash', str(installer)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(list(home.glob('.byobu/.tmux.conf.before-tmux-agent-sidebar.*')))

    def test_hook_script_reports_supported_agents(self):
        result = subprocess.run(
            ['bash', str(ROOT / 'installer/tmux_agent_sidebar_hooks.sh'), '--help'],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('codex', result.stdout)
        self.assertIn('claude', result.stdout)
        self.assertIn('opencode', result.stdout)

    def test_byobu_script_uses_ubuntu_packages_without_creating_user_configuration(self):
        script = ROOT / 'installer/byobu.sh'
        result = subprocess.run(['bash', '-n', str(script)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = script.read_text()
        self.assertIn('apt=(sudo apt-get)', text)
        self.assertIn('"${apt[@]}" install -y tmux byobu', text)
        self.assertNotIn('mkdir ', text)

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
            env = os.environ | {'HOME': str(home), 'XDG_DATA_HOME': str(data),
                                'XDG_CONFIG_HOME': str(root / 'config')}
            script = ROOT / 'installer/tmux_agent_sidebar_hooks.sh'
            result = subprocess.run(['bash', str(script), '--agent', 'codex'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('codex_hooks = true', (home / '.codex/config.toml').read_text())
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
