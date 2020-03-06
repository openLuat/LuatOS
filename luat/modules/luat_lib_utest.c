
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"

#include "rtthread.h"

// #define LOG_TAG              "luat.utest"
// #define LOG_LVL              LOG_LVL_DBG
// #include "ulog.h"

static int l_utest_600_mem_check(lua_State *L) {
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
