
/*
@module  softkeyboard
@summary 软件键盘矩阵(当前仅air105支持)
@version 1.0
@date    2022.03.09
*/

#include "luat_base.h"
#include "luat_softkeyboard.h"
#include "luat_msgbus.h"

#define MAX_DEVICE_COUNT 2
static luat_softkeyboard_conf_t softkb_conf[MAX_DEVICE_COUNT];

int l_softkeyboard_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
/*
@sys_pub softkeyboard
软件键盘矩阵消息
SOFT_KB_INC
@number port, keyboard id 当前固定为0, 可以无视
@number data, keyboard 按键 需要配合init的map进行解析
@number state, 按键状态 1 为按下, 0 为 释放
@usage
sys.subscribe("SOFT_KB_INC", function(port, data, state)
    -- port 当前固定为0, 可以无视
    -- data, 需要配合init的map进行解析
    -- state, 1 为按下, 0 为 释放
    log.info("keyboard", port, data, state)
end)
*/
    lua_pushstring(L, "SOFT_KB_INC");
    lua_pushinteger(L, msg->arg1);
    lua_pushinteger(L, msg->arg2);
    lua_pushinteger(L, msg->ptr);
    lua_call(L, 4, 0);
    return 0;
}

/**
初始化软件键盘矩阵
@api softkb.init(port, key_in, key_out)
@int 预留, 当前填0
@table 矩阵输入按键表
@table 矩阵输出按键表
@usage
    key_in = {pin.PD10,pin.PE00,pin.PE01,pin.PE02}
    key_out = {pin.PD12,pin.PD13,pin.PD14,pin.PD15}
    softkb.init(0,key_in,key_out)

sys.subscribe("SOFT_KB_INC", function(port, data, state)
    -- port 当前固定为0, 可以无视
    -- data, 需要配合init的map进行解析
    -- state, 1 为按下, 0 为 释放
    -- TODO 详细介绍
end)
 */
int l_softkb_init(lua_State* L) {
    uint8_t softkb_port = luaL_checkinteger(L,1);
    softkb_conf[softkb_port].port = softkb_port;
    if (lua_istable(L, 2)) {
        softkb_conf[softkb_port].inio_num = lua_rawlen(L, 2);
        softkb_conf[softkb_port].inio = (uint8_t*)luat_heap_calloc(softkb_conf[softkb_port].inio_num,sizeof(uint8_t));
        for (size_t i = 0; i < softkb_conf[softkb_port].inio_num; i++){
            lua_geti(L,2,i+1);
            softkb_conf[softkb_port].inio[i] = luaL_checkinteger(L,-1);
            lua_pop(L, 1);
        }
    }
    if (lua_istable(L, 3)) {
        softkb_conf[softkb_port].outio_num = lua_rawlen(L, 3);
        softkb_conf[softkb_port].outio = (uint8_t*)luat_heap_calloc(softkb_conf[softkb_port].outio_num,sizeof(uint8_t));
        for (size_t i = 0; i < softkb_conf[softkb_port].outio_num; i++){
            lua_geti(L,3,i+1);
            softkb_conf[softkb_port].outio[i] = luaL_checkinteger(L,-1);
            lua_pop(L, 1);
        }
    }
    int ret = luat_softkeyboard_init(&softkb_conf[softkb_port]);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/**
删除软件键盘矩阵
@api softkb.deinit(port)
@int 预留, 当前填0
@usage
    softkb.deinit(0)
 */
int l_softkb_deinit(lua_State* L) {
    luat_softkeyboard_conf_t conf = {0};
    uint8_t softkb_port = luaL_checkinteger(L,1);
    int ret = luat_softkeyboard_deinit(&softkb_conf[softkb_port]);
    luat_heap_free(softkb_conf[softkb_port].inio);
    luat_heap_free(softkb_conf[softkb_port].outio);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}


#include "rotable2.h"
static const rotable_Reg_t reg_softkb[] =
{
    { "init",          ROREG_FUNC(l_softkb_init)},
    { "deinit",        ROREG_FUNC(l_softkb_deinit)},
	{ NULL,            {}}
};

LUAMOD_API int luaopen_softkb( lua_State *L ) {
    luat_newlib2(L, reg_softkb);
    return 1;
}
