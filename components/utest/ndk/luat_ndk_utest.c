#include "luat_base.h"
#include "luat_log.h"
#include <string.h>

#define LUAT_LOG_TAG "ndk_utest"
#include "luat_log.h"

static int run_lua_bool_expr(lua_State *L, const char *code) {
    int top = lua_gettop(L);
    int ok = 0;
    if (luaL_loadstring(L, code) != LUA_OK) {
        LLOGE("ndk utest syntax error: %s", lua_tostring(L, -1));
    } else if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
        LLOGE("ndk utest runtime error: %s", lua_tostring(L, -1));
    } else {
        ok = lua_toboolean(L, -1) ? 1 : 0;
    }
    lua_settop(L, top);
    return ok;
}

int luat_ndk_utest(lua_State *L, const char *case_name) {
    if (!case_name || strcmp(case_name, "lifecycle_basic") == 0) {
        return run_lua_bool_expr(L,
            "local ctx = ndk.rv32i(\"/luadb/baremetal.bin\", 32768, 1024)\n"
            "if not ctx then return false end\n"
            "local info = ndk.info(ctx)\n"
            "if info.mem <= 0 or info.exchange <= 0 or info.image <= 0 then return false end\n"
            "if info.running ~= false then return false end\n"
            "if info.mcause ~= 0 or info.mtval ~= 0 then return false end\n"
            "local ok, ret = ndk.exec(ctx, {steps=100000})\n"
            "if not ok then return false end\n"
            "local data = ndk.getData(ctx, 16, 0)\n"
            "if type(data) ~= \"string\" or #data ~= 16 then return false end\n"
            "return ndk.stop(ctx, 1000)"
        ) ? 0 : -1;
    }
    if (strcmp(case_name, "invalid_image") == 0) {
        return run_lua_bool_expr(L,
            "local ctx, err = ndk.rv32i(\"/luadb/nonexistent.bin\", 32768, 1024)\n"
            "if ctx ~= nil then return false end\n"
            "if type(err) ~= \"string\" or #err == 0 then return false end\n"
            "collectgarbage(\"collect\")\n"
            "return true"
        ) ? 0 : -1;
    }
    if (strcmp(case_name, "isa_option_rv32imf") == 0) {
        return run_lua_bool_expr(L,
            "local ctx = ndk.rv32i(\"/luadb/baremetal.bin\", 32768, 1024, {isa=\"rv32imf\"})\n"
            "if not ctx then return false end\n"
            "local info = ndk.info(ctx)\n"
            "if info.isa ~= \"rv32imf\" then return false end\n"
            "if info.flen ~= 32 then return false end\n"
            "if info.fcsr ~= 0 then return false end\n"
            "if info.frm ~= 0 then return false end\n"
            "if info.fflags ~= 0 then return false end\n"
            "return true"
        ) ? 0 : -1;
    }
    if (strcmp(case_name, "exec_fadd") == 0) {
        return run_lua_bool_expr(L,
            "local ctx = ndk.rv32i(\"/luadb/baremetal_fadd.bin\", 32768, 1024, {isa=\"rv32imf\"})\n"
            "if not ctx then return false end\n"
            "local ok, ret = ndk.exec(ctx, {steps=100000})\n"
            "if not ok then return false end\n"
            "return ret == 0x40400000"
        ) ? 0 : -1;
    }
    return -1;
}
