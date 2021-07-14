
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_objmask_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_objmask_create(lua_State *L) {
    LV_DEBUG("CALL lv_objmask_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_objmask_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_objmask_mask_t* lv_objmask_add_mask(lv_obj_t* objmask, void* param)
int luat_lv_objmask_add_mask(lua_State *L) {
    LV_DEBUG("CALL lv_objmask_add_mask");
    lv_obj_t* objmask = (lv_obj_t*)lua_touserdata(L, 1);
    void* param = (void*)lua_touserdata(L, 2);
    lv_objmask_mask_t* ret = NULL;
    ret = lv_objmask_add_mask(objmask ,param);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_objmask_update_mask(lv_obj_t* objmask, lv_objmask_mask_t* mask, void* param)
int luat_lv_objmask_update_mask(lua_State *L) {
    LV_DEBUG("CALL lv_objmask_update_mask");
    lv_obj_t* objmask = (lv_obj_t*)lua_touserdata(L, 1);
    lv_objmask_mask_t* mask = (lv_objmask_mask_t*)lua_touserdata(L, 2);
    void* param = (void*)lua_touserdata(L, 3);
    lv_objmask_update_mask(objmask ,mask ,param);
    return 0;
}

//  void lv_objmask_remove_mask(lv_obj_t* objmask, lv_objmask_mask_t* mask)
int luat_lv_objmask_remove_mask(lua_State *L) {
    LV_DEBUG("CALL lv_objmask_remove_mask");
    lv_obj_t* objmask = (lv_obj_t*)lua_touserdata(L, 1);
    lv_objmask_mask_t* mask = (lv_objmask_mask_t*)lua_touserdata(L, 2);
    lv_objmask_remove_mask(objmask ,mask);
    return 0;
}

