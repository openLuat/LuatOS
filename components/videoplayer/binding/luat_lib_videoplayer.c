
/*
@module  videoplayer
@summary 视频播放库
@catalog 多媒体
@version 1.0
@date    2026.03.20
@demo    videoplayer
@tag LUAT_USE_VIDEOPLAYER
@usage
-- 打开MJPG视频文件, 逐帧解码后绘制到LCD
local player = videoplayer.open("/sdcard/video.mjpg")
if not player then
    log.error("videoplayer", "打开视频失败")
    return
end
-- 开启调试信息
videoplayer.debug(true)
-- 获取视频信息
local info = videoplayer.info(player)
log.info("videoplayer", "分辨率", info.width, info.height)
-- 逐帧解码并显示
while true do
    local ok, err = videoplayer.draw_frame(player, 0, 0)
    if err == "eof" then break end
    sys.wait(33)  -- 约30fps
end
videoplayer.close(player)
*/

#ifdef LUAT_BUILD
#include "luat_base.h"
#include "luat_malloc.h"
#define VP_LIB_MALLOC luat_heap_malloc
#define VP_LIB_FREE   luat_heap_free
#else
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <stdlib.h>
#define VP_LIB_MALLOC malloc
#define VP_LIB_FREE   free
#endif

#include "luat_videoplayer.h"
#include <string.h>

#define LUAT_LOG_TAG "videoplayer"
#ifdef LUAT_BUILD
#include "luat_log.h"
#endif

/* Metatable name for videoplayer userdata */
#define VP_META "videoplayer.ctx"

/* Wrapper for player context Lua userdata */
typedef struct {
    luat_vp_ctx_t *ctx;
} LuaVideoPlayer;

/*
打开视频文件, 返回播放器对象
@api videoplayer.open(path)
@string path 视频文件路径, 当前支持MJPG格式, 例如 "/sdcard/video.mjpg"
@return userdata 播放器对象, 失败时返回nil和错误信息
@usage
-- 打开MJPG格式视频文件
local player, err = videoplayer.open("/sdcard/video.mjpg")
if not player then
    log.error("videoplayer", "打开失败", err)
    return
end
*/
static int l_videoplayer_open(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);

    LuaVideoPlayer *ud = (LuaVideoPlayer *)lua_newuserdata(L, sizeof(LuaVideoPlayer));
    ud->ctx = luat_videoplayer_open(path);
    if (!ud->ctx) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, "failed to open video file");
        return 2;
    }

    luaL_getmetatable(L, VP_META);
    lua_setmetatable(L, -2);
    return 1;
}

/*
关闭播放器, 释放所有资源
@api videoplayer.close(player)
@userdata player videoplayer.open()返回的播放器对象
@return nil 无返回值
@usage
videoplayer.close(player)
player = nil
*/
static int l_videoplayer_close(lua_State *L) {
    LuaVideoPlayer *ud = (LuaVideoPlayer *)luaL_checkudata(L, 1, VP_META);
    if (ud->ctx) {
        luat_videoplayer_close(ud->ctx);
        ud->ctx = NULL;
    }
    return 0;
}

/* __gc metamethod */
static int l_videoplayer_gc(lua_State *L) {
    return l_videoplayer_close(L);
}

/*
读取并解码下一帧视频, 返回帧数据表
@api videoplayer.read_frame(player)
@userdata player videoplayer.open()返回的播放器对象
@return table 成功返回帧数据表(含width/height/data字段), 到达文件末尾时返回nil和"eof", 出错返回nil和错误信息
@usage
-- 逐帧读取视频
while true do
    local frame, err = videoplayer.read_frame(player)
    if err == "eof" then
        log.info("videoplayer", "播放完毕")
        break
    end
    if frame then
        log.info("videoplayer", "帧大小", frame.width, frame.height)
        -- frame.data 为RGB565格式的原始像素数据(字符串), 长度 = width * height * 2
    end
end
*/
static int l_videoplayer_read_frame(lua_State *L) {
    LuaVideoPlayer *ud = (LuaVideoPlayer *)luaL_checkudata(L, 1, VP_META);
    if (!ud->ctx) {
        lua_pushnil(L);
        lua_pushstring(L, "player closed");
        return 2;
    }

    luat_vp_frame_t frame;
    memset(&frame, 0, sizeof(frame));

    int ret = luat_videoplayer_read_frame(ud->ctx, &frame);
    if (ret == LUAT_VP_ERR_EOF) {
        lua_pushnil(L);
        lua_pushstring(L, "eof");
        return 2;
    }
    if (ret != LUAT_VP_OK) {
        lua_pushnil(L);
        lua_pushstring(L, "decode error");
        return 2;
    }

    /* Build result table */
    lua_newtable(L);

    lua_pushinteger(L, frame.width);
    lua_setfield(L, -2, "width");

    lua_pushinteger(L, frame.height);
    lua_setfield(L, -2, "height");

    /* Push RGB565 data as Lua string (2 bytes per pixel) */
    size_t data_size = (size_t)frame.width * frame.height * 2;
    if (frame.data && data_size > 0 && data_size / 2 / frame.height == frame.width) {
        lua_pushlstring(L, (const char *)frame.data, data_size);
    } else {
        lua_pushstring(L, "");
    }
    lua_setfield(L, -2, "data");

    luat_videoplayer_frame_free(&frame);
    return 1;
}

/* ---- LCD frame output (only when LCD support is compiled in) ---- */
#ifdef LUAT_USE_LCD
#include "luat_lcd.h"

/*
读取下一帧并绘制到默认LCD屏幕, 需开启LUAT_USE_LCD
@api videoplayer.draw_frame(player, x, y)
@userdata player videoplayer.open()返回的播放器对象
@int x 显示起始X坐标
@int y 显示起始Y坐标
@return boolean 成功返回true, 到达文件末尾返回nil和"eof", 失败返回nil和错误信息
@usage
-- 逐帧解码并显示到LCD左上角
while true do
    local ok, err = videoplayer.draw_frame(player, 0, 0)
    if err == "eof" then break end
    sys.wait(33)  -- 约30fps
end
*/
static int l_videoplayer_draw_frame(lua_State *L) {
    LuaVideoPlayer *ud = (LuaVideoPlayer *)luaL_checkudata(L, 1, VP_META);
    if (!ud->ctx) {
        lua_pushnil(L);
        lua_pushstring(L, "player closed");
        return 2;
    }

    int16_t x = (int16_t)luaL_checkinteger(L, 2);
    int16_t y = (int16_t)luaL_checkinteger(L, 3);

    luat_lcd_conf_t *lcd = luat_lcd_get_default();
    if (!lcd) {
        lua_pushnil(L);
        lua_pushstring(L, "no lcd");
        return 2;
    }

    luat_vp_frame_t frame;
    memset(&frame, 0, sizeof(frame));

    int ret = luat_videoplayer_read_frame(ud->ctx, &frame);
    if (ret == LUAT_VP_ERR_EOF) {
        lua_pushnil(L);
        lua_pushstring(L, "eof");
        return 2;
    }
    if (ret != LUAT_VP_OK) {
        lua_pushnil(L);
        lua_pushstring(L, "decode error");
        return 2;
    }

    luat_lcd_draw(lcd, x, y,
                  (int16_t)(x + frame.width - 1),
                  (int16_t)(y + frame.height - 1),
                  (luat_color_t *)frame.data);

    luat_videoplayer_frame_free(&frame);
    lua_pushboolean(L, 1);
    return 1;
}
#endif /* LUAT_USE_LCD */

/*
获取视频信息
@api videoplayer.info(player)
@userdata player videoplayer.open()返回的播放器对象
@return table 成功返回信息表(含width/height/format/decode_mode字段), 失败返回nil
@usage
local info = videoplayer.info(player)
if info then
    log.info("videoplayer", "分辨率", info.width, info.height)
    log.info("videoplayer", "格式", info.format)
    log.info("videoplayer", "解码模式", info.decode_mode)
end
*/
static int l_videoplayer_info(lua_State *L) {
    LuaVideoPlayer *ud = (LuaVideoPlayer *)luaL_checkudata(L, 1, VP_META);
    if (!ud->ctx) {
        lua_pushnil(L);
        return 1;
    }

    luat_vp_info_t info;
    memset(&info, 0, sizeof(info));
    int ret = luat_videoplayer_get_info(ud->ctx, &info);
    if (ret != LUAT_VP_OK) {
        lua_pushnil(L);
        return 1;
    }

    lua_newtable(L);

    lua_pushinteger(L, info.width);
    lua_setfield(L, -2, "width");

    lua_pushinteger(L, info.height);
    lua_setfield(L, -2, "height");

    lua_pushinteger(L, (int)info.format);
    lua_setfield(L, -2, "format");

    lua_pushinteger(L, (int)info.decode_mode);
    lua_setfield(L, -2, "decode_mode");

    return 1;
}

/*
设置解码模式, 支持软件解码和硬件解码两种模式, 可在播放过程中随时切换
@api videoplayer.set_decode_mode(player, mode)
@userdata player videoplayer.open()返回的播放器对象
@int mode 解码模式, videoplayer.DECODE_SW为软件解码, videoplayer.DECODE_HW为硬件解码
@return boolean 成功返回true, 失败返回false
@usage
-- 切换到硬件解码
videoplayer.set_decode_mode(player, videoplayer.DECODE_HW)
-- 切换回软件解码
videoplayer.set_decode_mode(player, videoplayer.DECODE_SW)
*/
static int l_videoplayer_set_decode_mode(lua_State *L) {
    LuaVideoPlayer *ud = (LuaVideoPlayer *)luaL_checkudata(L, 1, VP_META);
    if (!ud->ctx) {
        lua_pushboolean(L, 0);
        return 1;
    }

    int mode = luaL_checkinteger(L, 2);
    int ret = luat_videoplayer_set_decode_mode(ud->ctx,
                                               (luat_vp_decode_mode_t)mode);
    lua_pushboolean(L, ret == LUAT_VP_OK ? 1 : 0);
    return 1;
}

/*
设置调试信息输出开关, 开启后将打印解码过程、帧大小等关键信息
@api videoplayer.debug(on_off)
@boolean on_off true开启调试输出, false关闭(默认)
@return nil 无返回值
@usage
-- 开启调试, 将打印帧信息等
videoplayer.debug(true)
-- 关闭调试
videoplayer.debug(false)
*/
static int l_videoplayer_debug(lua_State *L) {
    luat_videoplayer_set_debug(lua_toboolean(L, 1));
    return 0;
}

/* ---- Module registration ---- */

#include "rotable2.h"

static const rotable_Reg_t reg_videoplayer[] = {
    { "open",             ROREG_FUNC(l_videoplayer_open)},
    { "close",            ROREG_FUNC(l_videoplayer_close)},
    { "read_frame",       ROREG_FUNC(l_videoplayer_read_frame)},
#ifdef LUAT_USE_LCD
    { "draw_frame",       ROREG_FUNC(l_videoplayer_draw_frame)},
#endif
    { "info",             ROREG_FUNC(l_videoplayer_info)},
    { "set_decode_mode",  ROREG_FUNC(l_videoplayer_set_decode_mode)},
    { "debug",            ROREG_FUNC(l_videoplayer_debug)},

    //@const DECODE_SW number 软件解码模式
    { "DECODE_SW",        ROREG_INT(LUAT_VP_DECODE_SW)},
    //@const DECODE_HW number 硬件解码模式
    { "DECODE_HW",        ROREG_INT(LUAT_VP_DECODE_HW)},

    //@const FMT_MJPG number MJPG视频格式
    { "FMT_MJPG",         ROREG_INT(LUAT_VP_FMT_MJPG)},
    //@const FMT_AVI_MJPG number AVI+MJPG视频格式(预留)
    { "FMT_AVI_MJPG",     ROREG_INT(LUAT_VP_FMT_AVI_MJPG)},
    //@const FMT_MP4_H264 number MP4+H264视频格式(预留)
    { "FMT_MP4_H264",     ROREG_INT(LUAT_VP_FMT_MP4_H264)},

    { NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_videoplayer(lua_State *L) {
    /* Create metatable for player userdata */
    luaL_newmetatable(L, VP_META);
    lua_pushcfunction(L, l_videoplayer_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_videoplayer_close);
    lua_setfield(L, -2, "__close");
    lua_pop(L, 1);

    luat_newlib2(L, reg_videoplayer);
    return 1;
}
