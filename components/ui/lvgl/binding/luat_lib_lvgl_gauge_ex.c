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
    uint8_t needle_cnt = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t *colors = (lv_color_t*)luat_heap_calloc(needle_cnt,sizeof(lv_color_t));
    if (lua_istable(L,3)){
        for (int i = 0; i < needle_cnt; i++) {  
            lua_pushinteger(L, i+1);   
            if (LUA_TNUMBER == lua_gettable(L, 3)) {
                colors[i].full = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
        }
    }
    lv_gauge_set_needle_count(gauge, needle_cnt,colors);
    //luat_heap_free(colors);
    return 0;
}
