#include "luat_base.h"
#include <fenv.h>
#include <string.h>

#include "rotable2.h"

static int l_hostfenv_get(lua_State *L) {
    int mode = fegetround();
    switch (mode) {
    case FE_TONEAREST:
        lua_pushstring(L, "nearest");
        break;
    case FE_UPWARD:
        lua_pushstring(L, "upward");
        break;
    case FE_DOWNWARD:
        lua_pushstring(L, "downward");
        break;
    case FE_TOWARDZERO:
        lua_pushstring(L, "towardzero");
        break;
    default:
        lua_pushnil(L);
        break;
    }
    return 1;
}

static int l_hostfenv_set(lua_State *L) {
    const char *mode_name = luaL_checkstring(L, 1);
    int mode = 0;

    if (strcmp(mode_name, "nearest") == 0) {
        mode = FE_TONEAREST;
    }
    else if (strcmp(mode_name, "upward") == 0) {
        mode = FE_UPWARD;
    }
    else if (strcmp(mode_name, "downward") == 0) {
        mode = FE_DOWNWARD;
    }
    else if (strcmp(mode_name, "towardzero") == 0) {
        mode = FE_TOWARDZERO;
    }
    else {
        return luaL_error(L, "unsupported rounding mode: %s", mode_name);
    }

    lua_pushboolean(L, fesetround(mode) == 0);
    return 1;
}

static int l_hostfenv_getflags(lua_State *L) {
    lua_pushinteger(L, fetestexcept(FE_ALL_EXCEPT));
    return 1;
}

static int l_hostfenv_clearflags(lua_State *L) {
    lua_pushboolean(L, feclearexcept(FE_ALL_EXCEPT) == 0);
    return 1;
}

static const rotable_Reg_t reg_hostfenv[] = {
    { "get", ROREG_FUNC(l_hostfenv_get) },
    { "set", ROREG_FUNC(l_hostfenv_set) },
    { "getflags", ROREG_FUNC(l_hostfenv_getflags) },
    { "clearflags", ROREG_FUNC(l_hostfenv_clearflags) },
    { "FLAG_INEXACT", ROREG_INT(FE_INEXACT) },
    { NULL, ROREG_INT(0) }
};

LUAMOD_API int luaopen_hostfenv(lua_State *L) {
    luat_newlib2(L, reg_hostfenv);
    return 1;
}
