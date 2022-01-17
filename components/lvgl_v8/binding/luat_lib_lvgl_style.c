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
创建一个style
@api lvgl.style_t()
@return userdata style指针
@usage
local style = lvgl.style_t()
lvgl.style_init(style)
*/
int luat_lv_style_t(lua_State *L) {
    lv_style_t* style = (lv_style_t*)luat_heap_malloc(sizeof(lv_style_t));
    lua_pushlightuserdata(L, style);
    return 1;
}

/*
创建一个style并初始化
@api lvgl.style_create()
@return userdata style指针
@usage
local style = lvgl.style_create()
*/
int luat_lv_style_create(lua_State *L) {
    lv_style_t* style = (lv_style_t*)luat_heap_malloc(sizeof(lv_style_t));
    lv_style_init(style);
    lua_pushlightuserdata(L, style);
    return 1;
}

/*
删除style,慎用,通常不会执行删除操作
@api lvgl.style_delete(style)
@userdata style指针
@usage
local style = lvgl.style_create()
-- ...
-- ...
-- lvgl.style_delete(style)
*/
int luat_lv_style_delete(lua_State *L) {
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    if (style != NULL) {
        luat_heap_free(style);
    }
    return 0;
}
