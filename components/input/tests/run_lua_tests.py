# Production input service/binding with bundled Lua and host RTOS shims.
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import os, subprocess, tempfile
root = Path(__file__).resolve().parents[3]
component = root / 'components/input'
cc = os.environ.get('CC', 'gcc')
if Path(cc).is_file(): os.environ['PATH'] = str(Path(cc).resolve().parent) + os.pathsep + os.environ['PATH']
with tempfile.TemporaryDirectory(prefix='input-lua-') as tmp:
    out = Path(tmp)
    headers = {
        'luat_conf_bsp.h': '#define LUAT_CONF_BSP\n#define LUAT_CONF_VM_64bit\n#define LUAT_CONF_LUASTATE_NOT_STATIC\n#define LUAT_CONF_CUSTOM_SPRINTF\n#include <stdio.h>\n#define l_sprintf snprintf\n#define sprintf_ sprintf\n',
        'luat_base.h': '#pragma once\n#include <stdint.h>\n#include "lua.h"\n#include "lauxlib.h"\n#include "lualib.h"\n#include "luat_malloc.h"\n',
        'luat_mem.h': '#pragma once\n#include <stddef.h>\n#include "luat_malloc.h"\n',
        'bget.h': '',
        'luat_log.h': '#pragma once\nvoid input_test_log(const char *, ...);\n#define LLOGE(...) input_test_log(__VA_ARGS__)\n#define LLOGD(...) input_test_log(__VA_ARGS__)\n',
        'luat_rtos.h': '''#pragma once
#include <stdint.h>
typedef void *luat_rtos_mutex_t;
typedef void *luat_rtos_timer_t;
int luat_rtos_mutex_create(luat_rtos_mutex_t *);
int luat_rtos_mutex_lock(luat_rtos_mutex_t, uint32_t);
int luat_rtos_mutex_unlock(luat_rtos_mutex_t);
int luat_rtos_timer_create(luat_rtos_timer_t *);
int luat_rtos_timer_start(luat_rtos_timer_t, uint32_t, int, void (*)(void *), void *);
int luat_rtos_timer_stop(luat_rtos_timer_t);
int luat_rtos_timer_delete(luat_rtos_timer_t);
''',
        'luat_msgbus.h': '''#pragma once
#include "lua.h"
typedef struct {int (*handler)(lua_State *, void *); void *ptr; int arg1, arg2;} rtos_msg_t;
unsigned luat_msgbus_put(rtos_msg_t *, size_t);
''',
        'luat_fs.h': '''#pragma once
#include <stdio.h>
static inline FILE *luat_fs_fopen(const char *a,const char *b) {return fopen(a,b);}
static inline int luat_fs_fclose(FILE *f) {return fclose(f);}
static inline size_t luat_fs_fread(void *p,size_t s,size_t n,FILE *f) {return fread(p,s,n,f);}
static inline int luat_fs_fseek(FILE *f,long p,int o) {return fseek(f,p,o);}
static inline int luat_fs_feof(FILE *f) {return feof(f);}
static inline int luat_fs_ferror(FILE *f) {return ferror(f);}
static inline int luat_fs_getc(FILE *f) {return getc(f);}
''',
    }
    for name, text in headers.items(): (out/name).write_text(text, encoding='utf-8')
    names = 'lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject lopcodes lparser lstate lstring ltable ltm lundump lvm lzio lauxlib lbaselib ltablib lcorolib rotable2 rotable'.split()
    sources = [root/'lua/src'/f'{name}.c' for name in names]
    sources += [component/'luat_input.c', component/'luat_input_queue.c', component/'luat_input_service.c',
                root/'luat/modules/luat_lib_input.c', component/'tests/lua_input_test.c']
    flags = ['-std=c11', '-O1', '-DLUAT_USE_INPUT', '-DLUAT_USE_INPUT_LUA',
             '-I'+str(out), '-I'+str(root/'lua/include'), '-I'+str(root/'luat/include')]
    def compile_one(item):
        i, source = item
        obj = out/f'{i}.o'
        extra = ['-Wall', '-Wextra', '-Werror'] if source in sources[-5:] else []
        result = subprocess.run([cc,*flags,*extra,'-c',str(source),'-o',str(obj)], capture_output=True,text=True,encoding="utf-8",errors="replace")
        if result.returncode: raise RuntimeError(str(source)+'\n'+result.stderr)
        return obj
    with ThreadPoolExecutor(max_workers=8) as pool:
        objects = list(pool.map(compile_one, enumerate(sources)))
    exe = out/'input_lua_test.exe'
    link = subprocess.run([cc,*(str(p) for p in objects),'-lm','-o',str(exe)],capture_output=True,text=True,encoding='utf-8',errors='replace')
    if link.returncode: raise RuntimeError(link.stdout + link.stderr)
    subprocess.run([str(exe),str(component/'tests/input_lua_test.lua')],check=True,timeout=30)
