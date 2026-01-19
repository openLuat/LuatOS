/*
@module  h264player
@summary H264 基线解码器(仅 I/P)
@version 0.1.0
@date    2026.01.16
@tag     LUAT_USE_H264PLAYER
*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_h264player.h"
#include "rotable2.h"
#include <string.h>
#ifdef LUAT_USE_ZBUFF
#include "luat_zbuff.h"
#endif

#define LUAT_LOG_TAG "h264player"
#include "luat_log.h"

#define LUAT_H264PLAYER_META "h264player_ctx"

typedef struct {
    luat_h264player_t *ctx;
    lua_State *L;
    int cb_ref;
} h264player_ud_t;

static h264player_ud_t *h264player_check_ud(lua_State *L, int idx) {
    h264player_ud_t *ud = (h264player_ud_t *)luaL_checkudata(L, idx, LUAT_H264PLAYER_META);
    if (!ud) {
        return NULL;
    }
    return ud;
}

static luat_h264player_t *h264player_check(lua_State *L, int idx) {
    h264player_ud_t *ud = h264player_check_ud(L, idx);
    return ud ? ud->ctx : NULL;
}

static void h264player_lua_frame_cb(void *userdata, const uint8_t *frame, size_t len,
                                    uint16_t width, uint16_t height, uint8_t format) {
    h264player_ud_t *ud = (h264player_ud_t *)userdata;
    if (!ud || !ud->L || ud->cb_ref == LUA_NOREF || ud->cb_ref < 0) {
        return;
    }
    lua_State *L = ud->L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ud->cb_ref);
    if (lua_isfunction(L, -1)) {
        lua_pushlstring(L, (const char *)frame, len);
        lua_pushinteger(L, width);
        lua_pushinteger(L, height);
        lua_pushinteger(L, format);
        if (lua_pcall(L, 4, 0, 0) != LUA_OK) {
            const char *msg = lua_tostring(L, -1);
            LLOGW("h264 cb error: %s", msg ? msg : "unknown");
            lua_pop(L, 1);
        }
    } else {
        lua_pop(L, 1);
    }
}

/**
创建解码器
@api h264player.create(cb)
@func cb 回调函数, 参数为 (frame, width, height, format)
@return userdata 解码器句柄
*/
static int l_h264player_create(lua_State *L) {
    int cb_ref = LUA_NOREF;
    if (lua_isfunction(L, 1)) {
        lua_pushvalue(L, 1);
        cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }

    h264player_ud_t *ud = (h264player_ud_t *)lua_newuserdata(L, sizeof(*ud));
    memset(ud, 0, sizeof(*ud));
    ud->L = L;
    ud->cb_ref = cb_ref;
    ud->ctx = luat_h264player_create(cb_ref == LUA_NOREF ? NULL : h264player_lua_frame_cb, ud);
    if (!ud->ctx) {
        if (ud->cb_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, ud->cb_ref);
        }
        lua_pushnil(L);
        return 1;
    }
    luaL_setmetatable(L, LUAT_H264PLAYER_META);
    return 1;
}

/**
释放解码器
@api h264player.release(ctx)
@userdata 解码器句柄
@return nil
*/
static int l_h264player_release(lua_State *L) {
    h264player_ud_t *ud = (h264player_ud_t *)luaL_testudata(L, 1, LUAT_H264PLAYER_META);
    if (ud && ud->ctx) {
        if (ud->cb_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, ud->cb_ref);
            ud->cb_ref = LUA_NOREF;
        }
        luat_h264player_set_callback(ud->ctx, NULL, NULL);
        luat_h264player_destroy(ud->ctx);
        ud->ctx = NULL;
    }
    return 0;
}

/**
输入 Annex-B H264 数据流(可包含 SPS/PPS/IDR)
@api h264player.feed(ctx, data)
@userdata 解码器句柄
@string/zbuff Annex-B 数据
@return boolean 成功返回 true
*/
static int l_h264player_feed(lua_State *L) {
    luat_h264player_t *ctx = h264player_check(L, 1);
    const uint8_t *data = NULL;
    size_t len = 0;
#ifdef LUAT_USE_ZBUFF
    if (lua_isuserdata(L, 2)) {
        luat_zbuff_t *buff = (luat_zbuff_t *)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
        if (buff) {
            data = buff->addr;
            len = buff->used;
        }
    }
#endif
    if (!data) {
        data = (const uint8_t *)luaL_checklstring(L, 2, &len);
    }

    LUAT_RET ret = luat_h264player_feed(ctx, data, len);
    lua_pushboolean(L, ret == LUAT_ERR_OK);
    return 1;
}

/**
获取解码帧
@api h264player.frame(ctx)
@userdata 解码器句柄
@return string 解码帧数据, 无新帧返回 nil
*/
static int l_h264player_frame(lua_State *L) {
    luat_h264player_t *ctx = h264player_check(L, 1);
    const uint8_t *out = NULL;
    size_t out_len = 0;
    if (!luat_h264player_get_frame(ctx, &out, &out_len)) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushlstring(L, (const char *)out, out_len);
    return 1;
}

/**
获取宽度
@api h264player.width(ctx)
@userdata 解码器句柄
@return int 宽度
*/
static int l_h264player_width(lua_State *L) {
    luat_h264player_t *ctx = h264player_check(L, 1);
    lua_pushinteger(L, luat_h264player_get_width(ctx));
    return 1;
}

/**
获取高度
@api h264player.height(ctx)
@userdata 解码器句柄
@return int 高度
*/
static int l_h264player_height(lua_State *L) {
    luat_h264player_t *ctx = h264player_check(L, 1);
    lua_pushinteger(L, luat_h264player_get_height(ctx));
    return 1;
}

/**
获取输出格式
@api h264player.format(ctx)
@userdata 解码器句柄
@return int 0=RGB565, 1=RGB8888
*/
static int l_h264player_format(lua_State *L) {
    luat_h264player_t *ctx = h264player_check(L, 1);
    lua_pushinteger(L, luat_h264player_get_format(ctx));
    return 1;
}

static int l_h264player_gc(lua_State *L) {
    return l_h264player_release(L);
}

static const rotable_Reg_t reg_h264player_ctx[] = {
    {"feed", ROREG_FUNC(l_h264player_feed)},
    {"frame", ROREG_FUNC(l_h264player_frame)},
    {"width", ROREG_FUNC(l_h264player_width)},
    {"height", ROREG_FUNC(l_h264player_height)},
    {"format", ROREG_FUNC(l_h264player_format)},
    {"release", ROREG_FUNC(l_h264player_release)},
    {NULL, ROREG_INT(0)}
};

static const rotable_Reg_t reg_h264player[] = {
    {"create", ROREG_FUNC(l_h264player_create)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_h264player(lua_State *L) {
    luat_newlib2(L, reg_h264player);
    luaL_newmetatable(L, LUAT_H264PLAYER_META);
    rotable2_newidx(L, reg_h264player_ctx);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, l_h264player_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);
    return 1;
}
