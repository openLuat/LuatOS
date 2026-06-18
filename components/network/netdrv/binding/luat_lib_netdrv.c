
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
#include "luat_zbuff.h"
#include "luat_netdrv.h"
#include "luat_netdrv_napt.h"
#include "luat_netdrv_drv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_event.h"
#include "net_lwip2.h"

#include "lwip/ip.h"
#include "lwip/ip4.h"
#include "lwip/tcpip.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

/*
初始化指定netdrv设备
@api netdrv.setup(id, tp, opts)
@int 网络适配器编号, 例如 socket.LWIP_ETH, socket.LWIP_USER0
@int 实现方式,如果是设备自带的硬件,那就不需要传, 外挂设备需要传,当前支持CH390H/D/OPENVPN等
@table 外挂方式,需要额外的参数,参考示例
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

-- 初始化 OpenVPN 虚拟网卡 (需要通过其他网卡提供网络连接)
-- 仅支持 TLS 证书认证
local ok = netdrv.setup(socket.LWIP_USER0, netdrv.OPENVPN, {
    ovpn_remote_ip = "10.0.0.1",                -- VPN 服务器IP地址
    ovpn_remote_port = 1194,                     -- VPN 服务器端口 (默认 1194)
    ovpn_ca_cert = ca_cert_pem_string,           -- CA 证书 (PEM 格式, 可选)
    ovpn_client_cert = client_cert_pem_string,   -- 客户端证书 (PEM 格式, 可选)
    ovpn_client_key = client_key_pem_string,     -- 客户端私钥 (PEM 格式, 可选)
})
-- 完整示例见 openvpn/example_netdrv.lua
-- 详细说明见 openvpn/usage.md 和 openvpn/PARAMETER_HANDLING.md
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
        if (conf.impl == LUAT_NETDRV_IMPL_WG) {
            conf.wg_conf = luat_heap_malloc(sizeof(luat_netdrv_wg_conf_t));
            // WG的配置参数比较多, 放在这里面传递
            // 需要的参数有, private_key, public_key, endpoint, port, address, dns, mtu
            if (lua_getfield(L, 3, "wg_private_key") == LUA_TSTRING) {
                conf.wg_conf->wg_private_key = luaL_checklstring(L, -1, &len);
            };
            lua_pop(L, 1);
            // 本地端口
            if (lua_getfield(L, 3, "wg_listen_port") == LUA_TNUMBER) {
                conf.wg_conf->wg_listen_port = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
            // keepalive时长
            if (lua_getfield(L, 3, "wg_keepalive") == LUA_TNUMBER) {
                conf.wg_conf->wg_keepalive = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
            // 预分享密钥
            if (lua_getfield(L, 3, "wg_preshared_key") == LUA_TSTRING) {
                conf.wg_conf->wg_preshared_key = luaL_checklstring(L, -1, &len);
            };
            lua_pop(L, 1);

            // 对端信息, 公钥, IP地址, 端口
            if (lua_getfield(L, 3, "wg_endpoint_key") == LUA_TSTRING) {
                conf.wg_conf->wg_endpoint_key = luaL_checklstring(L, -1, &len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "wg_endpoint_ip") == LUA_TSTRING) {
                conf.wg_conf->wg_endpoint_ip = luaL_checklstring(L, -1, &len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "wg_endpoint_port") == LUA_TNUMBER) {
                conf.wg_conf->wg_endpoint_port = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
        }
        #endif

        #ifdef LUAT_USE_NETDRV_OPENVPN
        if (conf.impl == LUAT_NETDRV_IMPL_OPENVPN) {
            conf.ovpn_conf = luat_heap_malloc(sizeof(luat_netdrv_openvpn_conf_t));
            if (conf.ovpn_conf == NULL) {
                lua_pushboolean(L, 0);
                return 1;
            }
            memset(conf.ovpn_conf, 0, sizeof(luat_netdrv_openvpn_conf_t));
            // OpenVPN的配置参数
            if (lua_getfield(L, 3, "ovpn_remote_ip") == LUA_TSTRING) {
                conf.ovpn_conf->ovpn_remote_ip = luaL_checklstring(L, -1, &len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_remote_port") == LUA_TNUMBER) {
                conf.ovpn_conf->ovpn_remote_port = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_ca_cert") == LUA_TSTRING) {
                conf.ovpn_conf->ovpn_ca_cert = luaL_checklstring(L, -1, &conf.ovpn_conf->ovpn_ca_cert_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_client_cert") == LUA_TSTRING) {
                conf.ovpn_conf->ovpn_client_cert = luaL_checklstring(L, -1, &conf.ovpn_conf->ovpn_client_cert_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_client_key") == LUA_TSTRING) {
                conf.ovpn_conf->ovpn_client_key = luaL_checklstring(L, -1, &conf.ovpn_conf->ovpn_client_key_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_retry_enable") == LUA_TBOOLEAN) {
                conf.ovpn_conf->ovpn_retry_enable = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_retry_base_ms") == LUA_TNUMBER) {
                conf.ovpn_conf->ovpn_retry_base_ms = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_retry_max_ms") == LUA_TNUMBER) {
                conf.ovpn_conf->ovpn_retry_max_ms = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_username") == LUA_TSTRING) {
                conf.ovpn_conf->ovpn_username = luaL_checklstring(L, -1, &conf.ovpn_conf->ovpn_username_len);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ovpn_password") == LUA_TSTRING) {
                conf.ovpn_conf->ovpn_password = luaL_checklstring(L, -1, &conf.ovpn_conf->ovpn_password_len);
            }
            lua_pop(L, 1);
            lua_pop(L, 1);
        }
        #endif
    }
    luat_netdrv_t* ret = luat_netdrv_setup(&conf);
    lua_pushboolean(L, ret != NULL);
    if (conf.wg_conf) {
        luat_heap_free(conf.wg_conf);
    }
    if (conf.ovpn_conf) {
        luat_heap_free(conf.ovpn_conf);
    }
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
-- 注意, 并非所有网络设备都支持关闭DHCP, 例如4G Cat.1自带的netdrv就不支持关闭DHCP
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
            LLOGD("adapter %d dhcp name set fail", id);
            lua_pushboolean(L, 0);
            return 1;
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
        LLOGW("对应的netdrv不存在或未就绪 %d %p", id, netdrv);
        return 0;
    }
    #ifdef LUAT_USE_MOBILE
    if (NW_ADAPTER_INDEX_LWIP_GPRS == id && !luat_netdrv_is_ready(id)) {
        lua_pushliteral(L, "");
        lua_pushliteral(L, "");
        lua_pushliteral(L, "");
        return 3;
    }
    #endif
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
        ret = network_set_static_ip_info(id, &ip, &netmask, &gw, NULL);
        LLOGI("设置IP[%d] %s %s %s ret %d", id,
            luaL_checkstring(L, 2),
            luaL_checkstring(L, 3),
            luaL_checkstring(L, 4),
            ret
        );
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
开启或关闭NAPT。关闭时会清除所有映射表。开启NAPT前请确保网关适配器已就绪。
@api netdrv.napt(id)
@int 网关适配器的id, 传-1或nil关闭NAPT并清除所有映射表
@return bool 合法值就返回true, 否则返回nil
@usage

-- 使用4G网络作为主网关出口
netdrv.napt(socket.LWIP_GP)

-- 关闭napt功能, 清除所有映射表
netdrv.napt(-1)
*/
static int l_netdrv_napt(lua_State *L) {
    int id = luaL_optinteger(L, 1, -1);
    if (id < 0) {
        LLOGI("NAPT is disabled, cleaning up all mappings");
        luat_netdrv_napt_disable();
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
-- 注意, 本函数仅支持读取, 而且不代表ip状态, 即是否能联网
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
    #ifdef LUAT_USE_MOBILE
    if (NW_ADAPTER_INDEX_LWIP_GPRS == id && !luat_netdrv_is_ready(id)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    #endif
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
-- 当id传-1时, 会返回一个位掩码, 每一位代表一个网卡的ready状态
-- 例如有4个网卡, 那么返回值0b00001101就代表0号,2号网卡ready,1号,3号网卡不ready
local ready, netstat = netdrv.ready(-1)
log.info("netdrv", ready, "netstat", string.format("0x%X", netstat))
*/
static int l_netdrv_ready(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int ret = 0;
    if (id < 0) {
        ret = luat_netdrv_simple_stat();
        lua_pushboolean(L, ret > 0);
        lua_pushinteger(L, ret);
        return 2;
    }
    ret = luat_netdrv_is_ready(id);
    #ifdef LUAT_USE_MOBILE
    if (NW_ADAPTER_INDEX_LWIP_GPRS == id && !luat_netdrv_is_ready(id)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    #endif
    lua_pushboolean(L, ret);
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

-- 关闭CH390H通信并下电PHY，可用于降功耗；第三个参数1=关闭，0=重新启动
netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_DOWN, 1)
netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_DOWN, 0)
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
设置遥测功能，开启后，会自动上报设备信息，2025/9/25启用
@api netdrv.mreport(config, value)
@string 配置项
@boolean 设置功能开关
@return boolean 成功与否
@usage
-- 设置开启与关闭
netdrv.mreport("enable", true)
netdrv.mreport("enable", false)

-- 设置使用的网络适配器，2025/10/30启用
netdrv.mreport("adapter_id", socket.LWIP_GP)
netdrv.mreport("adapter_id", socket.LWIP_STA)
netdrv.mreport("adapter_id", socket.LWIP_ETH)

-- 立即上报一次, 无参数的方式调用
netdrv.mreport()

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

// netdrv 事件 Lua 绑定 (l_netdrv_on + 内部 static 状态/回调) 已拆分到
// components/network/netdrv/binding/luat_lib_netdrv_event.c,
// 这里仅通过 extern 引用, reg_netdrv[] 的 {"on", ...} 条目照旧有效.
extern int l_netdrv_on(lua_State *L);

// send_raw: 把 zbuff 原始数据按 target 方向投到 netdrv 链路
typedef struct netdrv_send_msg {
    luat_netdrv_t* drv;
    uint16_t len;
    uint8_t buff[4]; // flexible array
} netdrv_send_msg_t;

static void do_send_raw_to_hw(void* args) {
    netdrv_send_msg_t* m = (netdrv_send_msg_t*)args;
    if (m == NULL) return;
    // 走统一出口 pkg_output: null 检查 + drv->dataout 在那里集中处理
    luat_netdrv_pkg_output(m->drv->id, LUAT_NETDRV_CH_HW, m->buff, m->len);
    luat_heap_free(m);
}

// CH_LWIP: 跳过 NAPT, 直接注入 LWIP (相当于 post-NAPT 入口)
static void do_send_raw_to_lwip(void* args) {
    netdrv_send_msg_t* m = (netdrv_send_msg_t*)args;
    if (m == NULL) return;
    if (m->drv && m->drv->netif) {
        luat_netdrv_netif_input_proxy(m->drv->netif, m->buff, m->len);
    }
    luat_heap_free(m);
}

// CH_NAPT: 先过 NAPT, 未消费则继续到 LWIP (相当于 pre-NAPT 入口)
static void do_send_raw_to_napt(void* args) {
    netdrv_send_msg_t* m = (netdrv_send_msg_t*)args;
    if (m == NULL) return;
    int napt_ret = luat_netdrv_napt_pkg_input(m->drv->id, m->buff, (size_t)m->len);
    if (napt_ret == 0 && m->drv && m->drv->netif) {
        // NAPT 未消费, 继续注入 LWIP
        luat_netdrv_netif_input_proxy(m->drv->netif, m->buff, m->len);
    }
    luat_heap_free(m);
}

/*
直接向 netdrv 链路投递原始数据包
@api netdrv.send_raw(id, target, zbuff, len)
@int 网络适配器编号
@int 投递目标: netdrv.CH_HW / netdrv.CH_LWIP / netdrv.CH_NAPT
@zbuff 待发送的 zbuff, used 长度即默认发送长度
@int 可选, 发送长度(<= zbuff.used), 默认 zbuff.used
@return int 实际进入发送队列的字节数, 失败返回 nil+err
@usage
-- 立即以默认长度发送
netdrv.send_raw(socket.LWIP_ETH, netdrv.CH_HW, zb)
-- 只发前 64 字节
netdrv.send_raw(socket.LWIP_ETH, netdrv.CH_HW, zb, 64)
*/
static int l_netdrv_send_raw(lua_State *L) {
    int id     = luaL_checkinteger(L, 1);
    int target = luaL_checkinteger(L, 2);
    luat_zbuff_t* buff = (luat_zbuff_t*)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE);
    size_t used = buff ? buff->used : 0;
    int len_in = (int)luaL_optinteger(L, 4, (lua_Integer)used);
    if (len_in < 0) len_in = 0;
    if (len_in > 0xFFFF) len_in = 0xFFFF;
    uint16_t len = (uint16_t)len_in;

    if (target == LUAT_NETDRV_CH_HW) {
        luat_netdrv_t* drv = luat_netdrv_get(id);
        if (!drv || !drv->dataout) {
            lua_pushnil(L);
            lua_pushliteral(L, "netdrv not available");
            return 2;
        }
        if (!buff || !buff->addr) {
            lua_pushnil(L);
            lua_pushliteral(L, "zbuff invalid");
            return 2;
        }
        if (len == 0) {
            lua_pushnil(L);
            lua_pushliteral(L, "len is 0");
            return 2;
        }
        if (len > buff->used) {
            lua_pushnil(L);
            lua_pushliteral(L, "len out of range");
            return 2;
        }
        netdrv_send_msg_t* m = (netdrv_send_msg_t*)luat_heap_malloc(sizeof(netdrv_send_msg_t) + len - 4);
        if (!m) {
            lua_pushnil(L);
            lua_pushliteral(L, "oom");
            return 2;
        }
        m->drv = drv;
        m->len = len;
        memcpy(m->buff, buff->addr, len);
        if (tcpip_callback_with_block(do_send_raw_to_hw, m, 0) != ERR_OK) {
            luat_heap_free(m);
            lua_pushnil(L);
            lua_pushliteral(L, "tcpip queue full");
            return 2;
        }
        lua_pushinteger(L, len);
        return 1;
    }
    else if (target == LUAT_NETDRV_CH_LWIP) {
        // CH_LWIP: 跳过 NAPT, 直接注入 LWIP
        luat_netdrv_t* drv = luat_netdrv_get(id);
        if (!drv || !drv->netif) {
            lua_pushnil(L);
            lua_pushliteral(L, "netdrv not available");
            return 2;
        }
        if (!buff || !buff->addr) {
            lua_pushnil(L);
            lua_pushliteral(L, "zbuff invalid");
            return 2;
        }
        if (len == 0) {
            lua_pushnil(L);
            lua_pushliteral(L, "len is 0");
            return 2;
        }
        if (len > buff->used) {
            lua_pushnil(L);
            lua_pushliteral(L, "len out of range");
            return 2;
        }
        netdrv_send_msg_t* m = (netdrv_send_msg_t*)luat_heap_malloc(sizeof(netdrv_send_msg_t) + len - 4);
        if (!m) {
            lua_pushnil(L);
            lua_pushliteral(L, "oom");
            return 2;
        }
        m->drv = drv;
        m->len = len;
        memcpy(m->buff, buff->addr, len);
        if (tcpip_callback_with_block(do_send_raw_to_lwip, m, 0) != ERR_OK) {
            luat_heap_free(m);
            lua_pushnil(L);
            lua_pushliteral(L, "tcpip queue full");
            return 2;
        }
        lua_pushinteger(L, len);
        return 1;
    }
    else if (target == LUAT_NETDRV_CH_NAPT) {
        // CH_NAPT: 先过 NAPT, 未消费则注入 LWIP
        luat_netdrv_t* drv = luat_netdrv_get(id);
        if (!drv || !drv->netif) {
            lua_pushnil(L);
            lua_pushliteral(L, "netdrv not available");
            return 2;
        }
        if (!buff || !buff->addr) {
            lua_pushnil(L);
            lua_pushliteral(L, "zbuff invalid");
            return 2;
        }
        if (len == 0) {
            lua_pushnil(L);
            lua_pushliteral(L, "len is 0");
            return 2;
        }
        if (len > buff->used) {
            lua_pushnil(L);
            lua_pushliteral(L, "len out of range");
            return 2;
        }
        netdrv_send_msg_t* m = (netdrv_send_msg_t*)luat_heap_malloc(sizeof(netdrv_send_msg_t) + len - 4);
        if (!m) {
            lua_pushnil(L);
            lua_pushliteral(L, "oom");
            return 2;
        }
        m->drv = drv;
        m->len = len;
        memcpy(m->buff, buff->addr, len);
        if (tcpip_callback_with_block(do_send_raw_to_napt, m, 0) != ERR_OK) {
            luat_heap_free(m);
            lua_pushnil(L);
            lua_pushliteral(L, "tcpip queue full");
            return 2;
        }
        lua_pushinteger(L, len);
        return 1;
    }
    return luaL_error(L, "unknown send_raw target %d", target);
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
    { "on",             ROREG_FUNC(l_netdrv_on)},
    { "send_raw",       ROREG_FUNC(l_netdrv_send_raw)},
#ifdef LUAT_USE_MREPORT
    { "mreport",        ROREG_FUNC(l_mreport_config)},
#endif
#ifdef LUAT_USE_ICMP
    { "ping",           ROREG_FUNC(l_icmp_ping)},
#endif

    //@const CH390 number 南京沁恒CH390系列,支持CH390D/CH390H, SPI通信
    { "CH390",          ROREG_INT(LUAT_NETDRV_IMPL_CH390H)},
    { "UART",           ROREG_INT(LUAT_NETDRV_IMPL_UART)}, // UART形式的网卡, 不带MAC, 直接IP包
    #ifdef LUAT_USE_NETDRV_WG
    { "WG",             ROREG_INT(LUAT_NETDRV_IMPL_WG)}, // Wireguard VPN网卡
    #endif
    //@const WHALE number 虚拟网卡
    { "WHALE",          ROREG_INT(LUAT_NETDRV_IMPL_WHALE)}, // 通用WHALE设备
    #ifdef LUAT_USE_NETDRV_OPENVPN
    { "OPENVPN",        ROREG_INT(LUAT_NETDRV_IMPL_OPENVPN)}, // OpenVPN虚拟网卡
    #endif

    //@const CTRL_RESET number 控制类型-复位,当前仅支持CH390H
    { "CTRL_RESET",     ROREG_INT(LUAT_NETDRV_CTRL_RESET)},
    //@const CTRL_UPDOWN number 控制类型-1=启动UP，0关闭DOWN
    { "CTRL_UPDOWN",    ROREG_INT(LUAT_NETDRV_CTRL_UPDOWN)},
    //@const RESET_HARD number 请求对网卡硬复位,当前仅支持CH390H
    { "RESET_HARD",     ROREG_INT(0x101)},
    //@const RESET_SOFT number 请求对网卡软复位,当前仅支持CH390H
    { "RESET_SOFT",     ROREG_INT(0x102)},

    //@const EVT_SOCKET number 事件类型-socket事件
    { "EVT_SOCKET",     ROREG_INT(LUAT_NETDRV_EVT_SOCKET)},

    //@const CH_HW number 数据包通道-物理硬件 (HW RX = FROM_HW, send_raw target TO_HW)
    { "CH_HW",          ROREG_INT(LUAT_NETDRV_CH_HW)},
    //@const CH_LWIP number 数据包通道-LWIP协议栈 (send_raw target TO_LWIP, 未来 FROM_LWIP)
    { "CH_LWIP",        ROREG_INT(LUAT_NETDRV_CH_LWIP)},
    //@const CH_NAPT number 数据包通道-NAPT层 (send_raw target TO_NAPT, 未来 FROM_NAPT)
    { "CH_NAPT",        ROREG_INT(LUAT_NETDRV_CH_NAPT)},
    //@const EVT_PKG number 事件类型-数据包事件
    { "EVT_PKG",        ROREG_INT(LUAT_NETDRV_EVT_PKG)},

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_netdrv( lua_State *L ) {
    luat_newlib2(L, reg_netdrv);
    return 1;
}
