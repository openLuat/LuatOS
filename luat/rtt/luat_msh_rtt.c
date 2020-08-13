
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "luat.msh"
#include "luat_log.h"

#include "rtthread.h"
#include <rtdevice.h>

#ifdef FINSH_USING_MSH

extern lua_State *L;

static void loadstr(int argc, char**argv) {
    if (argc < 2)
        return;
    int re = luaL_dostring(L, argv[1]);
    if (re) {
        LLOGE("luaL_dostring  return re != 0\n");
        LLOGE(lua_tostring(L, -1));
    }
};

MSH_CMD_EXPORT(loadstr , run lua code);

#endif

