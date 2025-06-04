
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
#include "lwip/ip.h"
#include "lwip/ip4.h"
#include "luat_network_adapter.h"
#include "net_lwip2.h"

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

-- Air8000/Air780EPM初始化CH390H/D作为LAN/WAN
-- 支持多个CH390H, 使用不同的CS脚区分不同网口
netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0,cs=8})
netdrv.dhcp(socket.LWIP_ETH, true)
-- 支持CH390H的中断模式, 能提供响应速度, 但是需要外接中断引脚
-- 实测对总网速没有帮助, 轻负载时能降低功耗, 让模组能进入低功耗模式
netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0,cs=8,irq=20})
*/
static int l_netdrv_setup(lua_State *L) {
    luat_netdrv_conf_t conf = {0};
    conf.id = luaL_checkinteger(L, 1);
    conf.impl = luaL_optinteger(L, 2, 0);
    conf.irqpin = 255; // 默认无效
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

        if (lua_getfield(L, 3, "mtu") == LUA_TNUMBER) {
            conf.mtu = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);

        if (lua_getfield(L, 3, "flags") == LUA_TNUMBER) {
            conf.flags = luaL_checkinteger(L, -1);
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
    if (lua_type(L, 2) == LUA_TSTRING) {
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

/*
设置或读取ipv4地址
@api netdrv.ipv4(id, addr, mark, gw)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@string ipv4地址,如果是读取就不需要传
@string 掩码
@string 网关
@return string ipv4地址
@return string 掩码
@return string 网关
@usage
-- 注意, 不是所有netdrv都支持设置的, 尤其4G Cat.1自带的netdrv就不能设置ipv4
-- 注意, 设置ipv4时, DHCP要处于关闭状态!!
-- 当前设置ip但ip值非法, 不返回任何东西
-- 如果设置ip且ip值合法, 会返回ip, mask, gw
*/
static int l_netdrv_ipv4(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    const char* tmp = NULL;
    luat_ip_addr_t ip;
    luat_ip_addr_t netmask;
    luat_ip_addr_t gw;
    int ret = 0;
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return 0;
    }
    if (lua_isstring(L, 2) && lua_isstring(L, 3) && lua_isstring(L, 4)) {
        luat_netdrv_dhcp(id, 0); // 自动关闭DHCP
        tmp = luaL_checkstring(L, 2);
        ret = ipaddr_aton(tmp, &ip);
        if (!ret) {
            LLOGW("非法IP[%d] %s %d", id, tmp, ret);
            return 0;
        }
        tmp = luaL_checkstring(L, 3);
        ret = ipaddr_aton(tmp, &netmask);
        if (!ret) {
            LLOGW("非法MARK[%d] %s %d", id, tmp, ret);
            return 0;
        }
        tmp = luaL_checkstring(L, 4);
        ret = ipaddr_aton(tmp, &gw);
        if (ret == 0) {
            LLOGW("非法GW[%d] %s %d", id, tmp, ret);
            return 0;
        }
        network_set_static_ip_info(id, &ip, &netmask, &gw, NULL);
    }
    char buff[16] = {0};
    char buff2[16] = {0};
    char buff3[16] = {0};
    ipaddr_ntoa_r(&netdrv->netif->ip_addr, buff, 16);
    ipaddr_ntoa_r(&netdrv->netif->netmask, buff2, 16);
    ipaddr_ntoa_r(&netdrv->netif->gw, buff3, 16);
    lua_pushstring(L, buff);
    lua_pushstring(L, buff2);
    lua_pushstring(L, buff3);
    return 3;
}

/*
开启或关闭NAPT
@api netdrv.napt(id)
@int 网关适配器的id
@return bool 合法值就返回true, 否则返回nil
@usage

-- 使用4G网络作为主网关出口
netdrv.napt(socket.LWIP_GP)

-- 关闭napt功能
netdrv.napt(-1)
*/
extern int luat_netdrv_gw_adapter_id;
static int l_netdrv_napt(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id < 0) {
        LLOGD("NAPT is disabled");
        luat_netdrv_gw_adapter_id = id;
        lua_pushboolean(L, 1);
        return 1;
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return 0;
    }
    LLOGD("NAPT is enabled gw %d", id);
    luat_netdrv_gw_adapter_id = id;
    lua_pushboolean(L, 1);
    return 1;
}

/*
获取netdrv的物理连接状态
@api netdrv.link(id)
@int netdrv的id, 例如 socket.LWIP_ETH
@return bool 已连接返回true, 否则返回false. 如果id对应的netdrv不存在,返回nil
@usage
-- 注意, 本函数仅支持读取, 而且不能ip状态, 即是否能联网
*/
static int l_netdrv_link(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id < 0) {
        return 0; // 非法id
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return 0;
    }
    lua_pushboolean(L, netif_is_link_up(netdrv->netif));
    return 1;
}

/*
获取netdrv的网络状态
@api netdrv.ready(id)
@int netdrv的id, 例如 socket.LWIP_ETH
@return bool 已连接返回true, 否则返回false. 如果id对应的netdrv不存在,返回nil
@usage
-- 注意, 本函数仅支持读取, 即判断是否能通信, 不代表IP状态
*/
static int l_netdrv_ready(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id < 0) {
        return 0; // 非法id
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return 0;
    }
    lua_pushboolean(L, netif_is_link_up(netdrv->netif) && !ip_addr_isany(&netdrv->netif->ip_addr));
    return 1;
}

/*
给具体的驱动发送控制指令
@api netdrv.ctrl(id, cmd, arg)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@int 指令, 例如 netdrv.CTRL_RESET
@int 参数, 例如 netdrv.RESET_HARD
@return boolean 成功与否
@usage
-- 重启网卡, 仅CH390H支持, 其他网络设备暂不支持
-- 本函数于 2025.4.14 新增
netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_RESET, netdrv.RESET_HARD)
*/
static int l_netdrv_ctrl(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int cmd = luaL_checkinteger(L, 2);
    int arg = luaL_checkinteger(L, 3);
    luat_netdrv_t* drv = luat_netdrv_get(id);
    if (drv == NULL) {
        LLOGW("not such netdrv %d", id);
        return 0;
    }
    if (drv->ctrl == NULL) {
        LLOGW("netdrv %d not support ctrl", id);
        return 0;
    }
    int ret = drv->ctrl(drv, drv->userdata, cmd, arg);
    lua_pushboolean(L, ret == 0);
    lua_pushinteger(L, ret);
    return 2;
}

/*
设置调试信息输出
@api netdrv.debug(id, enable)
@int 网络适配器编号, 例如 socket.LWIP_ETH, 如果传0就是全局调试开关
@boolean 是否开启调试信息输出
@return boolean 成功与否
@usage
-- 打开netdrv全局调试开关
netdrv.debug(0, true)
*/
static int l_netdrv_debug(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int enable = lua_toboolean(L, 2);
    luat_netdrv_debug_set(id, enable);
    return 0;
}


#include "rotable2.h"
static const rotable_Reg_t reg_netdrv[] =
{
    { "setup" ,         ROREG_FUNC(l_netdrv_setup )},
    { "dhcp",           ROREG_FUNC(l_netdrv_dhcp)},
    { "mac",            ROREG_FUNC(l_netdrv_mac)},
    { "ipv4",           ROREG_FUNC(l_netdrv_ipv4)},
    { "napt",           ROREG_FUNC(l_netdrv_napt)},
    { "link",           ROREG_FUNC(l_netdrv_link)},
    { "ready",          ROREG_FUNC(l_netdrv_ready)},

    { "ctrl",           ROREG_FUNC(l_netdrv_ctrl)},
    { "debug",          ROREG_FUNC(l_netdrv_debug)},

    //@const CH390 number 南京沁恒CH390系列,支持CH390D/CH390H, SPI通信
    { "CH390",          ROREG_INT(1)},
    { "UART",           ROREG_INT(16)}, // UART形式的网卡, 不带MAC, 直接IP包
    //@const WHALE number 虚拟网卡
    { "WHALE",          ROREG_INT(64)}, // 通用WHALE设备

    //@const CTRL_RESET number 控制类型-复位,当前仅支持CH390H
    { "CTRL_RESET",     ROREG_INT(LUAT_NETDRV_CTRL_RESET)},
    //@const CTRL_RESET number 请求对网卡硬复位,当前仅支持CH390H
    { "RESET_HARD",     ROREG_INT(0x101)},
    //@const CTRL_RESET number 请求对网卡硬复位,当前仅支持CH390H
    { "RESET_SOFT",     ROREG_INT(0x102)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_netdrv( lua_State *L ) {
    luat_newlib2(L, reg_netdrv);
    return 1;
}
