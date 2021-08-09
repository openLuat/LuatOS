/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "../exts/lv_gif/lv_gif.h"

/*
创建gif组件
@api lvgl.gif_create(parent, path)
@userdata 父组件,可以是nil,但通常不会是nil
@string 文件路径
@return userdata 组件指针,若失败会返回nil,建议检查
@usage
local gif = lvgl.gif_create(scr, "S/emtry.gif")
if gif then
    log.info("gif", "create ok")
end

*/
int luat_lv_gif_create(lua_State *L) {
    lv_obj_t * parent = lua_touserdata(L, 1);
    const char* path = luaL_checkstring(L, 2);
    lv_obj_t *gif = lv_gif_create_from_file(parent, path);
    lua_pushlightuserdata(L, gif);
    return 1;
}

/*
重新播放gif组件
@api lvgl.gif_restart(gif)
@userdata gif组件支持, 由gif_create方法返回
@return nil 无返回值
@usage
local gif = lvgl.gif_create(scr, "S/emtry.gif")
if gif then
    log.info("gif", "create ok")
end

*/
int luat_lv_gif_restart(lua_State *L) {
    lv_obj_t * gif = lua_touserdata(L, 1);
    lv_gif_restart(gif);
    return 0;
}

int luat_lv_gif_delete(lua_State *L);
