/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
@demo lvgl
@tag LUAT_USE_LVGL
*/

#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_malloc.h"

#if LV_USE_ANIMATION
/*
创建并初始化一个anim
@api lvgl.anim_create()
@return userdata anim指针
@usage
local anim = lvgl.anim_create()
*/
int luat_lv_anim_create(lua_State *L) {
    lv_anim_t* anim = (lv_anim_t*)luat_heap_malloc(sizeof(lv_anim_t));
    lv_anim_init(anim);
    lua_pushlightuserdata(L, anim);
    return 1;
}

/*
释放一个anim
@api lvgl.anim_free(anim)
@usage
local lvgl.anim_free(anim)
*/
int luat_lv_anim_free(lua_State *L) {
    lv_anim_t* anim = (lv_anim_t*)lua_touserdata(L, 1);
    if (anim != NULL) {
        luat_heap_free(anim);
    }
    return 0;
}

/*
创建一个lv_anim_path_t
@api lvgl.anim_path_t()
@return userdata lv_anim_path_t指针
@usage
local anim_path_t = lvgl.anim_path_t()
*/
int luat_lv_anim_path_t(lua_State *L) {
    lv_anim_path_t* anim_path_t = (lv_anim_path_t*)luat_heap_malloc(sizeof(lv_anim_path_t));
    lua_pushlightuserdata(L, anim_path_t);
    return 1;
}

/*
释放一个lv_anim_path_t
@api lvgl.anim_path_t_free(anim_path_t)
@usage
local lvgl.anim_path_t_free(anim_path_t)
*/
int luat_lv_anim_path_t_free(lua_State *L) {
    lv_anim_path_t* anim_path_t = (lv_anim_path_t*)lua_touserdata(L, 1);
    if (anim_path_t != NULL) {
        luat_heap_free(anim_path_t);
    }
    return 0;
}

/*
设置动画路径方式
@api lvgl.anim_set_path_str(anim, tp)
@userdata 动画指针
@string 类型, 支持 linear/ease_in/ease_out/ease_in_out/overshoot/bounce/step
@return nil 无返回值
*/
int luat_lv_anim_set_path_str(lua_State *L) {
    lv_anim_t* anim = lua_touserdata(L, 1);
    if (anim == NULL) {
        LLOGW("obj is NULL when set event cb");
        return 0;
    }
    const char* tp = luaL_checkstring(L, 2);
    lv_anim_path_t path;
    lv_anim_path_init(&path);
    if (!strcmp("linear", tp)) {
        lv_anim_path_set_cb(&path, lv_anim_path_linear);
    }
    else if (!strcmp("ease_in", tp)) {
        lv_anim_path_set_cb(&path, lv_anim_path_ease_in);
    }
    else if (!strcmp("ease_out", tp)) {
        lv_anim_path_set_cb(&path, lv_anim_path_ease_out);
    }
    else if (!strcmp("ease_in_out", tp)) {
        lv_anim_path_set_cb(&path, lv_anim_path_ease_in_out);
    }
    else if (!strcmp("overshoot", tp)) {
        lv_anim_path_set_cb(&path, lv_anim_path_overshoot);
    }
    else if (!strcmp("bounce", tp)) {
        lv_anim_path_set_cb(&path, lv_anim_path_bounce);
    }
    else if (!strcmp("step", tp)) {
        lv_anim_path_set_cb(&path, lv_anim_path_step);
    }
    else {
        //lv_anim_path_set_cb(&path, NULL);
        return 0;
    }
    lv_anim_set_path(anim, &path);
    return 0;
}

#endif
