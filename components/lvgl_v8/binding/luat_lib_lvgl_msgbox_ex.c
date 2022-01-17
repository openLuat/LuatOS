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

int luat_lv_msgbox_create(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_add_btns");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    const char *txt = luaL_checkstring(L, 2);
    const char *title = luaL_checkstring(L, 3);
    char **btn_mapaction = NULL;
    if (lua_istable(L,4)){
        int n = luaL_len(L, 4);
        btn_mapaction = (char**)luat_heap_calloc(n,sizeof(char*));
        for (int i = 0; i < n; i++) {  
            lua_pushnumber(L, i+1);
            if (LUA_TSTRING == lua_gettable(L, 4)) {
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
    bool close_btn = (bool)lua_toboolean(L, 5);
    obj = lv_msgbox_create(obj, txt, title, btn_mapaction, close_btn);
    if (obj)
    {
        lua_pushlightuserdata(L, obj);
        return 1;
    }
    return 0;
}

