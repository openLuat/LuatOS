
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
#include "luat_netdrv_napt.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_event.h"
#include "net_lwip2.h"

#include "lwip/ip.h"
#include "lwip/ip4.h"

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
    size_t len = 0;
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

        #ifdef LUAT_USE_NETDRV_WG
        // WG的配置参数比较多, 放在这里面传递
        // 需要的参数有, private_key, public_key, endpoint, port, address, dns, mtu
        if (lua_getfield(L, 3, "wg_private_key") == LUA_TSTRING) {
            conf.wg_private_key = luaL_checklstring(L, -1, &len);
        };
        lua_pop(L, 1);
        // 本地端口
        if (lua_getfield(L, 3, "wg_listen_port") == LUA_TNUMBER) {
            conf.wg_listen_port = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);
        // keepalive时长
        if (lua_getfield(L, 3, "wg_keepalive") == LUA_TNUMBER) {
            conf.wg_keepalive = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);
        // 预分享密钥
        if (lua_getfield(L, 3, "wg_preshared_key") == LUA_TSTRING) {
            conf.wg_preshared_key = luaL_checklstring(L, -1, &len);
        };
        lua_pop(L, 1);

        // 对端信息, 公钥, IP地址, 端口
        if (lua_getfield(L, 3, "wg_endpoint_key") == LUA_TSTRING) {
            conf.wg_endpoint_key = luaL_checklstring(L, -1, &len);
        };
        lua_pop(L, 1);
        if (lua_getfield(L, 3, "wg_endpoint_ip") == LUA_TSTRING) {
            conf.wg_endpoint_ip = luaL_checklstring(L, -1, &len);
        };
        lua_pop(L, 1);
        if (lua_getfield(L, 3, "wg_endpoint_port") == LUA_TNUMBER) {
            conf.wg_endpoint_port = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);
        #endif
    }
    luat_netdrv_t* ret = luat_netdrv_setup(&conf);
    lua_pushboolean(L, ret != NULL);
    return 1;
}

/*
开启或关闭DHCP
@api netdrv.dhcp(id, enable, name)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@boolean 开启或者关闭
@string dhcp主机名称, 可选, 最长31字节，填""清除
@return boolean 成功与否
@usgae
-- 注意, 并非所有网络设备都支持关闭DHCP, 例如4G Cat.1
-- name参数于2025.9.23添加
netdrv.dhcp(socket.LWIP_ETH, true)
netdrv.dhcp(socket.LWIP_ETH, true, "LuatOS")
*/
static int l_netdrv_dhcp(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int enable = lua_toboolean(L, 2);
    if (lua_isstring(L, 3)) {
        size_t len = 0;
        const char* data = NULL;
        luat_netdrv_t *drv = NULL;
        data = luaL_checklstring(L, 3, &len);
        drv = luat_netdrv_get(id);
        if(((len + 1) > 32) || (drv == NULL) || (drv->ulwip == NULL)) {
            LLOGD("dhcp name set fail");
            lua_pushboolean(L, 0);
            return -1;
        }
        if(0 == len){
            memset(drv->ulwip->dhcp_client.name, 0x00, 32);
        } else {
            memcpy(drv->ulwip->dhcp_client.name, data, len + 1);
        }
    }
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
    uint8_t buff[6] = {0};
    char tmpbuff[13] = {0};
    size_t len = 0;
    if (lua_type(L, 2) == LUA_TSTRING) {
        const char* tmp = luaL_checklstring(L, 2, &len);
        if (len != 6) {
            return 0;
        }
        luat_netdrv_mac(id, tmp, (char*)buff);
    }
    else {
        luat_netdrv_mac(id, NULL, (char*)buff);
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
static int l_netdrv_napt(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id < 0) {
        LLOGD("NAPT is disabled");
        luat_netdrv_napt_enable(id);
        lua_pushboolean(L, 1);
        return 1;
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        LLOGE("对应的网关netdrv不存在或未就绪 %d", id);
        return 0;
    }
    LLOGD("NAPT is enabled gw %d", id);
    luat_netdrv_napt_enable(id);
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

/*
设置遥测功能（还未实现全部功能）
@api netdrv.mreport(config, value)
@string 配置项
@boolean 设置功能开关
@return boolean 成功与否
@usage
-- 设置开启与关闭
netdrv.mreport("enable", true)
netdrv.mreport("enable", false)

-- 立即上报一次, 无参数的方式调用
netdrv.mreport()

-- 设置自定义数据
netdrv.mreport("custom", {abc=1234})
-- 清除自定义数据
netdrv.mreport("custom")
*/
extern int l_mreport_config(lua_State* L);


/*
发起ping(异步的)
@api netdrv.ping(id, ip, len)
@int 网络适配器的id
@string 目标ip地址,不支持域名!!
@int ping包大小,默认128字节,可以不传
@return bool 成功与否, 仅代表发送与否,不代表服务器已经响应
@usage
-- 本功能在2025.9.3新增
sys.taskInit(function()
    -- 要等联网了才能ping
    sys.waitUntil("IP_READY")
    sys.wait(1000)
    while 1 do
        -- 必须指定使用哪个网卡
        netdrv.ping(socket.LWIP_GP, "121.14.77.221")
        sys.waitUntil("PING_RESULT", 3000)
        sys.wait(3000)
    end
end)

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)
*/
extern int l_icmp_ping(lua_State *L);

static int s_socket_evt_ref[NW_ADAPTER_QTY] = {0};

static int l_socket_evt_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    netdrv_tcp_evt_t* evt = (netdrv_tcp_evt_t*)ptr;
    int ref = s_socket_evt_ref[evt->id];
    if (ref == 0) {
        LLOGW("socket evt cb no lua ref");
        luat_heap_free(ptr);
        return 0;
    }
    // LLOGD("socket evt cb %d %d lua function %d", evt->id, evt->flags, ref);
    // 取出函数
    lua_geti(L, LUA_REGISTRYINDEX, ref);
    if (!lua_isfunction(L, -1)) {
        LLOGW("socket evt cb ref not function");
        lua_pop(L, 1);
        luat_heap_free(ptr);
        return 0;
    }
    lua_pushinteger(L, evt->id);
    switch (evt->flags)
    {
    case 0x81:
        lua_pushstring(L, "create");
        break;
    case 0x82:
        lua_pushstring(L, "release");
        break;
    case 0x83:
        lua_pushstring(L, "connecting");
        break;
    case EV_NW_TIMEOUT - EV_NW_RESET:
        lua_pushstring(L, "timeout");
        break;
    case EV_NW_SOCKET_CLOSE_OK - EV_NW_RESET:
        lua_pushstring(L, "closed");
        break;
    case EV_NW_SOCKET_CONNECT_OK - EV_NW_RESET:
        lua_pushstring(L, "connected");
        break;
    case EV_NW_SOCKET_REMOTE_CLOSE - EV_NW_RESET:
        lua_pushstring(L, "remote_close");
        break;
    case EV_NW_SOCKET_ERROR - EV_NW_RESET:
        lua_pushstring(L, "error");
        break;
    case EV_NW_DNS_RESULT - EV_NW_RESET:
        lua_pushstring(L, "dns_result");
        break;
    
    default:
        lua_pushstring(L, "unknown");
        break;
    }
    lua_newtable(L);
    // 填充参数表 远端ip, 远端端口, 本地ip, 本地端口
    char buff[32] = {0};
    if (!ip_addr_isany(&evt->remote_ip)) {
        ipaddr_ntoa_r(&evt->remote_ip, buff, 32);
        lua_pushstring(L, buff);
        lua_setfield(L, -2, "remote_ip");
    }

    if (!ip_addr_isany(&evt->online_ip)) {
        ipaddr_ntoa_r(&evt->online_ip, buff, 32);
        lua_pushstring(L, buff);
        lua_setfield(L, -2, "online_ip");
    }

    lua_pushinteger(L, evt->remote_port);
    lua_setfield(L, -2, "remote_port");

    switch (evt->proto)
    {
    case 1:
        lua_pushstring(L, "tcp");
        break;
    case 2:
        lua_pushstring(L, "udp");
        break;
    case 3:
        lua_pushstring(L, "http");
        break;
    case 4:
        lua_pushstring(L, "mqtt");
        break;
    case 5:
        lua_pushstring(L, "websocket");
        break;
    default:
        lua_pushstring(L, "unknown");
        break;
    }
    lua_setfield(L, -2, "proto");

    // p = ipaddr_ntoa_r(&evt->local_ip, buff, 32);
    // lua_pushstring(L, p);
    // lua_setfield(L, -2, "local_ip");

    // lua_pushinteger(L, evt->local_port);
    // lua_setfield(L, -2, "local_port");

    if (evt->domain_name[0]) {
        lua_pushstring(L, evt->domain_name);
        lua_setfield(L, -2, "domain_name");
    }

    lua_call(L, 3, 0);
    // 释放内存
    luat_heap_free(ptr);

    return 0;
}

static void luat_socket_evt_cb(netdrv_tcp_evt_t* evt, void* userdata) {
    rtos_msg_t msg = {0};
    msg.handler = l_socket_evt_cb;
    msg.ptr = luat_heap_malloc(sizeof(netdrv_tcp_evt_t));
    if (msg.ptr == NULL) {
        LLOGE("socket evt cb no mem");
        return;
    }
    memcpy(msg.ptr, evt, sizeof(netdrv_tcp_evt_t));
    luat_msgbus_put(&msg, 0);
}

// 监听socket事件
/*
订阅网络事件
@api netdrv.on(adapter_id, event_type, callback)
@int 网络适配器的id
@int 事件总类型, 当前支持 netdrv.EVT_SOCKET
@function 回调函数 function(id, event, params)
@return bool 成功与否,成功返回true,否则返回nil
@usage
-- 订阅socket连接状态变化事件
netdrv.on(socket.LWIP_ETH, netdrv.EVT_SOCKET, function(id, event, params)
    -- id 是网络适配器id
    -- event是事件id, 字符串类型, 
        - create 创建socket对象
        - release 释放socket对象
        - connecting 正在连接, 域名解析成功后出现
        - connected 连接成功, TCP三次握手成功后出现
        - closed 连接关闭
        - remote_close 远程关闭, 网络中断,或者服务器主动断开
        - timeout dns解析超时,或者tcp连接超时
        - error 错误,包括一切异常错误
    -- params是参数表
        - remote_ip 远端ip地址,未必存在
        - remote_port 远端端口,未必存在
        - online_ip 实际连接的ip地址,未必存在
        - domain_name 远端域名,如果是通过域名连接的话, release时没有这个值, create时也没有
    log.info("netdrv", "socket event", id, event, json.encode(params or {}))
    if params then
        -- params里会有remote_ip, remote_port等信息, 可按需获取
        local remote_ip = params.remote_ip
        local remote_port = params.remote_port
        local domain_name = params.domain_name
        log.info("netdrv", "socket event", "remote_ip", remote_ip, "remote_port", remote_port, "domain_name", domain_name)
    end
end)
*/
static int l_netdrv_on(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id < 0) {
        return 0; // 非法id
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return 0;
    }
    int event_id = luaL_checkinteger(L, 2);
    if (event_id == 0) {
        if (s_socket_evt_ref[id]) {
            luaL_unref(L, LUA_REGISTRYINDEX, s_socket_evt_ref[id]);
            s_socket_evt_ref[id] = 0;
        }
        luat_netdrv_register_socket_event_cb(id, 0, NULL, NULL);
        lua_pushboolean(L, 1);
        return 1;
    }
    else if (event_id == 1) {
        if (!lua_isfunction(L, 3)) {
            return 0;
        }
        lua_pushvalue(L, 3);
        s_socket_evt_ref[id] = luaL_ref(L, LUA_REGISTRYINDEX);
        // LLOGD("register socket event cb %d", s_socket_evt_ref[id]);
        luat_netdrv_register_socket_event_cb(id, 0xFF, luat_socket_evt_cb, NULL);
        lua_pushboolean(L, 1);
        return 1;
    }
    LLOGW("not support event type %d", event_id);
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
    { "on",ROREG_FUNC(l_netdrv_on)},
#ifdef LUAT_USE_MREPORT
    { "mreport",        ROREG_FUNC(l_mreport_config)},
#endif
#ifdef LUAT_USE_ICMP
    { "ping",           ROREG_FUNC(l_icmp_ping)},
#endif

    //@const CH390 number 南京沁恒CH390系列,支持CH390D/CH390H, SPI通信
    { "CH390",          ROREG_INT(1)},
    { "UART",           ROREG_INT(16)}, // UART形式的网卡, 不带MAC, 直接IP包
    #ifdef LUAT_USE_NETDRV_WG
    { "WG",             ROREG_INT(32)}, // Wireguard VPN网卡
    #endif
    //@const WHALE number 虚拟网卡
    { "WHALE",          ROREG_INT(64)}, // 通用WHALE设备

    //@const CTRL_RESET number 控制类型-复位,当前仅支持CH390H
    { "CTRL_RESET",     ROREG_INT(LUAT_NETDRV_CTRL_RESET)},
    //@const RESET_HARD number 请求对网卡硬复位,当前仅支持CH390H
    { "RESET_HARD",     ROREG_INT(0x101)},
    //@const RESET_SOFT number 请求对网卡软复位,当前仅支持CH390H
    { "RESET_SOFT",     ROREG_INT(0x102)},

    //@const EVT_SOCKET number 事件类型-socket事件
    { "EVT_SOCKET",     ROREG_INT(1)}, // socket事件

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_netdrv( lua_State *L ) {
    luat_newlib2(L, reg_netdrv);
    return 1;
}
