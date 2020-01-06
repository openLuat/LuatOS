
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"

static int l_sys_run(lua_State *L) {
    rtos_msg msg;
    int re;
    while (1) {
        re = luat_msgbus_get(&msg, 0);
        if (re == 0) {
            msg.handler(L, msg.ptr);
        }
        else {
            luat_sys_mdelay(1); // 暂缓1ms
        }
    }
    return 0;
}

static int l_sys_mdelay(lua_State *L) {
    size_t ms = luaL_checkinteger(L, 1);
    if (ms > 0)
        luat_sys_mdelay(ms);
    return 0;
}

static const luaL_Reg reg_sys[] =
{
    { "run" , l_sys_run },
    { "mdelay" , l_sys_mdelay },
	{ NULL, NULL }
};

LUAMOD_API int luaopen_sys( lua_State *L ) {
    luaL_newlib(L, reg_sys);
    return 1;
}
