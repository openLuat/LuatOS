#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_malloc.h"

/*
创建一个style
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
创建一个style
@api lvgl.style_t()
@return userdata style指针
@usage
local style = lvgl.style_t()
*/
int luat_lv_style_t(lua_State *L) {
    return luat_lv_style_create(L);
}

/*
创建一个style_list
@api lvgl.style_list_create()
@return userdata style指针
@usage
local style = lvgl.style_create()
*/
int luat_lv_style_list_create(lua_State *L) {
    lv_style_list_t* style_list = (lv_style_list_t*)luat_heap_malloc(sizeof(lv_style_list_t));
    lv_style_list_init(style_list);
    lua_pushlightuserdata(L, style_list);
    return 1;
}

/*
创建一个style_list
@api lvgl.style_list_t()
@return userdata style指针
@usage
local style = lvgl.style_list_t()
*/
int luat_lv_style_list_t(lua_State *L) {
    return luat_lv_style_list_create(L);
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

/*
删除style_list,慎用,通常不会执行删除操作
@api lvgl.style_delete(style)
@userdata style指针
@usage
local style_list = lvgl.style_list_create()
-- ...
-- ...
-- lvgl.style_list_delete(style_list)
*/
int luat_lv_style_list_delete(lua_State *L) {
    lv_style_list_t* style_list = (lv_style_list_t*)lua_touserdata(L, 1);
    if (style_list != NULL) {
        luat_heap_free(style_list);
    }
    return 0;
}
