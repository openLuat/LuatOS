#include "luat_base.h"
#include "luat_httpsrv.h"

#define LUAT_LOG_TAG "httpsrv"
#include "luat_log.h"

static int l_httpsrv_start(lua_State *L) {
    int port = luaL_checkinteger(L, 1);
    if (!lua_isfunction(L, 2)) {
        LLOGW("httpsrv need callback function!!!");
        return 0;
    }
    lua_pushvalue(L, 2);
    int lua_ref_id = luaL_ref(L, LUA_REGISTRYINDEX);
    luat_httpsrv_ctx_t ctx = {
        .port = port,
        .lua_ref_id = lua_ref_id
    };
    int ret = luat_httpsrv_start(&ctx);
    return 0;
}

static int l_httpsrv_stop(lua_State *L) {
    int port = luaL_checkinteger(L, 1);
    luat_httpsrv_stop(port);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_httpsrv[] =
{
    {"start",        ROREG_FUNC(l_httpsrv_start) },
    {"stop",         ROREG_FUNC(l_httpsrv_stop) },
	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_httpsrv( lua_State *L ) {
    luat_newlib2(L, reg_httpsrv);
    return 1;
}