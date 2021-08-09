/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"
#include "luat_malloc.h"

int luat_lv_gauge_set_needle_count(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_set_needle_count");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t needle_cnt = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_color_t *colors;
    colors = (lv_color_t*)luat_heap_calloc(needle_cnt,sizeof(lv_color_t));
    for(int i=0; i<needle_cnt; i++){
        lv_color_t _color;
        _color.full = luaL_checkinteger(L, i+3);
        colors[i]=_color;
    }
    lv_gauge_set_needle_count(gauge, needle_cnt,colors);
    luat_heap_free(colors);
    return 1;
}

