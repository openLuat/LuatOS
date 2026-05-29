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

int luat_cjson_utest(lua_State *L, const char *case_name) {
    if (!case_name || strcmp(case_name, "encode_decode_basic") == 0) {
        return run_lua_bool_expr(
            L,
            "local s=json.encode({a=1,b='x'}) "
            "local t=json.decode(s) "
            "return t and t.a==1 and t.b=='x'"
        ) ? 0 : -1;
    }
    return -1;
}

