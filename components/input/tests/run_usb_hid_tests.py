"""Common USB HID adapter regressions; no CCM headers or hardware required."""
from pathlib import Path
import os, subprocess, tempfile

root = Path(__file__).resolve().parents[3]
cc = os.environ.get('CC', 'gcc')
if Path(cc).is_file():
    os.environ['PATH'] = str(Path(cc).resolve().parent) + os.pathsep + os.environ['PATH']
with tempfile.TemporaryDirectory(prefix='input-usb-hid-') as tmp:
    out = Path(tmp)
    headers = {
        'luat_conf_bsp.h': '',
        'luat_base.h': '#pragma once\n#include <stdint.h>\n#include <stddef.h>\n#define LUAT_WEAK\n',
        'luat_mcu.h': '#include <stdint.h>\nuint64_t luat_mcu_tick64_ms(void);\n',
        'luat_rtos.h': '''#pragma once
#include <stdint.h>
typedef void *luat_rtos_mutex_t;
typedef void *luat_rtos_task_handle;
luat_rtos_task_handle luat_rtos_get_current_handle(void);
typedef struct {uint32_t id,param1,param2,param3;} luat_event_t;
int luat_rtos_mutex_create(luat_rtos_mutex_t *);
int luat_rtos_mutex_lock(luat_rtos_mutex_t,uint32_t);
int luat_rtos_mutex_unlock(luat_rtos_mutex_t);
uint32_t luat_rtos_entry_critical(void);
void luat_rtos_exit_critical(uint32_t);
int luat_rtos_task_create(luat_rtos_task_handle*,uint32_t,uint8_t,const char*,void(*)(void*),void*,uint16_t);
int luat_rtos_event_send(luat_rtos_task_handle,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
int luat_rtos_event_recv(luat_rtos_task_handle,uint32_t,luat_event_t*,void*,uint32_t);
''',
    }
    for name, text in headers.items(): (out/name).write_text(text, encoding='utf-8')
    flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-O1', '-I'+str(out), '-I'+str(root/'luat/include')]
    common = root/'components/input'
    callback = root/'luat/weak/luat_usb_hid.c'
    sources = [common/'tests/usb_hid_test.c', common/'luat_input.c', common/'luat_input_hid.c', common/'luat_input_log.c', callback]
    for service in (False, True):
        extra = ['-DLUAT_USE_INPUT', '-DLUAT_USE_INPUT_HID']
        src = list(sources)
        if service:
            extra += ['-DLUAT_USE_INPUT_SERVICE', '-DLUAT_USE_INPUT_QUEUE', '-DLUAT_USE_AIRUI_LUATOS']
            src += [common/'luat_input_service.c', common/'luat_input_queue.c', root/'components/airui/src/platform/luatos/luat_airui_input_service_luatos.c']
        exe = out/f'hid_{service}.exe'
        subprocess.run([cc, *flags, *extra, *map(str, src), '-o', str(exe)], check=True)
        subprocess.run([str(exe)], check=True, timeout=20)
    # Macro-off transport callback links/runs without input, RTOS, heap or logs.
    off = out/'off.c'
    off.write_text('''#include <assert.h>
#include "luat_usb_hid.h"
int main(void) {
    luat_usb_hid_host_t d={0};
    for(int e=LUAT_USB_HID_OPEN;e<=LUAT_USB_HID_RX_ERROR;e++)
        luat_usb_hid_host_callback(&d,e,0,0);
    assert(!d.userdata);return 0;
}
''')
    subprocess.run([cc,*flags,str(off),str(callback),str(common/'luat_input_usb_hid.c'),'-o',str(out/'off.exe')],check=True)
    subprocess.run([str(out/'off.exe')],check=True)
    # Application registration overrides all policy even with INPUT_HID enabled.
    override = out/'override.c'
    override.write_text('''#include <assert.h>
#include "luat_input_usb_hid.h"
static unsigned received;
void luat_input_usb_hid_callback(luat_usb_hid_host_t *d,luat_usb_hid_event_t e,const uint8_t *p,uint32_t n)
{(void)d;(void)e;(void)p;(void)n;assert(0);}
static void application(luat_usb_hid_host_t *d,luat_usb_hid_event_t e,const uint8_t *p,uint32_t n)
{(void)d;assert(e==LUAT_USB_HID_REPORT && n==1 && *p==42);received++;}
int main(void){uint8_t p=42;luat_usb_hid_host_t d={0};luat_usb_hid_set_callback(application);luat_usb_hid_host_callback(&d,LUAT_USB_HID_REPORT,&p,1);assert(received==1);return 0;}
''')
    subprocess.run([cc,*flags,'-DLUAT_USE_INPUT_HID',str(override),str(callback),'-o',str(out/'override.exe')],check=True)
    subprocess.run([str(out/'override.exe')],check=True)
    print('USB HID callback PASS: input disabled and custom application override',flush=True)
