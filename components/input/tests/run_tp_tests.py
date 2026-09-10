"""Compile the actual TP task bridge, input core/service and LVGL touch consumer.
No Lua module is enabled: this also checks independent C-only operation.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import os, subprocess, tempfile
root = Path(__file__).resolve().parents[3]
airui = root/'components/airui'
cc = os.environ.get('CC', 'gcc')
if Path(cc).is_file(): os.environ['PATH'] = str(Path(cc).resolve().parent)+os.pathsep+os.environ['PATH']
with tempfile.TemporaryDirectory(prefix='input-tp-') as tmp:
    out = Path(tmp)
    headers = {
        'luat_conf_bsp.h': '#define AIRUI_TOUCH_MAX_POINTS 10\n#define AIRUI_POINTER_INDEV_MAX 3\n',
        'luat_base.h': '#pragma once\n#include <stdint.h>\n#include <string.h>\n#define LUAT_WEAK\n',
        'luat_mem.h': '#include "luat_malloc.h"\n',
        'luat_log.h': 'void test_log(const char *, ...);\n#define LLOGE(...) test_log(__VA_ARGS__)\n#define LLOGW(...) test_log(__VA_ARGS__)\n#define LLOGI(...) test_log(__VA_ARGS__)\n',
        'luat_mcu.h': '#pragma once\n#include <stdint.h>\nuint32_t luat_mcu_ticks(void);\n',
        'luat_i2c.h': '#pragma once\ntypedef struct {int unused;} luat_ei2c_t;\n',
        'luat_gpio.h': '#pragma once\n#include <stdint.h>\nint luat_gpio_irq_enable(int,uint8_t,int,void*);\n',
        'luat_rtos.h': r"""#pragma once
#include <stdint.h>
#include <stddef.h>
typedef void *luat_rtos_mutex_t;
typedef void *luat_rtos_task_handle;
#define LUAT_WAIT_FOREVER UINT32_MAX
int luat_rtos_mutex_create(luat_rtos_mutex_t *);
int luat_rtos_mutex_lock(luat_rtos_mutex_t, uint32_t);
int luat_rtos_mutex_unlock(luat_rtos_mutex_t);
int luat_rtos_task_create(luat_rtos_task_handle*,uint32_t,uint32_t,const char*,void(*)(void*),void*,uint32_t);
void luat_rtos_task_sleep(uint32_t);
int luat_rtos_message_recv(luat_rtos_task_handle,uint32_t*,void*,uint32_t);
""",
    }
    for name,text in headers.items(): (out/name).write_text(text,encoding='utf-8')
    sources = sorted(p for p in (airui/'lvgl9/src').rglob('*.c') if p.name!='luat_lv_mem_core_custom.c')
    production = [root/'components/input'/name for name in ['luat_input.c','luat_input_queue.c','luat_input_service.c','luat_input_touch.c']]
    production += [root/'components/tp'/name for name in ['luat_tp.c','luat_tp_input.c']]
    production += [airui/'src/platform/luatos/luat_airui_input_touch_luatos.c',root/'components/input/tests/tp_test.c']
    sources += production
    flags = ['-std=c11','-O1','-DLUAT_USE_INPUT','-DLUAT_USE_INPUT_TOUCH','-DLUAT_USE_INPUT_QUEUE',
             '-DLUAT_USE_AIRUI_LUATOS','-DLV_CONF_SKIP','-DLV_MEM_SIZE=2097152']
    flags += ['-I'+str(p) for p in [out,root/'luat/include',root/'components/tp',airui,airui/'inc',airui/'lvgl9',airui/'src/platform/luatos']]
    def compile_one(item):
        i,p=item;obj=out/f'{i}.o'
        strict=['-Wall','-Wextra','-Werror'] if p in production else []
        r=subprocess.run([cc,*flags,*strict,'-c',str(p),'-o',str(obj)],capture_output=True,text=True,encoding='utf-8',errors='replace')
        if r.returncode: raise RuntimeError(str(p)+'\n'+r.stdout+r.stderr)
        return obj
    print('Compiling C-only TP/input and real LVGL touch consumer...',flush=True)
    with ThreadPoolExecutor(max_workers=8) as pool: objects=list(pool.map(compile_one,enumerate(sources)))
    response=out/'objects.rsp';response.write_text('\n'.join('"'+str(p).replace('\\','/')+'"' for p in objects))
    exe=out/'tp_test.exe'
    subprocess.run([cc,'@'+str(response),'-lm','-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True,timeout=30)
    standalone=out/'tp_standalone.exe'
    subprocess.run([cc,'-std=c11','-Wall','-Wextra','-Werror',
                   '-I'+str(out),'-I'+str(root/'luat/include'),'-I'+str(root/'components/tp'),
                   str(root/'components/tp/luat_tp.c'),str(root/'components/input/tests/tp_standalone_test.c'),
                   '-o',str(standalone)],check=True)
    subprocess.run([str(standalone)],check=True,timeout=10)
