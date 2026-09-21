#!/usr/bin/env python3
"""Print the Hazkey GGML Vulkan device name for the best available GPU.

Vulkan device order is shared by vulkaninfo and GGML.  GGML exposes those
devices as Vulkan0, Vulkan1, and so on.  CPU implementations such as
llvmpipe are deliberately excluded.
"""
import os
import re
import shutil
import subprocess
import sys


def vulkan_summary():
    command = shutil.which('vulkaninfo')
    if not command:
        return ''
    environment = os.environ.copy()
    # Surface enumeration is unnecessary and can fail outside a GUI session.
    environment.pop('DISPLAY', None)
    environment.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(
        [command, '--summary'], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False, env=environment,
    )
    return result.stdout


def select_gpu_index(summary):
    devices = []
    current = None
    for line in summary.splitlines():
        found = re.match(r'^GPU(\d+):\s*$', line.strip())
        if found:
            current = {'index': int(found.group(1)), 'type': ''}
            devices.append(current)
            continue
        if current:
            found = re.match(r'^deviceType\s*=\s*PHYSICAL_DEVICE_TYPE_(\w+)', line.strip())
            if found:
                current['type'] = found.group(1)

    priority = {'DISCRETE_GPU': 0, 'INTEGRATED_GPU': 1, 'VIRTUAL_GPU': 2}
    usable = [device for device in devices if device['type'] in priority]
    if not usable:
        return None
    return min(usable, key=lambda device: (priority[device['type']], device['index']))['index']


def main():
    index = select_gpu_index(vulkan_summary())
    if index is None:
        return 1
    print(f'Vulkan{index}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
