
/*
@module  keyboard
@summary 键盘矩阵
@version 1.0
@date    2021.11.24
@demo keyboard
@tag LUAT_USE_KEYBOARD
*/

#include "luat_base.h"
#include "luat_keyboard.h"
#include "luat_msgbus.h"

//----------------------


static int l_keyboard_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
/*
@sys_pub keyboard
键盘矩阵消息
KB_INC
@number port, keyboard id 当前固定为0, 可以无视
@number data, keyboard 按键 需要配合init的map进行解析
@number state, 按键状态 1 为按下, 0 为 释放
@usage
sys.subscribe("KB_INC", function(port, data, state)
    -- port 当前固定为0, 可以无视
    -- data, 需要配合init的map进行解析
    -- state, 1 为按下, 0 为 释放
    log.info("keyboard", port, data, state)
end)
*/
    lua_pushstring(L, "KB_INC");
    lua_pushinteger(L, msg->arg1);
    lua_pushinteger(L, msg->arg2);
    lua_pushinteger(L, (uint32_t)msg->ptr);
    lua_call(L, 4, 0);
    return 0;
}

static void l_keyboard_irq_cb(luat_keyboard_ctx_t* ctx) {
    rtos_msg_t msg = {0};
    msg.handler = l_keyboard_handler;
    msg.arg1 = ctx->port;
    msg.arg2 = ctx->pin_data;
    msg.ptr = (void*)ctx->state;
    luat_msgbus_put(&msg, 0);
}

//----------------------

/**
初始化键盘矩阵
@api keyboard.init(port, conf, map, debounce)
@int 预留, 当前填0
@int 启用的keyboard管脚掩码, 例如使用keyboard0~9, 则掩码为 0x1FF, 若使用 0~3 则 0xF
@int keyboard管脚方向映射, 其中输入为0,输出为1, 按位设置.  例如 keyboard0~3作为输入, keyboard4~7为输入, 则 0xF0
@int 消抖配置,预留,可以不填
@usage
-- 做一个 4*4 键盘矩阵, 使用 keyboard0~7, 其中0~3做输入, 4~7做输出
-- 使用 keyboard0~7, 对应conf为 0xFF
-- 其中0~3做输入, 4~7做输出, 对应map 为 0xF0
keyboard.init(0, 0xFF, 0xF0)

-- 做一个 2*3 键盘矩阵, 使用 keyboard0~4, 其中0~1做输入, 2~4做输出
-- 使用 keyboard0~4, 二进制为 11111,  对应conf的十六进制表达为 0x1F
-- 其中0~1做输入, 2~4做输出, 二进制为 11100 对应map 为 0x14
-- keyboard.init(0, 0xFF, 0x14)

sys.subscribe("KB_INC", function(port, data, state)
    -- port 当前固定为0, 可以无视
    -- data, 需要配合init的map进行解析
    -- state, 1 为按下, 0 为 释放
    -- TODO 详细介绍
end)
 */
static int l_keyboard_init(lua_State *L) {
    luat_keyboard_conf_t conf = {0};
    conf.port = luaL_checkinteger(L, 1);
    conf.pin_conf = luaL_checkinteger(L, 2);
    conf.pin_map = luaL_checkinteger(L, 3);
    conf.debounce = luaL_optinteger(L, 4, 1);
    conf.cb = l_keyboard_irq_cb;
    int ret = luat_keyboard_init(&conf);

    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

static int l_keyboard_deinit(lua_State *L) {
    luat_keyboard_conf_t conf = {0};
    conf.port = luaL_checkinteger(L, 1);
    conf.pin_conf = luaL_checkinteger(L, 2);
    conf.pin_map = luaL_checkinteger(L, 3);
    conf.debounce = luaL_optinteger(L, 4, 1);

    int ret = luat_keyboard_deinit(&conf);

    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_keyboard[] =
{
    { "init" ,         ROREG_FUNC(l_keyboard_init)},
    { "deinit" ,       ROREG_FUNC(l_keyboard_deinit)},
	{ NULL,            ROREG_INT(0) }
};

LUAMOD_API int luaopen_keyboard( lua_State *L ) {
    luat_newlib2(L, reg_keyboard);
    return 1;
}
