/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/


#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "../exts/lv_qrcode/lv_qrcode.h"

/**
创建qrcode组件
@api lvgl.qrcode_create(parent, size, dark_color, light_color)
@userdata 父组件
@int 长度,因为qrcode是正方形
@int 二维码中数据点的颜色, RGB颜色, 默认 0x3333ff
@int 二维码中背景点的颜色, RGB颜色, 默认 0xeeeeff
@return userdata qrcode组件
@usage
-- 创建并显示qrcode
local qrcode = lvgl.qrcode_create(scr, 100)
lvgl.qrcode_update(qrcode, "https://luatos.com")
lvgl.obj_align(qrcode, lvgl.scr_act(), lvgl.ALIGN_CENTER, -100, -100)
*/
int luat_lv_qrcode_create(lua_State *L) {
    lv_obj_t * parent = lua_touserdata(L, 1);
    lv_coord_t size = luaL_checkinteger(L, 2);
    int32_t dark_color = luaL_optinteger(L, 3, 0x3333ff);
    int32_t light_color = luaL_optinteger(L, 4, 0xeeeeff);
    lv_obj_t * qrcode = lv_qrcode_create(parent, size, lv_color_hex(dark_color), lv_color_hex(light_color));
    lua_pushlightuserdata(L, qrcode);
    return 1;
}

/**
设置qrcode组件的二维码内容,配合qrcode_create使用
@api lvgl.qrcode_update(qrcode, cnt)
@userdata qrcode组件,由qrcode_create创建
@string 二维码的内容数据
@return bool 更新成功返回true,否则返回false. 通常只有数据太长无法容纳才会返回false
*/
int luat_lv_qrcode_update(lua_State *L) {
    lv_obj_t * qrcode = lua_touserdata(L, 1);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 2, &len);
    lv_res_t ret = lv_qrcode_update(qrcode, data, len);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    return 1;
}

/**
删除qrcode组件
@api lvgl.qrcode_delete(qrcode)
@userdata qrcode组件,由qrcode_create创建
@return nil 无返回值
*/
int luat_lv_qrcode_delete(lua_State *L) {
    lv_obj_t * qrcode = lua_touserdata(L, 1);
    lv_qrcode_delete(qrcode);
    return 0;
}
