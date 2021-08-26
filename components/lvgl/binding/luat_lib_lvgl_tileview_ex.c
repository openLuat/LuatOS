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

int luat_lv_tileview_set_valid_positions(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_set_valid_positions");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t valid_pos_cnt = (uint16_t)luaL_checkinteger(L, 3);
    lv_point_t *valid_pos = (lv_point_t*)luat_heap_calloc(valid_pos_cnt,sizeof(lv_point_t));
    if (lua_istable(L,2)){
        for (int m = 0; m < valid_pos_cnt; m++) {  
            lua_pushinteger(L, m+1);
            if (LUA_TTABLE == lua_gettable(L, 2)) {
                    lua_geti(L,-1,1);
                    valid_pos[m].x=luaL_checkinteger(L,-1);
                    lua_pop(L, 1);
                    lua_geti(L,-1,2);
                    valid_pos[m].y=luaL_checkinteger(L,-1);
                    lua_pop(L, 1);
            }
            lua_pop(L, 1);
        }
    }
    lv_tileview_set_valid_positions(tileview,valid_pos,valid_pos_cnt);
    //luat_heap_free(valid_pos);
    return 0;
}

