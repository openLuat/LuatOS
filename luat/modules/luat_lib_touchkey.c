/*
@module  touchkey
@summary 触摸按键
@version 1.0
@date    2022.01.15
@tag LUAT_USE_TOUCHKEY
*/
#include "luat_base.h"
#include "luat_touchkey.h"
#include "luat_msgbus.h"

/*
配置触摸按键
@api touchkey.setup(id, scan_period, window, threshold)
@int 传感器id,请查阅硬件文档, 例如air101/air103支持 1~15, 例如PA7对应touch id=1
@int 扫描间隔,范围1 ~ 0x3F, 单位16ms,可选
@int 扫描窗口,范围2-7, 可选
@int 阀值, 范围0-127, 可选
@return bool 成功返回true, 失败返回false
@usage
touchkey.setup(1)
sys.subscribe("TOUCHKEY_INC", function(id, count)
    -- 传感器id
    -- 计数器,触摸次数统计
    log.info("touchkey", id, count)
end)
*/
static int l_touchkey_setup(lua_State *L) {
    luat_touchkey_conf_t conf;

    conf.id = (uint8_t)luaL_checkinteger(L, 1);
    conf.scan_period = (uint8_t)luaL_optinteger(L, 2, 0);
    conf.window = (uint8_t)luaL_optinteger(L, 2, 0);
    conf.threshold = (uint8_t)luaL_optinteger(L, 2, 0);

    int ret = luat_touchkey_setup(&conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
关闭初始触摸按键
@api touchkey.close(id)
@int 传感器id,请查阅硬件文档
@return nil 无返回值
@usage
-- 不太可能需要关掉的样子
touchkey.close(1)
*/
static int l_touchkey_close(lua_State *L) {
    uint8_t pin = (uint8_t)luaL_checkinteger(L, 1);
    luat_touchkey_close(pin);
    return 0;
}

int l_touchkey_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (lua_isnil(L, -1)) {
        lua_pushinteger(L, 0);
        return 1;
    }
/*
@sys_pub touchkey
触摸按键消息
TOUCHKEY_INC
@number port, 传感器id
@number state, 计数器,触摸次数统计
@usage
sys.subscribe("TOUCHKEY_INC", function(id, count)
    -- 传感器id
    -- 计数器,触摸次数统计
    log.info("touchkey", id, count)
end)
*/
    lua_pushliteral(L, "TOUCHKEY_INC");
    lua_pushinteger(L, msg->arg1);
    lua_pushinteger(L, msg->arg2);
    lua_call(L, 3, 0);
    return 0;
}


#include "rotable2.h"
static const rotable_Reg_t reg_touchkey[] =
{
    { "setup",  ROREG_FUNC(l_touchkey_setup)},
    { "close",  ROREG_FUNC(l_touchkey_close)},
    { NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_touchkey(lua_State *L)
{
    luat_newlib2(L, reg_touchkey);
    return 1;
}
