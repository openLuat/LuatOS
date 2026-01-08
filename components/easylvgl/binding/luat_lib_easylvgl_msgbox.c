/*
@module  easylvgl.msgbox
@summary EasyLVGL Msgbox 组件
@version 0.2.0
@date    2025.12.12
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include "lvgl9/src/widgets/msgbox/lv_msgbox.h"
#include "lvgl9/src/misc/lv_timer.h"
#include "lvgl9/src/misc/lv_event.h"

#define LUAT_LOG_TAG "easylvgl.msgbox"
#include "luat_log.h"

#define EASYLVGL_MSGBOX_MT "easylvgl.msgbox"

/**
 * 清理 msgbox Lua 侧关联数据
 * @param ud 组件用户数据
 */
static void easylvgl_msgbox_lua_cleanup(easylvgl_component_ud_t *ud)
{
    if (ud == NULL || ud->obj == NULL) {
        return;
    }

    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
    if (meta != NULL) {
        lv_timer_t *timer = easylvgl_msgbox_release_user_data(meta);
        if (timer != NULL) {
            lv_timer_delete(timer);
        }
        easylvgl_component_meta_free(meta);
    }

    lv_msgbox_close(ud->obj);
    ud->obj = NULL;
}

/**
 * 创建 Msgbox 组件
 * @api easylvgl.msgbox(config)
 * @table config 配置表
 * @string config.title 标题文本，可选
 * @string config.text 内容文本，可选
 * @boolean config.auto_center 是否自动居中，默认 true
 * @int config.timeout 自动关闭时间（毫秒），默认 0
 * @table config.buttons 按钮标签数组，默认 ["OK"]
 * @function config.on_action 按钮点击回调
 * @userdata config.parent 父对象，可选
 * @return userdata Msgbox 对象，失败返回 nil
 */
static int l_easylvgl_msgbox(lua_State *L)
{
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    lv_obj_t *msgbox = easylvgl_msgbox_create_from_config(L, 1);
    if (msgbox == NULL) {
        lua_pushnil(L);
        return 1;
    }

    easylvgl_push_component_userdata(L, msgbox, EASYLVGL_MSGBOX_MT);
    return 1;
}

/**
 * Msgbox:show()
 * @api msgbox:show()
 * @return nil
 */
static int l_msgbox_show(lua_State *L)
{
    lv_obj_t *msgbox = easylvgl_check_component(L, 1, EASYLVGL_MSGBOX_MT);
    easylvgl_msgbox_show(msgbox);
    return 0;
}

/**
 * Msgbox:hide()
 * @api msgbox:hide()
 * @return nil
 */
static int l_msgbox_hide(lua_State *L)
{
    lv_obj_t *msgbox = easylvgl_check_component(L, 1, EASYLVGL_MSGBOX_MT);
    easylvgl_msgbox_hide(msgbox);
    return 0;
}

/**
 * Msgbox:set_on_action(callback)
 * @api msgbox:set_on_action(callback)
 * @function callback 操作回调（按键 ID 传参）
 * @return nil
 */
static int l_msgbox_set_on_action(lua_State *L)
{
    lv_obj_t *msgbox = easylvgl_check_component(L, 1, EASYLVGL_MSGBOX_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_msgbox_set_on_action(msgbox, ref);
    return 0;
}

/**
 * Msgbox:release()
 * @api msgbox:release()
 * @return nil
 */
static int l_msgbox_release(lua_State *L)
{
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_MSGBOX_MT);
    if (ud != NULL && ud->obj != NULL) {
        easylvgl_msgbox_lua_cleanup(ud);
    }
    return 0;
}

/**
 * Msgbox:destroy（手动销毁）
 */
static int l_msgbox_destroy(lua_State *L)
{
    return l_msgbox_release(L);
}

/**
 * 注册 Msgbox 元表
 * @param L Lua 状态
 */
void easylvgl_register_msgbox_meta(lua_State *L)
{
    luaL_newmetatable(L, EASYLVGL_MSGBOX_MT);

    static const luaL_Reg methods[] = {
        {"show", l_msgbox_show},
        {"hide", l_msgbox_hide},
        {"set_on_action", l_msgbox_set_on_action},
        {"release", l_msgbox_release},
        {"destroy", l_msgbox_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Msgbox 创建函数（供主模块注册）
 */
int easylvgl_msgbox_create(lua_State *L)
{
    return l_easylvgl_msgbox(L);
}

