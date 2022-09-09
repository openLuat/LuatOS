
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_table_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_table_create(lua_State *L) {
    LV_DEBUG("CALL lv_table_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_table_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_table_set_cell_value(lv_obj_t* table, uint16_t row, uint16_t col, char* txt)
int luat_lv_table_set_cell_value(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_cell_value");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    char* txt = (char*)luaL_checkstring(L, 4);
    lv_table_set_cell_value(table ,row ,col ,txt);
    return 0;
}

//  void lv_table_set_row_cnt(lv_obj_t* table, uint16_t row_cnt)
int luat_lv_table_set_row_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_row_cnt");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row_cnt = (uint16_t)luaL_checkinteger(L, 2);
    lv_table_set_row_cnt(table ,row_cnt);
    return 0;
}

//  void lv_table_set_col_cnt(lv_obj_t* table, uint16_t col_cnt)
int luat_lv_table_set_col_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_col_cnt");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t col_cnt = (uint16_t)luaL_checkinteger(L, 2);
    lv_table_set_col_cnt(table ,col_cnt);
    return 0;
}

//  void lv_table_set_col_width(lv_obj_t* table, uint16_t col_id, lv_coord_t w)
int luat_lv_table_set_col_width(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_col_width");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t col_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 3);
    lv_table_set_col_width(table ,col_id ,w);
    return 0;
}

//  void lv_table_set_cell_align(lv_obj_t* table, uint16_t row, uint16_t col, lv_label_align_t align)
int luat_lv_table_set_cell_align(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_cell_align");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    lv_label_align_t align = (lv_label_align_t)luaL_checkinteger(L, 4);
    lv_table_set_cell_align(table ,row ,col ,align);
    return 0;
}

//  void lv_table_set_cell_type(lv_obj_t* table, uint16_t row, uint16_t col, uint8_t type)
int luat_lv_table_set_cell_type(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_cell_type");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    uint8_t type = (uint8_t)luaL_checkinteger(L, 4);
    lv_table_set_cell_type(table ,row ,col ,type);
    return 0;
}

//  void lv_table_set_cell_crop(lv_obj_t* table, uint16_t row, uint16_t col, bool crop)
int luat_lv_table_set_cell_crop(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_cell_crop");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    bool crop = (bool)lua_toboolean(L, 4);
    lv_table_set_cell_crop(table ,row ,col ,crop);
    return 0;
}

//  void lv_table_set_cell_merge_right(lv_obj_t* table, uint16_t row, uint16_t col, bool en)
int luat_lv_table_set_cell_merge_right(lua_State *L) {
    LV_DEBUG("CALL lv_table_set_cell_merge_right");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    bool en = (bool)lua_toboolean(L, 4);
    lv_table_set_cell_merge_right(table ,row ,col ,en);
    return 0;
}

//  char* lv_table_get_cell_value(lv_obj_t* table, uint16_t row, uint16_t col)
int luat_lv_table_get_cell_value(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_cell_value");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    char* ret = NULL;
    ret = lv_table_get_cell_value(table ,row ,col);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_table_get_row_cnt(lv_obj_t* table)
int luat_lv_table_get_row_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_row_cnt");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_table_get_row_cnt(table);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_table_get_col_cnt(lv_obj_t* table)
int luat_lv_table_get_col_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_col_cnt");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_table_get_col_cnt(table);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_table_get_col_width(lv_obj_t* table, uint16_t col_id)
int luat_lv_table_get_col_width(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_col_width");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t col_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_table_get_col_width(table ,col_id);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_label_align_t lv_table_get_cell_align(lv_obj_t* table, uint16_t row, uint16_t col)
int luat_lv_table_get_cell_align(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_cell_align");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    lv_label_align_t ret;
    ret = lv_table_get_cell_align(table ,row ,col);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_label_align_t lv_table_get_cell_type(lv_obj_t* table, uint16_t row, uint16_t col)
int luat_lv_table_get_cell_type(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_cell_type");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    lv_label_align_t ret;
    ret = lv_table_get_cell_type(table ,row ,col);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_label_align_t lv_table_get_cell_crop(lv_obj_t* table, uint16_t row, uint16_t col)
int luat_lv_table_get_cell_crop(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_cell_crop");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    lv_label_align_t ret;
    ret = lv_table_get_cell_crop(table ,row ,col);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_table_get_cell_merge_right(lv_obj_t* table, uint16_t row, uint16_t col)
int luat_lv_table_get_cell_merge_right(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_cell_merge_right");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t row = (uint16_t)luaL_checkinteger(L, 2);
    uint16_t col = (uint16_t)luaL_checkinteger(L, 3);
    bool ret;
    ret = lv_table_get_cell_merge_right(table ,row ,col);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_res_t lv_table_get_pressed_cell(lv_obj_t* table, uint16_t* row, uint16_t* col)
int luat_lv_table_get_pressed_cell(lua_State *L) {
    LV_DEBUG("CALL lv_table_get_pressed_cell");
    lv_obj_t* table = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t* row = (uint16_t*)lua_touserdata(L, 2);
    uint16_t* col = (uint16_t*)lua_touserdata(L, 3);
    lv_res_t ret;
    ret = lv_table_get_pressed_cell(table ,row ,col);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

