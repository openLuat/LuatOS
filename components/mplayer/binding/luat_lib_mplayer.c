/*
 * luat_lib_mplayer.c - mplayer Lua 绑定层
 * 仅负责 Lua 参数解析与返回值组装; 媒体类型分派全部在 luat_mplayer.c。
 */

#include "luat_base.h"
#include "luat_mplayer.h"

#define LUAT_LOG_TAG "mplayer"
#include "luat_log.h"

#include <string.h>

/* Metatable name for mplayer userdata */
#define MP4_MOVIE_META "mplayer.media"

/* Wrapper for player context Lua userdata */
typedef struct {
    luat_mplayer_t *m;   /* 由 luat_mplayer_open 创建, close 释放 */
} LuaMediaPlayer;

/*
打开音视频文件, 返回播放器对象
@api mplayer.open(path)
@string path 媒体文件路径, 支持 mp4/mp3 等格式, 例如 "/sdcard/video.mp4" 或 "/sdcard/music.mp3"
@return userdata 播放器对象, 失败时返回nil和错误信息
@usage
local player = mplayer.open("/sdcard/video.mp4")
local music  = mplayer.open("/sdcard/music.mp3")
*/
static int l_mplayer_open(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);

    LuaMediaPlayer *ud = (LuaMediaPlayer *)lua_newuserdata(L, sizeof(LuaMediaPlayer));
    memset(ud, 0, sizeof(LuaMediaPlayer));

    ud->m = luat_mplayer_open(path);
    if (!ud->m) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, "decoder not support");
        return 2;
    }

    luaL_getmetatable(L, MP4_MOVIE_META);
    lua_setmetatable(L, -2);
    return 1;
}

/*
关闭播放器, 释放所有资源
@api mplayer.close(player)
@userdata player mplayer.open()返回的播放器对象
@return nil 无返回值
@usage
mplayer.close(player)
player = nil
*/
static int l_mplayer_close(lua_State *L) {
    LuaMediaPlayer *ud = (LuaMediaPlayer *)luaL_checkudata(L, 1, MP4_MOVIE_META);
    if (ud->m) {
        luat_mplayer_close(ud->m);
        ud->m = NULL;
    }
    return 0;
}

/* __gc metamethod */
static int l_mplayer_gc(lua_State *L) {
    return l_mplayer_close(L);
}

/*
开始播放
@api mplayer.play(player)
@userdata player mplayer.open()返回的播放器对象
@return boolean 成功返回true, 失败返回false
@usage
mplayer.play(player)
*/
static int l_mplayer_play(lua_State *L) {
    LuaMediaPlayer *ud = (LuaMediaPlayer *)luaL_checkudata(L, 1, MP4_MOVIE_META);
    if (!ud->m) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "player closed");
        return 2;
    }
    lua_pushboolean(L, luat_mplayer_play(ud->m) == 0);
    return 1;
}

/*
暂停播放
@api mplayer.pause(player)
@userdata player mplayer.open()返回的播放器对象
@return boolean 成功返回true, 失败返回false
@usage
mplayer.pause(player)
*/
static int l_mplayer_pause(lua_State *L) {
    LuaMediaPlayer *ud = (LuaMediaPlayer *)luaL_checkudata(L, 1, MP4_MOVIE_META);
    if (!ud->m) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, luat_mplayer_pause(ud->m) == 0);
    return 1;
}

/*
恢复播放
@api mplayer.resume(player)
@userdata player mplayer.open()返回的播放器对象
@return boolean 成功返回true, 失败返回false
@usage
mplayer.resume(player)
*/
static int l_mplayer_resume(lua_State *L) {
    LuaMediaPlayer *ud = (LuaMediaPlayer *)luaL_checkudata(L, 1, MP4_MOVIE_META);
    if (!ud->m) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, luat_mplayer_resume(ud->m) == 0);
    return 1;
}

/*
停止播放
@api mplayer.stop(player)
@userdata player mplayer.open()返回的播放器对象
@return boolean 成功返回true, 失败返回false
@usage
mplayer.stop(player)
*/
static int l_mplayer_stop(lua_State *L) {
    LuaMediaPlayer *ud = (LuaMediaPlayer *)luaL_checkudata(L, 1, MP4_MOVIE_META);
    if (!ud->m) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, luat_mplayer_stop(ud->m) == 0);
    return 1;
}

/*
检查是否正在播放
@api mplayer.is_playing(player)
@userdata player mplayer.open()返回的播放器对象
@return boolean 正在播放返回true, 否则返回false
@usage
if mplayer.is_playing(player) then
    log.info("mplayer", "播放中...")
end
*/
static int l_mplayer_is_playing(lua_State *L) {
    LuaMediaPlayer *ud = (LuaMediaPlayer *)luaL_checkudata(L, 1, MP4_MOVIE_META);
    if (!ud->m) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, luat_mplayer_is_playing(ud->m) == 1);
    return 1;
}

/*
检查是否暂停
@api mplayer.is_paused(player)
@userdata player mplayer.open()返回的播放器对象
@return boolean 暂停返回true, 否则返回false
@usage
if mplayer.is_paused(player) then
    log.info("mplayer", "已暂停")
end
*/
static int l_mplayer_is_paused(lua_State *L) {
    LuaMediaPlayer *ud = (LuaMediaPlayer *)luaL_checkudata(L, 1, MP4_MOVIE_META);
    if (!ud->m) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, luat_mplayer_is_paused(ud->m) == 1);
    return 1;
}

/*
获取媒体信息
@api mplayer.info(player)
@userdata player mplayer.open()返回的播放器对象
@return table 成功返回信息表, 失败返回nil
@usage
local info = mplayer.info(player)
log.info("mplayer", "帧率", info.fps)
log.info("mplayer", "音频采样率", info.audio_sample_rate)
*/
static int l_mplayer_info(lua_State *L) {
    LuaMediaPlayer *ud = (LuaMediaPlayer *)luaL_checkudata(L, 1, MP4_MOVIE_META);
    if (!ud->m) {
        lua_pushnil(L);
        return 1;
    }

    luat_mplayer_info_t info;
    if (luat_mplayer_info(ud->m, &info) != 0) {
        lua_pushnil(L);
        return 1;
    }

    lua_newtable(L);

    lua_pushinteger(L, (int)info.media_type);
    lua_setfield(L, -2, "type");

    lua_pushinteger(L, info.fps);
    lua_setfield(L, -2, "fps");

    lua_pushinteger(L, info.width);
    lua_setfield(L, -2, "width");

    lua_pushinteger(L, info.height);
    lua_setfield(L, -2, "height");

    lua_pushinteger(L, info.audio_sample_rate);
    lua_setfield(L, -2, "audio_sample_rate");

    lua_pushinteger(L, info.audio_channels);
    lua_setfield(L, -2, "audio_channels");

    lua_pushinteger(L, info.timestamp_ms);
    lua_setfield(L, -2, "timestamp_ms");

    const char *status_str = "unknown";
    switch (info.status) {
        case LUAT_MPLAYER_STAT_STOP:  status_str = "stop";  break;
        case LUAT_MPLAYER_STAT_PLAY:  status_str = "play";  break;
        case LUAT_MPLAYER_STAT_PAUSE: status_str = "pause"; break;
        case LUAT_MPLAYER_STAT_EOS:   status_str = "eos";   break;
        default:                      status_str = "unknown"; break;
    }
    lua_pushstring(L, status_str);
    lua_setfield(L, -2, "status");

    return 1;
}

/* ---- Module registration ---- */

#include "rotable2.h"

static const rotable_Reg_t reg_mplayer[] = {
    { "open",           ROREG_FUNC(l_mplayer_open)},
    { "close",          ROREG_FUNC(l_mplayer_close)},
    { "play",           ROREG_FUNC(l_mplayer_play)},
    { "pause",          ROREG_FUNC(l_mplayer_pause)},
    { "resume",         ROREG_FUNC(l_mplayer_resume)},
    { "stop",           ROREG_FUNC(l_mplayer_stop)},
    { "is_playing",     ROREG_FUNC(l_mplayer_is_playing)},
    { "is_paused",      ROREG_FUNC(l_mplayer_is_paused)},
    { "info",           ROREG_FUNC(l_mplayer_info)},

    /* Status constants */
    //@const STAT_STOP number 停止状态
    { "STAT_STOP",      ROREG_INT(LUAT_MPLAYER_STAT_STOP)},
    //@const STAT_PLAY number 播放状态
    { "STAT_PLAY",      ROREG_INT(LUAT_MPLAYER_STAT_PLAY)},
    //@const STAT_PAUSE number 暂停状态
    { "STAT_PAUSE",     ROREG_INT(LUAT_MPLAYER_STAT_PAUSE)},
    //@const STAT_EOS number 播放结束状态
    { "STAT_EOS",       ROREG_INT(LUAT_MPLAYER_STAT_EOS)},

    { NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_mplayer(lua_State *L) {
    /* Create metatable for player userdata */
    luaL_newmetatable(L, MP4_MOVIE_META);
    lua_pushcfunction(L, l_mplayer_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_mplayer_close);
    lua_setfield(L, -2, "__close");
    lua_pop(L, 1);

    luat_newlib2(L, reg_mplayer);
    return 1;
}