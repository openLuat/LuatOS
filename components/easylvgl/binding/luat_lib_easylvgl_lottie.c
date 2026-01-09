/*
@module  easylvgl.lottie
@summary EasyLVGL Lottie 动画绑定
@version 0.1.0
@date    2026.01.09
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"

#define LUAT_LOG_TAG "easylvgl.lottie"
#include "luat_log.h"

#define EASYLVGL_LOTTIE_MT "easylvgl.lottie"

/**
 * 创建 Lottie 组件
 * @api easylvgl.lottie(config)
 * @table config Lottie 配置表
 * @string config.src 本地或资源路径，用于加载动画文件
 * @string config.data 内联动画字符串（优先于 src）
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 100
 * @boolean config.loop 是否循环播放，默认 true
 * @boolean config.auto_play 是否自动播放，默认 true
 * @number config.speed 播放速率，>0
 * @function config.on_ready 播放准备完成回调
 * @function config.on_complete 播放完成回调
 * @userdata config.parent 父对象，可选
 * @return userdata Lottie 对象，失败返回 nil
 */
static int l_easylvgl_lottie(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    lv_obj_t *lottie = easylvgl_lottie_create_from_config(L, 1);
    if (lottie == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, lottie, EASYLVGL_LOTTIE_MT);
    return 1;
}

static lv_obj_t *lottie_check(lua_State *L)
{
    return easylvgl_check_component(L, 1, EASYLVGL_LOTTIE_MT);
}

/**
 * Lottie:play() 动画播放
 * @api lottie:play()
 * @return nil
 */
static int l_lottie_play(lua_State *L)
{
    easylvgl_lottie_play(lottie_check(L));
    return 0;
}

/**
 * Lottie:pause() 动画暂停
 * @api lottie:pause()
 * @return nil
 */
static int l_lottie_pause(lua_State *L)
{
    easylvgl_lottie_pause(lottie_check(L));
    return 0;
}

/**
 * Lottie:stop() 动画停止
 * @api lottie:stop()
 * @return nil
 */
static int l_lottie_stop(lua_State *L)
{
    easylvgl_lottie_stop(lottie_check(L));
    return 0;
}

/**
 * Lottie:set_speed(speed) 设置播放速度
 * @api lottie:set_speed(speed)
 * @number speed 播放速度，>0
 * @return nil
 */
static int l_lottie_set_speed(lua_State *L)
{
    lv_obj_t *obj = lottie_check(L);
    float speed = (float)luaL_checknumber(L, 2);
    easylvgl_lottie_set_speed(obj, speed);
    return 0;
}

/**
 * Lottie:set_loop(loop) 设置是否循环
 * @api lottie:set_loop(loop)
 * @boolean loop 是否循环
 * @return nil
 */
static int l_lottie_set_loop(lua_State *L)
{
    lv_obj_t *obj = lottie_check(L);
    bool loop = lua_toboolean(L, 2);
    easylvgl_lottie_set_loop(obj, loop);
    return 0;
}

/**
 * Lottie:set_progress(progress) 设置进度
 * @api lottie:set_progress(progress)
 * @number progress 进度 [0,1]
 * @return nil
 */
static int l_lottie_set_progress(lua_State *L)
{
    lv_obj_t *obj = lottie_check(L);
    float progress = (float)luaL_checknumber(L, 2);
    easylvgl_lottie_set_progress(obj, progress);
    return 0;
}

/**
 * Lottie:set_src(path or {path=...,data=...}) 设置源
 * @api lottie:set_src(source)
 * @param source 可用字符串路径或包含 path/data 的表
 * @return nil
 */
static int l_lottie_set_src(lua_State *L)
{
    lv_obj_t *obj = lottie_check(L);

    if (lua_type(L, 2) == LUA_TSTRING) {
        const char *path = lua_tostring(L, 2);
        easylvgl_lottie_set_src_file(obj, path);
        return 0;
    }

    if (lua_type(L, 2) == LUA_TTABLE) {
        lua_getfield(L, 2, "path");
        const char *path = lua_tostring(L, -1);
        lua_pop(L, 1);

        if (path != NULL && path[0] != '\0') {
            easylvgl_lottie_set_src_file(obj, path);
            return 0;
        }

        lua_getfield(L, 2, "data");
        size_t len = 0;
        const char *data = NULL;
        if (lua_type(L, -1) == LUA_TSTRING) {
            data = lua_tolstring(L, -1, &len);
        }
        lua_pop(L, 1);

        if (data != NULL && len > 0) {
            easylvgl_lottie_set_src_data(obj, data, len);
            return 0;
        }
    }

    luaL_error(L, "easylvgl.lottie:set_src expects string path or table {path=...,data=...}");
    return 0;
}

/**
 * Lottie:destroy() 销毁
 * @api lottie:destroy()
 * @return nil
 */
static int l_lottie_destroy(lua_State *L)
{
    lv_obj_t *obj = lottie_check(L);
    int ret = easylvgl_lottie_destroy(obj);
    if (ret != EASYLVGL_OK) {
        LLOGE("easylvgl.lottie:destroy failed: %d", ret);
    }
    return 0;
}

void easylvgl_register_lottie_meta(lua_State *L)
{
    luaL_newmetatable(L, EASYLVGL_LOTTIE_MT);

    static const luaL_Reg methods[] = {
        {"play", l_lottie_play},
        {"pause", l_lottie_pause},
        {"stop", l_lottie_stop},
        {"set_src", l_lottie_set_src},
        {"set_speed", l_lottie_set_speed},
        {"set_loop", l_lottie_set_loop},
        {"set_progress", l_lottie_set_progress},
        {"destroy", l_lottie_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int easylvgl_lottie_create(lua_State *L)
{
    return l_easylvgl_lottie(L);
}

