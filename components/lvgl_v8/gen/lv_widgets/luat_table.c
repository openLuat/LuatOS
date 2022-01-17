
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_table_create(lv_obj_t* parent)
int luat_lv_table_create(lua_State *L) {
    LV_DEBUG("CALL lv_table_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_table_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_table_set_cell_value(lv_obj_t* obj, uint16_t row, uint16_t col, char* txt)
int luat_lv_table_set_cell_value(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_cell_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    char* txt = (char*)luaL_checkstring(L, 4);
    lv_table_set_cell_value(obj ,row ,col ,txt);
    return 0;
}

//  void lv_table_set_row_cnt(lv_obj_t* obj, uint16_t row_cnt)
int luat_lv_table_set_row_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_row_cnt");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row_cnt = (uint16_t)luaL_checkinteger(L, 2);
    lv_table_set_row_cnt(obj ,row_cnt);
    return 0;
}

//  void lv_table_set_col_cnt(lv_obj_t* obj, uint16_t col_cnt)
int luat_lv_table_set_col_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_col_cnt");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t col_cnt = (uint16_t)luaL_checkinteger(L, 2);
    lv_table_set_col_cnt(obj ,col_cnt);
    return 0;
}

//  void lv_table_set_col_width(lv_obj_t* obj, uint16_t col_id, lv_coord_t w)
int luat_lv_table_set_col_width(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_col_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t col_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 3);
    lv_table_set_col_width(obj ,col_id ,w);
    return 0;
}

//  void lv_table_add_cell_ctrl(lv_obj_t* obj, uint16_t row, uint16_t col, lv_table_cell_ctrl_t ctrl)
int luat_lv_table_add_cell_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_table_add_cell_ctrl");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    lv_table_cell_ctrl_t ctrl = (lv_table_cell_ctrl_t)luaL_checkinteger(L, 4);
    lv_table_add_cell_ctrl(obj ,row ,col ,ctrl);
    return 0;
}

//  void lv_table_clear_cell_ctrl(lv_obj_t* obj, uint16_t row, uint16_t col, lv_table_cell_ctrl_t ctrl)
int luat_lv_table_clear_cell_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_table_clear_cell_ctrl");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    lv_table_cell_ctrl_t ctrl = (lv_table_cell_ctrl_t)luaL_checkinteger(L, 4);
    lv_table_clear_cell_ctrl(obj ,row ,col ,ctrl);
    return 0;
}

//  char* lv_table_get_cell_value(lv_obj_t* obj, uint16_t row, uint16_t col)
int luat_lv_table_get_cell_value(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_cell_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    char* ret = NULL;
    ret = lv_table_get_cell_value(obj ,row ,col);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_table_get_row_cnt(lv_obj_t* obj)
int luat_lv_table_get_row_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_row_cnt");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_table_get_row_cnt(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_table_get_col_cnt(lv_obj_t* obj)
int luat_lv_table_get_col_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_col_cnt");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_table_get_col_cnt(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_table_get_col_width(lv_obj_t* obj, uint16_t col)
int luat_lv_table_get_col_width(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_col_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_table_get_col_width(obj ,col);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_table_has_cell_ctrl(lv_obj_t* obj, uint16_t row, uint16_t col, lv_table_cell_ctrl_t ctrl)
int luat_lv_table_has_cell_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_table_has_cell_ctrl");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    lv_table_cell_ctrl_t ctrl = (lv_table_cell_ctrl_t)luaL_checkinteger(L, 4);
    bool ret;
    ret = lv_table_has_cell_ctrl(obj ,row ,col ,ctrl);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_table_get_selected_cell(lv_obj_t* obj, uint16_t* row, uint16_t* col)
int luat_lv_table_get_selected_cell(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_selected_cell");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t* row = (uint16_t*)lua_touserdata(L, 2);
    uint16_t* col = (uint16_t*)lua_touserdata(L, 3);
    lv_table_get_selected_cell(obj ,row ,col);
    return 0;
}

