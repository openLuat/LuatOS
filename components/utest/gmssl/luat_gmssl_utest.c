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

int luat_gmssl_utest(lua_State *L, const char *case_name) {
    if (!case_name || strcmp(case_name, "sm3_known_vector") == 0) {
        return run_lua_bool_expr(
            L,
            "local v = gmssl.sm3('lqlq666lqlq946') "
            "return v and string.toHex(v) == "
            "'E64FD76F4078E51DCA428323D3FADBD5D52723BBF1379184650DA5CE6002B2BF'"
        ) ? 0 : -1;
    }
    return -1;
}

