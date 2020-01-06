
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"

static int l_msgbus_version(lua_State *L) {
    lua_pushstring(L, LUAT_VERSION);
    return 1;
}

static const luaL_Reg reg_msgbus[] =
{
    { "version" , l_msgbus_version },
	{ NULL, NULL }
};

LUAMOD_API int luaopen_msgbus( lua_State *L ) {
    luat_msgbus_init();
    luaL_newlib(L, reg_msgbus);
    return 1;
}
