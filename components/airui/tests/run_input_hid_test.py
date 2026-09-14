"""Build bundled LVGL and exercise real indev/widget events without SDL or Lua."""
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
airui = root / 'components/airui'
cc = os.environ.get('CC', 'gcc')
with tempfile.TemporaryDirectory(prefix='airui-input-') as tmp:
    build = Path(tmp)
    (build / 'luat_conf_bsp.h').write_text(
        '#define LUAT_USE_INPUT 1\n#define LUAT_USE_AIRUI_LUATOS 1\n')
    flags = ['-std=c11', '-O1', '-DLV_CONF_SKIP', '-DLV_MEM_SIZE=2097152',
             '-I' + str(build), '-I' + str(airui), '-I' + str(airui / 'lvgl9'),
             '-I' + str(root / 'luat/include'),
             '-I' + str(airui / 'src/platform/luatos')]
    sources = sorted(p for p in (airui / 'lvgl9/src').rglob('*.c')
                     if p.name != 'luat_lv_mem_core_custom.c')
    sources += [airui / 'src/platform/luatos/luat_airui_input_hid_luatos.c',
                airui / 'tests/input_hid_test.c']

    def compile_one(item):
        index, source = item
        obj = build / f'{index}.o'
        result = subprocess.run([cc, *flags, '-c', str(source), '-o', str(obj)],
                                capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(str(source) + '\n' + result.stderr)
        return obj

    print('Compiling bundled LVGL 9 and HID bridge...', flush=True)
    with ThreadPoolExecutor(max_workers=8) as pool:
        objects = list(pool.map(compile_one, enumerate(sources)))
    response = build / 'objects.rsp'
    response.write_text('\n'.join('"' + str(p).replace('\\', '/') + '"' for p in objects))
    exe = build / ('input_hid_test.exe' if os.name == 'nt' else 'input_hid_test')
    subprocess.run([cc, '@' + str(response), '-lm', '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=30)
