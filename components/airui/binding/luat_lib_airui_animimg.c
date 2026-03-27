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

static int l_animimg_play(lua_State *L)
{
    airui_animimg_play(animimg_check(L));
    return 0;
}

static int l_animimg_pause(lua_State *L)
{
    airui_animimg_pause(animimg_check(L));
    return 0;
}

static int l_animimg_stop(lua_State *L)
{
    airui_animimg_stop(animimg_check(L));
    return 0;
}

static int l_animimg_set_src(lua_State *L)
{
    lv_obj_t *obj = animimg_check(L);
    luaL_checktype(L, 2, LUA_TTABLE);
    if (airui_animimg_set_src(obj, L, 2) != AIRUI_OK) {
        luaL_error(L, "airui.animimg:set_src expects a non-empty frames table of strings");
    }
    return 0;
}

static int l_animimg_destroy(lua_State *L)
{
    lv_obj_t *obj = animimg_check(L);
    int ret = airui_animimg_destroy(obj);
    if (ret != AIRUI_OK) {
        LLOGE("airui.animimg:destroy failed: %d", ret);
    }

    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_ANIMIMG_MT);
    if (ud != NULL) {
        ud->obj = NULL;
    }
    return 0;
}

void airui_register_animimg_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_ANIMIMG_MT);

    static const luaL_Reg methods[] = {
        {"play", l_animimg_play},
        {"pause", l_animimg_pause},
        {"stop", l_animimg_stop},
        {"set_src", l_animimg_set_src},
        {"destroy", l_animimg_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_animimg_create(lua_State *L)
{
    return l_airui_animimg(L);
}
