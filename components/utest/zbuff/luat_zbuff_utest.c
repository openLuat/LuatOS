#include "luat_base.h"
#include <string.h>

static int run_lua_bool_expr(lua_State *L, const char *code) {
    int top = lua_gettop(L);
    int ok = 0;
    if (luaL_loadstring(L, code) == LUA_OK && lua_pcall(L, 0, 1, 0) == LUA_OK) {
        ok = lua_toboolean(L, -1) ? 1 : 0;
    }
    lua_settop(L, top);
    return ok;
}

int luat_zbuff_utest(lua_State *L, const char *case_name) {
    if (!case_name || strcmp(case_name, "rw_u8_basic") == 0) {
        return run_lua_bool_expr(
            L,
            "local b=zbuff.create(4) "
            "if not b then return false end "
            "b:write(0x12) "
            "b:seek(0) "
            "local s=b:read(1) "
            "return s and #s==1 and string.toHex(s)=='12'"
        ) ? 0 : -1;
    }
    return -1;
}

