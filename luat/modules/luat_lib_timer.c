
#include "luat_base.h"
#include "luat_log.h"

static int l_timer_start(lua_State *L) {
    return 0;
}

static int l_timer_stop(lua_State *L) {
    return 0;
}

static const luaL_Reg reg_timer[] =
{
    { "start" , l_timer_start },
    { "stop" , l_timer_stop },
	{ NULL, NULL }
};

LUAMOD_API int luaopen_timer( lua_State *L ) {
    luaL_newlib(L, reg_timer);
    return 1;
}
