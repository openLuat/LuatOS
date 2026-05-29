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

int luat_crypto_utest(lua_State *L, const char *case_name) {
    if (!case_name || strcmp(case_name, "sha1_known_vector") == 0) {
        return run_lua_bool_expr(
            L,
            "return crypto.sha1('str123') == '3F7773379D580530FDEA7060EFCA215438383369'"
        ) ? 0 : -1;
    }
    return -1;
}

