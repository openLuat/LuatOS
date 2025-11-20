#include "luat_base.h"

#include "luat_vtool_mp4box.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "vtool"
#include "luat_log.h"

#include "rotable.h"

static int l_vtool_mp4create(lua_State *L) {
    const char* filename = luaL_checkstring(L, 1);
    size_t w = luaL_checkinteger(L, 2);
    size_t h = luaL_checkinteger(L, 3);
    size_t fps = luaL_checkinteger(L, 4);
    mp4_ctx_t* ctx = luat_vtool_mp4box_creare(filename, w, h, fps);
    if (ctx == NULL) {
        return 0;
    }
    lua_pushlightuserdata(L, ctx);
    return 1;
}

static int l_vtool_mp4write(lua_State *L) {
    mp4_ctx_t* ctx = lua_touserdata(L, 1);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 2, &len);
    if (len == 0) {
        return 0;
    }
    int ret = luat_vtool_mp4box_write_frame(ctx, (uint8_t*)data, len);
    lua_pushinteger(L, ret);
    return 1;
}

static int l_vtool_mp4close(lua_State *L) {
    mp4_ctx_t* ctx = lua_touserdata(L, 1);
    int ret = luat_vtool_mp4box_close(ctx);
    lua_pushinteger(L, ret);
    return 1;
}

static const rotable_Reg_t reg_vtool[] =
{
    { "mp4create" ,     ROREG_FUNC(l_vtool_mp4create)},
    { "mp4write" ,      ROREG_FUNC(l_vtool_mp4write)},
    { "mp4close" ,      ROREG_FUNC(l_vtool_mp4close)},
	{ NULL,             ROREG_INT(0) }
};


LUAMOD_API int luaopen_vtool( lua_State *L ) {
    luat_newlib2(L, reg_vtool);
    return 1;
}
