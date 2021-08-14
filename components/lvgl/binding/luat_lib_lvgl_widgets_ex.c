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
    return 0;
}

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

/*line*/
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

/*gauge*/
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

/*btnmatrix*/
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

/*dropdown*/
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

/*roller*/
int luat_lv_roller_get_selected_str(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_selected_str");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    char buf[32] = {0};
    lv_roller_get_selected_str(roller, buf, 32);
    buf[31] = 0x00;
    lua_pushlstring(L, buf, strlen(buf));
    return 1;
}

/*canvas*/
//  void lv_canvas_set_buffer(lv_obj_t* canvas, void* buf, lv_coord_t w, lv_coord_t h, lv_img_cf_t cf)
int luat_lv_canvas_set_buffer(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_set_buffer");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    void *buf = NULL;
     if (lua_isuserdata(L, 2)) {
        luat_zbuff* cbuff = (luat_zbuff *)luaL_checkudata(L, 2, "ZBUFF*");
        //printf("cbuff_len: %d\r\n",cbuff->len);
        buf = cbuff->addr;
    }
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 4);
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 5);
    lv_canvas_set_buffer(canvas ,buf ,w ,h ,cf);
    return 0;
}
