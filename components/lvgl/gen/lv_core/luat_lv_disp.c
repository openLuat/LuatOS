
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_disp_drv_init(lv_disp_drv_t* driver)
int luat_lv_disp_drv_init(lua_State *L) {
    LV_DEBUG("CALL lv_disp_drv_init");
    lv_disp_drv_t* driver = (lv_disp_drv_t*)lua_touserdata(L, 1);
    lv_disp_drv_init(driver);
    return 0;
}

//  void lv_disp_buf_init(lv_disp_buf_t* disp_buf, void* buf1, void* buf2, uint32_t size_in_px_cnt)
int luat_lv_disp_buf_init(lua_State *L) {
    LV_DEBUG("CALL lv_disp_buf_init");
    lv_disp_buf_t* disp_buf = (lv_disp_buf_t*)lua_touserdata(L, 1);
    void* buf1 = (void*)lua_touserdata(L, 2);
    void* buf2 = (void*)lua_touserdata(L, 3);
    uint32_t size_in_px_cnt = (uint32_t)luaL_checkinteger(L, 4);
    lv_disp_buf_init(disp_buf ,buf1 ,buf2 ,size_in_px_cnt);
    return 0;
}

//  lv_disp_t* lv_disp_drv_register(lv_disp_drv_t* driver)
int luat_lv_disp_drv_register(lua_State *L) {
    LV_DEBUG("CALL lv_disp_drv_register");
    lv_disp_drv_t* driver = (lv_disp_drv_t*)lua_touserdata(L, 1);
    lv_disp_t* ret = NULL;
    ret = lv_disp_drv_register(driver);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_disp_drv_update(lv_disp_t* disp, lv_disp_drv_t* new_drv)
int luat_lv_disp_drv_update(lua_State *L) {
    LV_DEBUG("CALL lv_disp_drv_update");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_drv_t* new_drv = (lv_disp_drv_t*)lua_touserdata(L, 2);
    lv_disp_drv_update(disp ,new_drv);
    return 0;
}

//  void lv_disp_remove(lv_disp_t* disp)
int luat_lv_disp_remove(lua_State *L) {
    LV_DEBUG("CALL lv_disp_remove");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_remove(disp);
    return 0;
}

//  void lv_disp_set_default(lv_disp_t* disp)
int luat_lv_disp_set_default(lua_State *L) {
    LV_DEBUG("CALL lv_disp_set_default");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_set_default(disp);
    return 0;
}

//  lv_disp_t* lv_disp_get_default()
int luat_lv_disp_get_default(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_default");
    lv_disp_t* ret = NULL;
    ret = lv_disp_get_default();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_coord_t lv_disp_get_hor_res(lv_disp_t* disp)
int luat_lv_disp_get_hor_res(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_hor_res");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_disp_get_hor_res(disp);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_disp_get_ver_res(lv_disp_t* disp)
int luat_lv_disp_get_ver_res(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_ver_res");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_disp_get_ver_res(disp);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_disp_get_antialiasing(lv_disp_t* disp)
int luat_lv_disp_get_antialiasing(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_antialiasing");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_disp_get_antialiasing(disp);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_coord_t lv_disp_get_dpi(lv_disp_t* disp)
int luat_lv_disp_get_dpi(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_dpi");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_disp_get_dpi(disp);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_disp_size_t lv_disp_get_size_category(lv_disp_t* disp)
int luat_lv_disp_get_size_category(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_size_category");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_size_t ret;
    ret = lv_disp_get_size_category(disp);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_disp_set_rotation(lv_disp_t* disp, lv_disp_rot_t rotation)
int luat_lv_disp_set_rotation(lua_State *L) {
    LV_DEBUG("CALL lv_disp_set_rotation");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_rot_t rotation = (lv_disp_rot_t)luaL_checkinteger(L, 2);
    lv_disp_set_rotation(disp ,rotation);
    return 0;
}

//  lv_disp_rot_t lv_disp_get_rotation(lv_disp_t* disp)
int luat_lv_disp_get_rotation(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_rotation");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_rot_t ret;
    ret = lv_disp_get_rotation(disp);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_disp_flush_ready(lv_disp_drv_t* disp_drv)
int luat_lv_disp_flush_ready(lua_State *L) {
    LV_DEBUG("CALL lv_disp_flush_ready");
    lv_disp_drv_t* disp_drv = (lv_disp_drv_t*)lua_touserdata(L, 1);
    lv_disp_flush_ready(disp_drv);
    return 0;
}

//  bool lv_disp_flush_is_last(lv_disp_drv_t* disp_drv)
int luat_lv_disp_flush_is_last(lua_State *L) {
    LV_DEBUG("CALL lv_disp_flush_is_last");
    lv_disp_drv_t* disp_drv = (lv_disp_drv_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_disp_flush_is_last(disp_drv);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_disp_t* lv_disp_get_next(lv_disp_t* disp)
int luat_lv_disp_get_next(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_next");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_t* ret = NULL;
    ret = lv_disp_get_next(disp);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_disp_buf_t* lv_disp_get_buf(lv_disp_t* disp)
int luat_lv_disp_get_buf(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_buf");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_buf_t* ret = NULL;
    ret = lv_disp_get_buf(disp);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint16_t lv_disp_get_inv_buf_size(lv_disp_t* disp)
int luat_lv_disp_get_inv_buf_size(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_inv_buf_size");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_disp_get_inv_buf_size(disp);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_disp_is_double_buf(lv_disp_t* disp)
int luat_lv_disp_is_double_buf(lua_State *L) {
    LV_DEBUG("CALL lv_disp_is_double_buf");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_disp_is_double_buf(disp);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_disp_is_true_double_buf(lv_disp_t* disp)
int luat_lv_disp_is_true_double_buf(lua_State *L) {
    LV_DEBUG("CALL lv_disp_is_true_double_buf");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_disp_is_true_double_buf(disp);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_obj_t* lv_disp_get_scr_act(lv_disp_t* disp)
int luat_lv_disp_get_scr_act(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_scr_act");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_disp_get_scr_act(disp);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_disp_get_scr_prev(lv_disp_t* disp)
int luat_lv_disp_get_scr_prev(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_scr_prev");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_disp_get_scr_prev(disp);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_disp_load_scr(lv_obj_t* scr)
int luat_lv_disp_load_scr(lua_State *L) {
    LV_DEBUG("CALL lv_disp_load_scr");
    lv_obj_t* scr = (lv_obj_t*)lua_touserdata(L, 1);
    lv_disp_load_scr(scr);
    return 0;
}

//  lv_obj_t* lv_disp_get_layer_top(lv_disp_t* disp)
int luat_lv_disp_get_layer_top(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_layer_top");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_disp_get_layer_top(disp);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_disp_get_layer_sys(lv_disp_t* disp)
int luat_lv_disp_get_layer_sys(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_layer_sys");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_disp_get_layer_sys(disp);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_disp_assign_screen(lv_disp_t* disp, lv_obj_t* scr)
int luat_lv_disp_assign_screen(lua_State *L) {
    LV_DEBUG("CALL lv_disp_assign_screen");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_obj_t* scr = (lv_obj_t*)lua_touserdata(L, 2);
    lv_disp_assign_screen(disp ,scr);
    return 0;
}

//  void lv_disp_set_bg_color(lv_disp_t* disp, lv_color_t color)
int luat_lv_disp_set_bg_color(lua_State *L) {
    LV_DEBUG("CALL lv_disp_set_bg_color");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    lv_disp_set_bg_color(disp ,color);
    return 0;
}

//  void lv_disp_set_bg_image(lv_disp_t* disp, void* img_src)
int luat_lv_disp_set_bg_image(lua_State *L) {
    LV_DEBUG("CALL lv_disp_set_bg_image");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    void* img_src = (void*)lua_touserdata(L, 2);
    lv_disp_set_bg_image(disp ,img_src);
    return 0;
}

//  void lv_disp_set_bg_opa(lv_disp_t* disp, lv_opa_t opa)
int luat_lv_disp_set_bg_opa(lua_State *L) {
    LV_DEBUG("CALL lv_disp_set_bg_opa");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_opa_t opa = (lv_opa_t)luaL_checknumber(L, 2);
    lv_disp_set_bg_opa(disp ,opa);
    return 0;
}

//  uint32_t lv_disp_get_inactive_time(lv_disp_t* disp)
int luat_lv_disp_get_inactive_time(lua_State *L) {
    LV_DEBUG("CALL lv_disp_get_inactive_time");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_disp_get_inactive_time(disp);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_disp_trig_activity(lv_disp_t* disp)
int luat_lv_disp_trig_activity(lua_State *L) {
    LV_DEBUG("CALL lv_disp_trig_activity");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_trig_activity(disp);
    return 0;
}

//  void lv_disp_clean_dcache(lv_disp_t* disp)
int luat_lv_disp_clean_dcache(lua_State *L) {
    LV_DEBUG("CALL lv_disp_clean_dcache");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_disp_clean_dcache(disp);
    return 0;
}

