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

int luat_lv_line_set_points(lua_State *L) {
    LV_DEBUG("CALL lv_line_set_points");
    lv_obj_t* line = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t point_num = (uint16_t)luaL_checkinteger(L, 3);
    lv_point_t *point_a = (lv_point_t*)luat_heap_calloc(point_num,sizeof(lv_point_t));
    if (lua_istable(L,2)){
        for (int m = 0; m < point_num; m++) {  
            lua_pushinteger(L, m+1);
            if (LUA_TTABLE == lua_gettable(L, 2)) {
                    lua_geti(L,-1,1);
                    point_a[m].x=luaL_checkinteger(L,-1);
                    lua_pop(L, 1);
                    lua_geti(L,-1,2);
                    point_a[m].y=luaL_checkinteger(L,-1);
                    lua_pop(L, 1);
            }
            lua_pop(L, 1);
        }
    }
    lv_line_set_points(line,point_a,point_num);
    //luat_heap_free(point_a);
    return 0;
}

