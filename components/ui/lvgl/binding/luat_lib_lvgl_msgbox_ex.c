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
#include "luat_zbuff.h"

int luat_lv_msgbox_add_btns(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_add_btns");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    char **btn_mapaction = NULL;
    if (lua_istable(L,2)){
        int n = luaL_len(L, 2);
        btn_mapaction = (char**)luat_heap_calloc(n,sizeof(char*));
        for (int i = 0; i < n; i++) {  
            lua_pushnumber(L, i+1);
            if (LUA_TSTRING == lua_gettable(L, 2)) {
                char* btn_mapaction_str = luaL_checkstring(L, -1);
                LV_LOG_INFO("%d: %s",i,btn_mapaction_str);
                btn_mapaction[i] =luat_heap_calloc(1,strlen(btn_mapaction_str)+1);
                memcpy(btn_mapaction[i],btn_mapaction_str,strlen(btn_mapaction_str)+1);
                };
            lua_pop(L, 1);
        }  
    }
    if (btn_mapaction == NULL)
        return 0;
    lv_msgbox_add_btns(mbox, btn_mapaction);
    return 0;
}

