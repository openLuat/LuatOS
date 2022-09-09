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

int luat_lv_dropdown_get_selected_str(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_get_selected_str");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t buf_size = (uint32_t)luaL_checkinteger(L, 2);
    char *buf = (char*)luat_heap_calloc(buf_size,sizeof(char));
    lv_dropdown_get_selected_str(ddlist, buf, buf_size);
    lua_pushstring(L, buf);
    luat_heap_free(buf);
    return 1;
}

int luat_lv_dropdown_set_symbol(lua_State *L) {
    LV_DEBUG("CALL lv_dropdown_set_symbol");
    lv_obj_t* ddlist = (lv_obj_t*)lua_touserdata(L, 1);
    if(lua_isstring(L, 2)){
        char* symbol = (char*)luaL_checkstring(L, 2);
        lv_dropdown_set_symbol(ddlist ,symbol);
    }
    else
        lv_dropdown_set_symbol(ddlist ,NULL);
    return 1;
}
