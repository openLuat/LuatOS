/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_malloc.h"

/*
创建一个lv_draw_mask_radius_param_t
@api lvgl.draw_mask_radius_param_t()
@return userdata lv_draw_mask_radius_param_t指针
@usage
local radius = lvgl.draw_mask_radius_param_t()
*/
int luat_lv_draw_mask_radius_param_t(lua_State *L) {
    lv_draw_mask_radius_param_t* radius = (lv_draw_mask_radius_param_t*)luat_heap_malloc(sizeof(lv_draw_mask_radius_param_t));
    lua_pushlightuserdata(L, radius);
    return 1;
}

/*
释放一个lv_draw_mask_radius_param_t
@api lvgl.draw_mask_radius_param_t_free(radius)
@usage
local lvgl.draw_mask_radius_param_t_free(radius)
*/
int luat_lv_draw_mask_radius_param_t_free(lua_State *L) {
    lv_draw_mask_radius_param_t* radius = (lv_draw_mask_radius_param_t*)lua_touserdata(L, 1);
    if (radius != NULL) {
        luat_heap_free(radius);
    }
    return 0;
}

/*
创建一个lv_draw_mask_line_param_t
@api lvgl.draw_mask_line_param_t()
@return userdata lv_draw_mask_line_param_t指针
@usage
local line = lvgl.draw_mask_line_param_t()
*/
int luat_lv_draw_mask_line_param_t(lua_State *L) {
    lv_draw_mask_line_param_t* line = (lv_draw_mask_line_param_t*)luat_heap_malloc(sizeof(lv_draw_mask_line_param_t));
    lua_pushlightuserdata(L, line);
    return 1;
}

/*
释放一个lv_draw_mask_line_param_t
@api lvgl.draw_mask_line_param_t_free(line)
@usage
local lvgl.draw_mask_line_param_t_free(line)
*/
int luat_lv_draw_mask_line_param_t_free(lua_State *L) {
    lv_draw_mask_line_param_t* line = (lv_draw_mask_line_param_t*)lua_touserdata(L, 1);
    if (line != NULL) {
        luat_heap_free(line);
    }
    return 0;
}

/*
创建一个lv_draw_mask_fade_param_t
@api lvgl.draw_mask_fade_param_t()
@return userdata lv_draw_mask_fade_param_t指针
@usage
local fade = lvgl.draw_mask_fade_param_t()
*/
int luat_lv_draw_mask_fade_param_t(lua_State *L) {
    lv_draw_mask_fade_param_t* fade = (lv_draw_mask_fade_param_t*)luat_heap_malloc(sizeof(lv_draw_mask_fade_param_t));
    lua_pushlightuserdata(L, fade);
    return 1;
}

/*
释放一个lv_draw_mask_fade_param_t
@api lvgl.draw_mask_fade_param_t_free(fade)
@usage
local lvgl.draw_mask_fade_param_t_free(fade)
*/
int luat_lv_draw_mask_fade_param_t_free(lua_State *L) {
    lv_draw_mask_fade_param_t* fade = (lv_draw_mask_fade_param_t*)lua_touserdata(L, 1);
    if (fade != NULL) {
        luat_heap_free(fade);
    }
    return 0;
}


