

// #include "luat_base.h"
// #include "lvgl.h"
// #include "luat_lvgl.h"


// //  bool lv_font_get_glyph_dsc(lv_font_t* font_p, lv_font_glyph_dsc_t* dsc_out, uint32_t letter, uint32_t letter_next)
// int luat_lv_font_get_glyph_dsc(lua_State *L) {
//     LV_DEBUG("CALL lv_font_get_glyph_dsc");
//     lv_font_t* font_p = (lv_font_t*)lua_touserdata(L, 1);
//     lv_font_glyph_dsc_t* dsc_out = (lv_font_glyph_dsc_t*)lua_touserdata(L, 2);
//     uint32_t letter = (uint32_t)luaL_checkinteger(L, 3);
//     uint32_t letter_next = (uint32_t)luaL_checkinteger(L, 4);
//     bool ret;
//     ret = lv_font_get_glyph_dsc(font_p ,dsc_out ,letter ,letter_next);
//     lua_pushboolean(L, ret);
//     return 1;
// }

// //  uint16_t lv_font_get_glyph_width(lv_font_t* font, uint32_t letter, uint32_t letter_next)
// int luat_lv_font_get_glyph_width(lua_State *L) {
//     LV_DEBUG("CALL lv_font_get_glyph_width");
//     lv_font_t* font = (lv_font_t*)lua_touserdata(L, 1);
//     uint32_t letter = (uint32_t)luaL_checkinteger(L, 2);
//     uint32_t letter_next = (uint32_t)luaL_checkinteger(L, 3);
//     uint16_t ret;
//     ret = lv_font_get_glyph_width(font ,letter ,letter_next);
//     lua_pushinteger(L, ret);
//     return 1;
// }

// //  lv_coord_t lv_font_get_line_height(lv_font_t* font_p)
// int luat_lv_font_get_line_height(lua_State *L) {
//     LV_DEBUG("CALL lv_font_get_line_height");
//     lv_font_t* font_p = (lv_font_t*)lua_touserdata(L, 1);
//     lv_coord_t ret;
//     ret = lv_font_get_line_height(font_p);
//     lua_pushinteger(L, ret);
//     return 1;
// }

