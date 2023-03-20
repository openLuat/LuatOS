#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "luat_profiler.h"

#define LUAT_LOG_TAG "PRO"
#include "luat_log.h"

int luat_profiler_memdebug;
luat_profiler_mem_t profiler_memregs[LUAT_PROFILER_MEMDEBUG_ADDR_COUNT];

static int l_profiler_start(lua_State *L) {
    (void)L;
    luat_profiler_start();
    return 0;
}

static int l_profiler_stop(lua_State *L) {
    (void)L;
    luat_profiler_stop();
    return 0;
}

static int l_profiler_print(lua_State *L) {
    (void)L;
    luat_profiler_print();
    return 0;
}

static int l_profiler_memdebug(lua_State *L) {
    luat_profiler_memdebug = lua_toboolean(L, 1);
    LLOGD("memdebug %d", luat_profiler_memdebug);
    size_t total;
    size_t used;
    size_t max_used;
    luat_meminfo_luavm(&total, &used, &max_used);
    LLOGD("mem.lua %d %d %d", total, used, max_used);
    luat_meminfo_sys(&total, &used, &max_used);
    LLOGD("mem.sys %d %d %d", total, used, max_used);
    if (luat_profiler_memdebug == 0) {
        for (size_t i = 0; i < LUAT_PROFILER_MEMDEBUG_ADDR_COUNT; i++)
        {
            if (profiler_memregs[i].addr) {
                LLOGD("leak %08X %d", profiler_memregs[i].addr, profiler_memregs[i].len);
            }
        }
        
    }
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_profiler[] =
{
    { "start" ,        ROREG_FUNC(l_profiler_start)},
    { "stop" ,         ROREG_FUNC(l_profiler_stop)},
    { "print",         ROREG_FUNC(l_profiler_print)},
    { "memdebug",      ROREG_FUNC(l_profiler_memdebug)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_profiler( lua_State *L ) {
    luat_newlib2(L, reg_profiler);
    return 1;
}
