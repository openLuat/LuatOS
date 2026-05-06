/*
@module  airui.msgbox
@summary AIRUI Msgbox component
@version 0.2.0
@date    2025.12.12
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"
#include "lvgl9/src/widgets/msgbox/lv_msgbox.h"
#include "lvgl9/src/misc/lv_timer.h"
#include "lvgl9/src/misc/lv_event.h"

#define LUAT_LOG_TAG "airui.msgbox"
#include "luat_log.h"

#define AIRUI_MSGBOX_MT "airui.msgbox"

/**
 * 创建 Msgbox 组件
 * @api airui.msgbox(config)
 * @usage airui.msgbox({ title = "Notice", x = 20, y = 20, w = 280, h = 160, style = { bg_color = 0xffffff, text_font_size = 18 } })
 * @table config 配置表
 * @string config.title 标题文本，可选
 * @string config.text 内容文本，可选
 * @boolean config.auto_center 是否自动居中，默认 true
 * @int config.x X 坐标，可选
 * @int config.y Y 坐标，可选
 * @int config.w 宽度，可选
 * @int config.h 高度，可选
 * @int config.timeout 自动关闭时间，单位毫秒，默认 0
 * @table config.buttons 按钮标签数组，默认 {"OK"}
 * @table config.style 样式表，可选
 * @int config.style.bg_color 背景色，格式 0xRRGGBB
 * @int config.style.bg_opa 背景透明度，范围 0-255
 * @int config.style.border_color 边框颜色，格式 0xRRGGBB
 * @int config.style.border_width 边框宽度，单位像素
 * @int config.style.radius 圆角半径，单位像素
 * @int config.style.text_font_size 文本字号，仅在 hzfont 启用时生效
 * @function config.on_action 按钮点击回调
 * @userdata config.parent 父对象，可选
 * @return userdata Msgbox 对象，失败返回 nil
 */
static int l_airui_msgbox(lua_State *L)
{
    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "airui not initialized, call airui.init() first");
        return 0;
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    lv_obj_t *msgbox = airui_msgbox_create_from_config(L, 1);
    if (msgbox == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, msgbox, AIRUI_MSGBOX_MT);
    return 1;
}

static void airui_msgbox_lua_cleanup(airui_component_ud_t *ud)
{
    lv_obj_t *obj = airui_component_userdata_obj(ud);
    if (obj == NULL) {
        return;
    }

    airui_component_meta_t *meta = airui_component_meta_get(obj);
    if (meta != NULL) {
        lv_timer_t *timer = airui_msgbox_release_user_data(meta);
        if (timer != NULL) {
            lv_timer_delete(timer);
        }
    }

    lv_msgbox_close(obj);
}

/**
 * Msgbox:show()
 * @api msgbox:show()
 * @return nil
 */
static int l_msgbox_show(lua_State *L)
{
    lv_obj_t *msgbox = airui_check_component(L, 1, AIRUI_MSGBOX_MT);
    airui_msgbox_show(msgbox);
    return 0;
}

/**
 * Msgbox:hide()
 * @api msgbox:hide()
 * @return nil
 */
static int l_msgbox_hide(lua_State *L)
{
    lv_obj_t *msgbox = airui_check_component(L, 1, AIRUI_MSGBOX_MT);
    airui_msgbox_hide(msgbox);
    return 0;
}

/**
 * Msgbox:set_on_action(callback)
 * @api msgbox:set_on_action(callback)
 * @function callback action callback
 * @return nil
 */
static int l_msgbox_set_on_action(lua_State *L)
{
    lv_obj_t *msgbox = airui_check_component(L, 1, AIRUI_MSGBOX_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    airui_msgbox_set_on_action(msgbox, ref);
    return 0;
}

/**
 * Msgbox:set_style(style)
 * @api msgbox:set_style(style)
 * @table style style table, supports bg_color/bg_opa, border_color/border_width, radius, text_font_size
 * @return nil
 */
static int l_msgbox_set_style(lua_State *L)
{
    lv_obj_t *msgbox = airui_check_component(L, 1, AIRUI_MSGBOX_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    airui_msgbox_set_style(msgbox, L, 2);
    return 0;
}

/**
 * Msgbox:release()
 * @api msgbox:release()
 * @return nil
 */
static int l_msgbox_release(lua_State *L)
{
    airui_component_ud_t *ud = (airui_component_ud_t *)luaL_checkudata(L, 1, AIRUI_MSGBOX_MT);
    if (airui_component_userdata_obj(ud) != NULL) {
        airui_msgbox_lua_cleanup(ud);
    }
    return 0;
}

static int l_msgbox_destroy(lua_State *L)
{
    return l_msgbox_release(L);
}

void airui_register_msgbox_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_MSGBOX_MT);

    static const luaL_Reg methods[] = {
        {"show", l_msgbox_show},
        {"hide", l_msgbox_hide},
        {"set_style", l_msgbox_set_style},
        {"set_on_action", l_msgbox_set_on_action},
        {"release", l_msgbox_release},
        {"destroy", l_msgbox_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_msgbox_create(lua_State *L)
{
    return l_airui_msgbox(L);
}
