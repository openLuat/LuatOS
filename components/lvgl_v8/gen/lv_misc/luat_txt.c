
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_txt_get_size(lv_point_t* size_res, char* text, lv_font_t* font, lv_coord_t letter_space, lv_coord_t line_space, lv_coord_t max_width, lv_text_flag_t flag)
int luat_lv_txt_get_size(lua_State *L) {
    LV_DEBUG("CALL lv_txt_get_size");
    lv_point_t* size_res = (lv_point_t*)lua_touserdata(L, 1);
    char* text = (char*)luaL_checkstring(L, 2);
    lv_font_t* font = (lv_font_t*)lua_touserdata(L, 3);
    lv_coord_t letter_space = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t line_space = (lv_coord_t)luaL_checknumber(L, 5);
    lv_coord_t max_width = (lv_coord_t)luaL_checknumber(L, 6);
    lv_text_flag_t flag = (lv_text_flag_t)luaL_checkinteger(L, 7);
    lv_txt_get_size(size_res ,text ,font ,letter_space ,line_space ,max_width ,flag);
    return 0;
}

//  lv_coord_t lv_txt_get_width(char* txt, uint32_t length, lv_font_t* font, lv_coord_t letter_space, lv_text_flag_t flag)
int luat_lv_txt_get_width(lua_State *L) {
    LV_DEBUG("CALL lv_txt_get_width");
    char* txt = (char*)luaL_checkstring(L, 1);
    uint32_t length = (uint32_t)luaL_checkinteger(L, 2);
    lv_font_t* font = (lv_font_t*)lua_touserdata(L, 3);
    lv_coord_t letter_space = (lv_coord_t)luaL_checknumber(L, 4);
    lv_text_flag_t flag = (lv_text_flag_t)luaL_checkinteger(L, 5);
    lv_coord_t ret;
    ret = lv_txt_get_width(txt ,length ,font ,letter_space ,flag);
    lua_pushinteger(L, ret);
    return 1;
}

