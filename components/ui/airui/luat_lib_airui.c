#include "luat_base.h"

#include "luat_malloc.h"
#include "luat_airui.h"

static int l_airui_load_buff(lua_State *L) {
    size_t len;
    const char* backend = luaL_checkstring(L, 1);
    const char* screen_name = luaL_checkstring(L, 2);
    const char* buff = luaL_checklstring(L, 3, &len);

    luat_airui_ctx_t *ctx = NULL;
    int ret = luat_airui_load_buff(&ctx, 0, screen_name, buff, len);
    if (ret == 0) {
        lua_pushlightuserdata(L, ctx);
        return 1;
    }
    else {
        lua_pushnil(L);
        lua_pushinteger(L, ret);
        return 2;
    }
    return 0;
}

static int l_airui_load_file(lua_State *L) {
    return 0;
}


static int l_airui_get_scr(lua_State *L) {
    luat_airui_ctx_t *ctx = lua_touserdata(L, 1);
    if (ctx == NULL)
        return 0;
    lua_pushlightuserdata(L, ctx->scr);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_airui[] =
{
    { "load_buff" ,             ROREG_FUNC(l_airui_load_buff)},
    { "load_file" ,             ROREG_FUNC(l_airui_load_file)},
    { "get_scr" ,               ROREG_FUNC(l_airui_get_scr)},
    { NULL,                     ROREG_INT(0)}
};

LUAMOD_API int luaopen_airui( lua_State *L ) {
    luat_newlib2(L, reg_airui);
    return 1;
}
