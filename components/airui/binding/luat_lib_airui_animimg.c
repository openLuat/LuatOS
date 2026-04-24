/*
@module  airui.animimg
@summary AIRUI AnimImg 组件 Lua 绑定
@version 0.1.0
@date    2026.03.27
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui.animimg"
#include "luat_log.h"

#define AIRUI_ANIMIMG_MT "airui.animimg"

/**
 * 创建 AnimImg 组件
 * @api airui.animimg(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 100
 * @table config.frames 帧图片路径数组，必填
 * @int config.duration 动画总时长，单位毫秒，默认 1000
 * @boolean config.loop 是否循环播放，默认 true
 * @boolean config.auto_play 是否创建后自动播放，默认 true
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata AnimImg 对象
 */
static int l_airui_animimg(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    lv_obj_t *animimg = airui_animimg_create_from_config(L, 1);
    if (animimg == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, animimg, AIRUI_ANIMIMG_MT);
    return 1;
}

static lv_obj_t *animimg_check(lua_State *L)
{
    return airui_check_component(L, 1, AIRUI_ANIMIMG_MT);
}

/**
 * AnimImg:play()
 * @api animimg:play()
 * @return nil
 * @usage
 * anim:play()
 */
static int l_animimg_play(lua_State *L)
{
    airui_animimg_play(animimg_check(L));
    return 0;
}

/**
 * AnimImg:pause()
 * @api animimg:pause()
 * @return nil
 * @usage
 * anim:pause()
 */
static int l_animimg_pause(lua_State *L)
{
    airui_animimg_pause(animimg_check(L));
    return 0;
}

/**
 * AnimImg:stop()
 * @api animimg:stop()
 * @return nil
 * @usage
 * anim:stop()
 */
static int l_animimg_stop(lua_State *L)
{
    airui_animimg_stop(animimg_check(L));
    return 0;
}

/**
 * AnimImg:set_src(frames)
 * @api animimg:set_src(frames)
 * @table frames 帧图片路径数组
 * @return nil
 * @usage
 * anim:set_src({"/luadb/frame1.png", "/luadb/frame2.png"})
 */
static int l_animimg_set_src(lua_State *L)
{
    lv_obj_t *obj = animimg_check(L);
    luaL_checktype(L, 2, LUA_TTABLE);
    if (airui_animimg_set_src(obj, L, 2) != AIRUI_OK) {
        luaL_error(L, "airui.animimg:set_src expects a non-empty frames table of strings");
    }
    return 0;
}

/**
 * AnimImg:destroy（手动销毁）
 * @api animimg:destroy()
 * @return nil
 * @usage
 * anim:destroy()
 */
static int l_animimg_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_ANIMIMG_MT);
}

/**
 * 注册 AnimImg 元表
 * @param L Lua 状态
 */
void airui_register_animimg_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_ANIMIMG_MT);

    static const luaL_Reg methods[] = {
        {"play", l_animimg_play},
        {"pause", l_animimg_pause},
        {"stop", l_animimg_stop},
        {"set_src", l_animimg_set_src},
        {"destroy", l_animimg_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * AnimImg 创建函数（供主模块注册）
 */
int airui_animimg_create(lua_State *L)
{
    return l_airui_animimg(L);
}
