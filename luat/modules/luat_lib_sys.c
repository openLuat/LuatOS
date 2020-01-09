
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"

static void l_message (const char *pname, const char *msg) {
  if (pname) lua_writestringerror("%s: ", pname);
  lua_writestringerror("%s\n", msg);
}

static int report (lua_State *L, int status) {
  if (status != LUA_OK) {
    const char *msg = lua_tostring(L, -1);
    l_message("LUAT", msg);
    lua_pop(L, 1);  /* remove message */
  }
  return status;
}

static int l_default_handler(lua_State *L) {
    luat_printf("l_default_handler\n");    
    return 0;
}

static int l_sys_run(lua_State *L) {
    struct rtos_msg msg;
    int re;
    while (1) {
        re = luat_msgbus_get(&msg, 0);
        if (re == 0) {
            luat_printf("luat_msgbus_get!!!\n");
            if (msg.handler == NULL) {
                luat_printf("luat_msgbus_get!!! msg.handler == NULL\n");
                continue;
            }
            //lua_pushcfunction(L, msg.handler);
            lua_pushcfunction(L, &l_default_handler);
            lua_pushlightuserdata(L, msg.ptr);
            int re = lua_pcall(L, 1, 0, 0);
            report(L, re);
        }
        else {
            luat_timer_mdelay(1); // 暂缓1ms
        }
    }
    return 0;
}


static const luaL_Reg reg_sys[] =
{
    { "run" , l_sys_run },
	{ NULL, NULL }
};

LUAMOD_API int luaopen_sys( lua_State *L ) {
    luaL_newlib(L, reg_sys);
    return 1;
}
