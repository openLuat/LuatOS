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

int luat_lv_calendar_set_highlighted_dates(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_set_highlighted_dates");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t date_num = (uint16_t)luaL_checkinteger(L, 3);
    lv_calendar_date_t *highlighted = (lv_calendar_date_t*)luat_heap_calloc(date_num,sizeof(lv_calendar_date_t));
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
    //luat_heap_free(highlighted);
    return 0;
}


