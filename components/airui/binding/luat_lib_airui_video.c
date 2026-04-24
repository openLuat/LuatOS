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
 * @string|int config.format 视频格式，可选，支持 "auto"、"mjpg"、"avi_mjpg"、"mp4"
 * @string|int config.backend 后端类型，可选，支持 "auto"、"videoplayer"、"ffmpeg"、"platform"
 * @string|int config.decode_mode 解码模式，可选，支持 "sw"、"hw"
 * @int config.interval 播放间隔，单位毫秒，默认 33
 * @boolean config.loop 是否循环播放，默认 false
 * @boolean config.auto_play 是否创建后自动播放，默认 true
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

    static const luaL_Reg methods[] = {
        {"play", l_video_play},
        {"pause", l_video_pause},
        {"stop", l_video_stop},
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
