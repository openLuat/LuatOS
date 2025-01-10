
/*
@module  netdrv
@summary 网络设备管理
@catalog 外设API
@version 1.0
@date    2025.01.07
@demo netdrv
@tag LUAT_USE_NETDRV
*/
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_rtos.h"
#include "luat_netdrv.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

/*
初始化指定netdrv设备
@api netdrv.setup(id, tp, opts)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@int 实现方式,如果是设备自带的硬件,那就不需要传, 外挂设备需要传,当前支持CH390H/D
@int 外挂方式,需要额外的参数,参考示例
@return boolean 初始化成功与否
@usage
-- Air8101初始化内部以太网控制器
netdrv.setup(socket.LWIP_ETH)

-- Air8000/Air780EPM初始化CH390H/D作为LAN口, 单一使用.不含WAN.
netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spiid=0,cs=8})
netdrv.dhcp(socket.LWIP_ETH, true)
*/
static int l_netdrv_setup(lua_State *L) {
    luat_netdrv_conf_t conf = {0};
    conf.id = luaL_checkinteger(L, 1);
    conf.impl = luaL_optinteger(L, 2, 0);
    if (lua_istable(L, 3)) {
        if (lua_getfield(L, 3, "spi") == LUA_TNUMBER) {
            conf.spiid = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);
        if (lua_getfield(L, 3, "cs") == LUA_TNUMBER) {
            conf.cspin = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);

        if (lua_getfield(L, 3, "irq") == LUA_TNUMBER) {
            conf.irqpin = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);
    }
    luat_netdrv_t* ret = luat_netdrv_setup(&conf);
    lua_pushboolean(L, ret != NULL);
    return 1;
}

/*
开启或关闭DHCP
@api netdrv.dhcp(id, enable)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@boolean 开启或者关闭
@return boolean 成功与否
@usgae
-- 注意, 并非所有网络设备都支持关闭DHCP, 例如4G Cat.1
netdrv.dhcp(socket.LWIP_ETH, true)
*/
static int l_netdrv_dhcp(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int enable = lua_toboolean(L, 2);
    int ret = luat_netdrv_dhcp(id, enable);
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
设置或获取设备MAC
@api netdrv.mac(id, new_mac, raw_string)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@string 新的MAC地址,可选, 必须是6个字节
@boolean 是否返回6字节原始数据, 默认是否, 返回HEX字符串
@return boolean 成功与否
@usage
-- 获取MAC地址
log.info("netdrv", "mac addr", netdrv.mac(socket.LWIP_ETH))
-- 暂不支持设置
*/
static int l_netdrv_mac(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    char buff[6] = {0};
    char tmpbuff[13] = {0};
    size_t len = 0;
    int ret = 0;
    if (lua_isstring(L, 2)) {
        const char* tmp = luaL_checklstring(L, 2, &len);
        if (len != 6) {
            return 0;
        }
        luat_netdrv_mac(id, tmp, buff);
    }
    else {
        luat_netdrv_mac(id, NULL, buff);
    }
    if (lua_isboolean(L, 3) && !lua_toboolean(L, 3)) {
        lua_pushlstring(L, (const char*)buff, 6);
    }
    else {
        sprintf_(tmpbuff, "%02X%02X%02X%02X%02X%02X", buff[0], buff[1], buff[2], buff[3], buff[4], buff[5]);
        lua_pushstring(L, tmpbuff);
    }
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_netdrv[] =
{
    { "setup" ,         ROREG_FUNC(l_netdrv_setup )},
    { "dhcp",           ROREG_FUNC(l_netdrv_dhcp)},
    { "mac",            ROREG_FUNC(l_netdrv_mac)},

    { "CH390",          ROREG_INT(1)},
    { "W5500",          ROREG_INT(2)},
    { "W5100",          ROREG_INT(3)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_netdrv( lua_State *L ) {
    luat_newlib2(L, reg_netdrv);
    return 1;
}
