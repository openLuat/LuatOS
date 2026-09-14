"""Native input-core regression and optional Cortex-M size inspection; no SDK/Lua needed."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--arm-cc', help='Optional arm-none-eabi-gcc executable for Cortex-M4 object checks')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
component = root / 'components/input'
sources = [component / 'luat_input.c', component / 'luat_input_queue.c']
flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-Wpedantic', '-O2',
         '-DLUAT_USE_INPUT', '-DLUAT_USE_INPUT_QUEUE', '-I' + str(root / 'luat/include')]
cc = os.environ.get('CC', 'gcc')
with tempfile.TemporaryDirectory(prefix='luat-input-') as folder:
    build = Path(folder)
    exe = build / ('input_test.exe' if os.name == 'nt' else 'input_test')
    cmd = [cc, *flags, *(str(p) for p in sources), str(component / 'tests/input_test.c'), '-o', str(exe)]
    if os.name != 'nt':
        cmd.append('-pthread')
    subprocess.run(cmd, check=True)
    subprocess.run([str(exe)], check=True, timeout=30)
    smoke = build / ('core_only.exe' if os.name == 'nt' else 'core_only')
    subprocess.run([cc, *(flag for flag in flags if flag != '-DLUAT_USE_INPUT_QUEUE'),
                    str(sources[0]), str(component / 'tests/core_only_test.c'), '-o', str(smoke)], check=True)
    subprocess.run([str(smoke)], check=True, timeout=10)
    hid = build / ('hid_test.exe' if os.name == 'nt' else 'hid_test')
    subprocess.run([cc, *flags, '-DLUAT_USE_INPUT_HID', str(sources[0]),
                    str(component / 'luat_input_hid.c'), str(component / 'tests/hid_test.c'),
                    '-o', str(hid)], check=True)
    subprocess.run([str(hid)], check=True, timeout=30)
    touch = build / ('touch_test.exe' if os.name == 'nt' else 'touch_test')
    subprocess.run([cc, *flags, '-DLUAT_USE_INPUT_TOUCH', str(sources[0]),
                    str(component / 'luat_input_touch.c'), str(component / 'tests/touch_test.c'),
                    '-o', str(touch)], check=True)
    subprocess.run([str(touch)], check=True, timeout=30)
    # Both feature-off and core-only builds must stay independent of queue/RTOS.
    for source in [*sources, component / 'luat_input_hid.c', component / 'luat_input_touch.c']:
        subprocess.run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wpedantic',
                        '-I' + str(root / 'luat/include'), '-c', str(source),
                        '-o', str(build / (source.stem + '_off.o'))], check=True)
    if args.arm_cc:
        arm = str(Path(args.arm_cc).resolve()) if Path(args.arm_cc).exists() else shutil.which(args.arm_cc)
        if not arm:
            raise SystemExit('ARM compiler not found')
        objects = []
        for source in [*sources, component / 'luat_input_hid.c', component / 'luat_input_touch.c']:
            obj = build / (source.stem + '_arm.o')
            subprocess.run([arm, *flags, '-DLUAT_USE_INPUT_HID', '-DLUAT_USE_INPUT_TOUCH', '-Os', '-mcpu=cortex-m4', '-mthumb',
                            '-ffunction-sections', '-fdata-sections', '-fstack-usage',
                            '-c', str(source), '-o', str(obj)], check=True)
            objects.append(obj)
        size = str(Path(arm).with_name(Path(arm).name.replace('gcc', 'size')))
        nm = str(Path(arm).with_name(Path(arm).name.replace('gcc', 'nm')))
        print('Cortex-M4 -Os object sizes (before linker GC):', flush=True)
        subprocess.run([size, *(str(p) for p in objects)], check=True)
        print('Undefined symbols (no RTOS, Lua or heap dependency expected):', flush=True)
        subprocess.run([nm, '-u', *(str(p) for p in objects)], check=True)
        probe = build / 'layout.c'
        probe.write_text('#include "luat_input.h"\n' + '\n'.join(
            f'const char sizeof_{name}[sizeof(luat_input_{name}_t)] = {{0}};'
            for name in ('core', 'device', 'link', 'queue', 'device_desc', 'snapshot')), encoding='utf-8')
        probe_obj = build / 'layout.o'
        subprocess.run([arm, *flags, '-DLUAT_USE_INPUT_HID', '-Os', '-mcpu=cortex-m4', '-mthumb', '-c', str(probe), '-o', str(probe_obj)], check=True)
        print('Cortex-M4 object layouts (symbol sizes in decimal):', flush=True)
        subprocess.run([nm, '-S', '--radix=d', str(probe_obj)], check=True)
        print('Cortex-M4 stack estimates:', flush=True)
        for usage in sorted(build.glob('*.su')):
            for line in usage.read_text().splitlines():
                print(line.split('/')[-1])
