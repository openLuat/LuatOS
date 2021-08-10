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

int luat_lv_msgbox_add_btns(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_add_btns");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    char **btn_mapaction;
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
    lv_msgbox_add_btns(mbox,btn_mapaction);
    return 1;
}

int luat_lv_tileview_set_valid_positions(lua_State *L) {
    LV_DEBUG("CALL lv_tileview_set_valid_positions");
    lv_obj_t* tileview = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t valid_pos_cnt = (uint16_t)luaL_checkinteger(L, 3);
    lv_point_t *valid_pos;
    valid_pos = (lv_point_t*)luat_heap_calloc(valid_pos_cnt,sizeof(lv_point_t));
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
    luat_heap_free(valid_pos);
    return 1;
}

int luat_lv_calendar_set_highlighted_dates(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_set_highlighted_dates");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t date_num = (uint16_t)luaL_checkinteger(L, 3);

    lv_calendar_date_t *highlighted;
    highlighted = (lv_calendar_date_t*)luat_heap_calloc(date_num,sizeof(lv_calendar_date_t));
    if (lua_istable(L,2)){
        for (int m = 0; m < date_num; m++) {  
            lua_pushinteger(L, m+1);   
            if (LUA_TUSERDATA == lua_gettable(L, 2)) {
                    lv_calendar_date_t *date_t = lua_touserdata(L,-1);
                    highlighted[m].year = date_t->year;
                    highlighted[m].month = date_t->month;
                    highlighted[m].day = date_t->day;
            }
            lua_pop(L, 1);
        }
    }
    lv_calendar_set_highlighted_dates(calendar,highlighted,date_num);
    luat_heap_free(highlighted);
    return 1;
}

