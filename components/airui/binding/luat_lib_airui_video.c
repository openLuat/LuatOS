/*
@module  airui.video
@summary AIRUI Video 组件 Lua 绑定
@version 0.1.0
@date    2026.04.01
@tag     LUAT_USE_AIRUI

*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui.video"
#include "luat_log.h"

/**
 * 创建 Video 组件
 * @api airui.video(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 160
 * @int config.h 高度，默认 120
 * @string config.src 视频路径，必填
 * @string|int config.format 视频格式，可选，支持 "auto"、"mjpg"、"avi_mjpg"、"mp4"、"hzv"；"hzv" 为兼容别名
 * @string|int config.backend 后端类型，可选，支持 "auto"、"videoplayer"、"ffmpeg"、"platform"
 * @string|int config.decode_mode 解码模式，可选，支持 "sw"、"hw"
 * @boolean config.direct_render 是否使用独立硬件图层开窗直推，支持 MJPG / AVI-MJPG / HZV，默认 false
 * @int config.interval 播放间隔，单位毫秒，默认 33；HZV 会优先使用容器帧时长
 * @boolean config.loop 是否循环播放，默认 false
 * @boolean config.auto_play 是否创建后自动播放，默认 true
 * @function config.on_complete 播放结束回调，仅 loop=false 且读到 EOF 时触发，参数为 (self)
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Video 对象
 */
static int l_airui_video(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    lv_obj_t *video = airui_video_create_from_config(L, 1);
    if (video == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, video, AIRUI_VIDEO_MT);
    return 1;
}

static lv_obj_t *video_check(lua_State *L)
{
    return airui_check_component(L, 1, AIRUI_VIDEO_MT);
}

/**
 * Video:play()
 * @api video:play()
 * @return nil
 * @usage
 * video:play()
 */
static int l_video_play(lua_State *L)
{
    airui_video_play(video_check(L));
    return 0;
}

/**
 * Video:pause()
 * @api video:pause()
 * @return nil
 * @usage
 * video:pause()
 */
static int l_video_pause(lua_State *L)
{
    airui_video_pause(video_check(L));
    return 0;
}

/**
 * Video:stop()
 * @api video:stop()
 * @return nil
 * @usage
 * video:stop()
 */
static int l_video_stop(lua_State *L)
{
    airui_video_stop(video_check(L));
    return 0;
}

/**
 * Video:get_stats()
 * @api video:get_stats()
 * @return table 实际呈现统计：fps、total_frames、audio_pts_ms、video_pts_ms、av_delta_ms、dropped_frames、audio_underruns、clock_mode、decode_mode、playing
 */
static int l_video_get_stats(lua_State *L)
{
    airui_video_stats_t stats;

    if (airui_video_get_stats(video_check(L), &stats) != AIRUI_OK) {
        lua_pushnil(L);
        return 1;
    }

    lua_createtable(L, 0, 10);
    lua_pushnumber(L, (lua_Number)stats.fps);
    lua_setfield(L, -2, "fps");
    lua_pushinteger(L, (lua_Integer)stats.total_frames);
    lua_setfield(L, -2, "total_frames");
    lua_pushinteger(L, (lua_Integer)stats.audio_pts_ms);
    lua_setfield(L, -2, "audio_pts_ms");
    lua_pushinteger(L, (lua_Integer)stats.video_pts_ms);
    lua_setfield(L, -2, "video_pts_ms");
    lua_pushinteger(L, stats.av_delta_ms);
    lua_setfield(L, -2, "av_delta_ms");
    lua_pushinteger(L, stats.dropped_frames);
    lua_setfield(L, -2, "dropped_frames");
    lua_pushinteger(L, stats.audio_underruns);
    lua_setfield(L, -2, "audio_underruns");
    lua_pushstring(L, stats.clock_mode == 1 ? "sample-counter" : "none");
    lua_setfield(L, -2, "clock_mode");
    lua_pushstring(L, stats.decode_mode == AIRUI_VIDEO_DECODE_HW ? "hw" : "sw");
    lua_setfield(L, -2, "decode_mode");
    lua_pushboolean(L, stats.playing);
    lua_setfield(L, -2, "playing");
    return 1;
}

/**
 * Video:destroy（手动销毁）
 * @api video:destroy()
 * @return nil
 * @usage
 * video:destroy()
 */
static int l_video_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_VIDEO_MT);
}

/**
 * 注册 Video 元表
 * @param L Lua 状态
 */
void airui_register_video_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_VIDEO_MT);
    airui_component_set_metatable_gc(L);

    static const luaL_Reg methods[] = {
        {"play", l_video_play},
        {"pause", l_video_pause},
        {"stop", l_video_stop},
        {"get_stats", l_video_get_stats},
        {"destroy", l_video_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Video 创建函数（供主模块注册）
 */
int airui_video_create(lua_State *L)
{
    return l_airui_video(L);
}
