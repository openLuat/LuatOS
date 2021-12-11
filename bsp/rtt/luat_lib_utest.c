
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"

#include "rtthread.h"

#define DBG_TAG           "luat.utest"
#define DBG_LVL           DBG_LOG
#include <rtdbg.h>

static int l_utest_600_mem_check(lua_State *L) {
    // #ifdef BSP_USING_WM_LIBRARIES
    // void* ptr = 0x20028000 + 64*1024; // 当前设置的内存大小是64k, 所以从64k的位置开始测试

    // void* blank = rt_malloc(1024);
    // char* t;
    // rt_memset(blank, 0, 1024);
    // for (size_t i = 0; i < 64; i++)
    // {
    //     for (size_t j = 0; j < 1024; j++)
    //     {
    //         t = (char*)(ptr+1024*i+j);
    //         if (*t != 0) {
    //             rt_kprintf("Found Not Zero at 0x%08X\n", t);
    //             LOG_HEX("128K", 16, t, 1024);
    //             //i = 1024;
    //             break;
    //         }
    //     }

    // }
    // #endif
    return 0;
}

static int l_utest_memdump(lua_State *L) {
    void* ptr = (void*)luaL_checkinteger(L, 1);
    size_t len = luaL_optinteger(L, 2, 256);
    #if defined(RT_USING_ULOG)
    LOG_HEX("memdump", 16, ptr, len);
    #endif
    return 0;
}
#ifdef RT_USING_MEMTRACE
int memcheck(void);
static int l_utest_memcheck(lua_State *L) {
    memcheck();
    return 0;
}
#endif

//extern int mem_profiler_enable;
//static int l_utest_profiler(lua_State *L) {
//    mem_profiler_enable = luaL_optinteger(L, 1, 0);
//    return 0;
//}

#include "rotable.h"
static const rotable_Reg reg_utest[] =
{
    { "w600_mem_check" , l_utest_600_mem_check, 0},
    { "memdump", l_utest_memdump, 0},
    #ifdef RT_USING_MEMTRACE
    { "memcheck", l_utest_memcheck, 0},
//    { "profiler", l_utest_profiler},
    #endif
	{ NULL, NULL }
};

LUAMOD_API int luaopen_utest( lua_State *L ) {
    luat_newlib(L, reg_utest);
    return 1;
}
