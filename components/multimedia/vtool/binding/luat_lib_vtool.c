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
    mp4_ctx_t* ctx = luat_vtool_mp4box_create(filename, w, h, fps);
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

// 扩展支持, 写入jpeg文件为mp4的一帧
static int l_vtool_mp4write_jpeg(lua_State *L) {
    mp4_ctx_t* ctx = lua_touserdata(L, 1);
    const char* jpeg_path = luaL_checkstring(L, 2);
    int save_tmp = lua_toboolean(L, 3);
    // 首先, 解码jpeg成yuv422
    int ret = luat_vtool_jpeg_add(jpeg_path);
    lua_pushinteger(L, ret);
    return 1;
}

static int l_vtool_h264_encoder_init(lua_State *L) {
    luat_vtool_h264_encoder_init();
    lua_pushboolean(L, 1);
    return 1;
}

static int l_vtool_h264_encoder_start(lua_State *L) {
    luat_vtool_h264_encoder_start();
    lua_pushboolean(L, 1);
    return 1;
}

static int l_vtool_h264_encoder_deinit(lua_State *L) {
    luat_vtool_h264_encoder_deinit();
    lua_pushboolean(L, 1);
    return 1;
}

static const rotable_Reg_t reg_vtool[] =
{
    { "mp4create" ,         ROREG_FUNC(l_vtool_mp4create)},
    { "mp4write" ,          ROREG_FUNC(l_vtool_mp4write)},
    { "mp4close" ,          ROREG_FUNC(l_vtool_mp4close)},
    #ifdef __BK72XX__
    { "mp4write_jpeg" ,     ROREG_FUNC(l_vtool_mp4write_jpeg)},
    { "h264_encoder_init",  ROREG_FUNC(l_vtool_h264_encoder_init)},
    { "h264_encoder_start", ROREG_FUNC(l_vtool_h264_encoder_start)},
    { "h264_encoder_deinit",ROREG_FUNC(l_vtool_h264_encoder_deinit)},
    #endif
	{ NULL,                 ROREG_INT(0) }
};


LUAMOD_API int luaopen_vtool( lua_State *L ) {
    luat_newlib2(L, reg_vtool);
    return 1;
}
