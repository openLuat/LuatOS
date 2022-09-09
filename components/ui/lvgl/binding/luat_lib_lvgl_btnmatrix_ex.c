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

int luat_lv_btnmatrix_set_map(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_map");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    char **map;
    if (lua_istable(L,2)){
        int n = luaL_len(L, 2);
        map = (char**)luat_heap_calloc(n,sizeof(char*));
        for (int i = 0; i < n; i++) {  
            lua_pushnumber(L, i+1);
            if (LUA_TSTRING == lua_gettable(L, 2)) {
                char* map_str = luaL_checkstring(L, -1);
                LV_LOG_INFO("%d: [%s]", i, map_str);
                map[i] =luat_heap_calloc(1,strlen(map_str)+1);
                memcpy(map[i],map_str,strlen(map_str)+1);
            };
            lua_pop(L, 1);
        }  
    } else {
        return 0;
    }
    lv_btnmatrix_set_map(btnm,map);
    // luat_heap_free(map);
    return 0;
}

