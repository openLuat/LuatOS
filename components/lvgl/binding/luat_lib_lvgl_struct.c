#include "luat_base.h"
#include "luat_lvgl.h"

#include "lvgl.h"

#define META_LV_ANIM "LV_ANIM*"
#define META_LV_AREA "LV_AREA*"


//---------------------------------------------
/*
创建一个anim
@api lvgl.anim_t()
@return userdata anim指针
@usage
local anim = lvgl.anim_t()
*/
int luat_lv_struct_anim_t(lua_State *L) {
    lua_newuserdata(L, sizeof(lv_anim_t));
    luaL_setmetatable(L, META_LV_ANIM);
    return 1;
}


static int _lvgl_struct_anim_t_newindex(lua_State *L) {
    lv_anim_t* anim = (lv_anim_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("start", key)) {
        anim->start = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("end", key)) {
        anim->end = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("current", key)) {
        anim->current = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("time", key)) {
        anim->time = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("act_time", key)) {
        anim->act_time = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("playback_delay", key)) {
        anim->playback_delay = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("playback_time", key)) {
        anim->playback_time = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("repeat_delay", key)) {
        anim->repeat_delay = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("repeat_cnt", key)) {
        anim->repeat_cnt = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("early_apply", key)) {
        anim->early_apply = luaL_optinteger(L, 3, 0);
    }
    return 0;
}

//---------------------------------------------
/*
创建一个area
@api lvgl.anim_t()
@return userdata area指针
@usage
local area = lvgl.area_t()
*/
int luat_lv_struct_area_t(lua_State *L) {
    lua_newuserdata(L, sizeof(lv_area_t));
    luaL_setmetatable(L, META_LV_AREA);
    return 1;
}


static int _lvgl_struct_area_t_newindex(lua_State *L) {
    lv_area_t* area = (lv_area_t*)lua_touserdata(L, 1);
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("x1", key)) {
        area->x1 = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("x2", key)) {
        area->x2 = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("y1", key)) {
        area->y1 = luaL_optinteger(L, 3, 0);
    }
    else if (!strcmp("y2", key)) {
        area->y2 = luaL_optinteger(L, 3, 0);
    }
    return 0;
}


//--------------------------------------------


static void luat_lvgl_struct_init(lua_State *L) {

    // lv_anim*
    luaL_newmetatable(L, META_LV_ANIM);
    lua_pushcfunction(L, _lvgl_struct_anim_t_newindex);
    lua_setfield( L, -1, "__newindex" );
    lua_pop(L, 1);

    // lv_area
    luaL_newmetatable(L, META_LV_AREA);
    lua_pushcfunction(L, _lvgl_struct_area_t_newindex);
    lua_setfield( L, -1, "__newindex" );
    lua_pop(L, 1);
}