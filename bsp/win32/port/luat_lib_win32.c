
#include "luat_base.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "win32"
#include "luat_log.h"

extern int win32_argc;
extern char** win32_argv;

static int l_win32_args(lua_State *L) {
    int index = luaL_optinteger(L, 1, 2);
    lua_newtable(L);
    if (win32_argc > index) {
        for (size_t i = index; i < win32_argc; i++)
        {
            //printf("args[%d] %s\n", i, win32_argv[i]);
            lua_pushinteger(L, i + 1 - index);
            lua_pushstring(L, win32_argv[i]);
            lua_settable(L, -3);
        }
    }

    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_win32[] =
{
    { "args",      l_win32_args,   0},
	{ NULL,                 NULL,   0}
};

LUAMOD_API int luaopen_win32( lua_State *L ) {
    luat_newlib(L, reg_win32);
    return 1;
}
