
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"

static int l_timer_mdelay(lua_State *L) {
    lua_gettop(L);
    if (lua_isinteger(L, 1)) {
        lua_Integer ms = luaL_checkinteger(L, 1);
        if (ms)
            luat_timer_mdelay(ms);
    }
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_timer[] =
{
    { "mdelay", l_timer_mdelay, 0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_timer( lua_State *L ) {
    rotable_newlib(L, reg_timer);
    return 1;
}
