
#include "luat_base.h"
#include "luat_log.h"

static int l_sys_run(lua_State *L) {
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
