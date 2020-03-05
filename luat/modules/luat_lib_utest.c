
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"

#include "rtthread.h"

// #define LOG_TAG              "luat.utest"
// #define LOG_LVL              LOG_LVL_DBG
// #include "ulog.h"

static int l_utest_600_mem_check(lua_State *L) {
    void* ptr = 0x20028000 + 64*1024; // 当前设置的内存大小是64k, 所以从64k的位置开始测试
    
    void* blank = rt_malloc(1024);
    char* t;
    rt_memset(blank, 0, 1024);
    for (size_t i = 0; i < 64; i++)
    {
        //if (rt_memcmp(blank, ptr+i*1024, 1024)) {
        //    rt_kprintf("Found Not Zero at 0x%08X\n", ptr+i*1024);
        //    LOG_HEX("128K", 16, ptr+i*1024, 1024);
        //    break;
        //}
        for (size_t j = 0; j < 1024; j++)
        {
            t = (char*)(ptr+1024*i+j);
            if (*t != 0) {
                rt_kprintf("Found Not Zero at 0x%08X\n", t);
                //LOG_HEX("128K", 16, t, 1024);
                i = 1024;
                break;
            }
        }
        
    }
    
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_utest[] =
{
    { "w600_mem_check" , l_utest_600_mem_check, 0},
	{ NULL, NULL }
};

LUAMOD_API int luaopen_utest( lua_State *L ) {
    rotable_newlib(L, reg_utest);
    return 1;
}
