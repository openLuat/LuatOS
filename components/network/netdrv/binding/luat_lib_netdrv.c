
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
/* 显式包含: 下面 netdrv.CTRL_DNS / netdrv.dns_utest 的编译开关依赖该头推导出的宏,
 * 不能只依赖 net_lwip2.h 的间接引入 */
#include "luat_netdrv_dns.h"
#ifdef LUAT_USE_NETDRV_IPSEC
#include "luat_netdrv_ipsec.h"
#endif
#include "net_lwip2.h"
#include "net_lwip2_dns.h"

#ifdef LUAT_USE_NETDRV_LWIP_ARP
#include "luat_netdrv_lwip_etharp.h"
#endif

#include "lwip/ip.h"
#include "lwip/ip4.h"
#include "lwip/tcpip.h"

#if defined(LUAT_USE_NETDRV_LWIP_ARP) && LWIP_IPV4 && LWIP_ARP
#define LUAT_NETDRV_HAVE_ARP 1
#endif

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

-- 初始化 L2TPv2 虚拟网卡 (LAC, 需要通过其他网卡提供网络连接)
-- 认证支持 PAP + CHAP(MD5); l2tp_secret 可选, 开启 L2TP 隧道认证
local ok = netdrv.setup(socket.LWIP_USER1, netdrv.L2TP, {
    l2tp_remote_ip = "10.0.0.1",                -- LNS IP (必填, 仅IP字面量)
    l2tp_remote_port = 1701,                     -- LNS 端口 (默认 1701)
    l2tp_username = "user",                      -- PPP 用户名 (可选)
    l2tp_password = "pass",                      -- PPP 密码 (可选)
    l2tp_secret = nil,                           -- L2TP 隧道共享密钥 (可选)
    l2tp_mtu = 1450,                             -- PPP MRU (默认 1450)
    l2tp_retry_enable = true,                    -- 失败后自动重连
    l2tp_retry_base_ms = 1000,
    l2tp_retry_max_ms = 60000,
})
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

        // 虚拟/外挂网卡的初始MAC, 6字节字符串; 不传则保持全0(由驱动自己决定).
        // 该参数同时决定IPv6链路本地地址(EUI-64), 因此对IPv6场景是必需的.
        if (lua_getfield(L, 3, "mac") == LUA_TSTRING) {
            size_t mac_len = 0;
            const char* mac = luaL_checklstring(L, -1, &mac_len);
            if (mac_len == 6) {
                memcpy(conf.mac, mac, 6);
            }
            else if (mac_len != 0) {
                LLOGW("netdrv %d 的 mac 参数必须是6字节, 实际 %d 字节, 已忽略", conf.id, (int)mac_len);
            }
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

        #ifdef LUAT_USE_NETDRV_L2TP
        if (conf.impl == LUAT_NETDRV_IMPL_L2TP) {
            conf.l2tp_conf = luat_heap_malloc(sizeof(luat_netdrv_l2tp_conf_t));
            if (conf.l2tp_conf == NULL) {
                lua_pushboolean(L, 0);
                return 1;
            }
            memset(conf.l2tp_conf, 0, sizeof(luat_netdrv_l2tp_conf_t));
            // L2TP的配置参数
            if (lua_getfield(L, 3, "l2tp_remote_ip") == LUA_TSTRING) {
                conf.l2tp_conf->l2tp_remote_ip = luaL_checklstring(L, -1, &len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "l2tp_remote_port") == LUA_TNUMBER) {
                conf.l2tp_conf->l2tp_remote_port = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "l2tp_username") == LUA_TSTRING) {
                conf.l2tp_conf->l2tp_username = luaL_checklstring(L, -1, &conf.l2tp_conf->l2tp_username_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "l2tp_password") == LUA_TSTRING) {
                conf.l2tp_conf->l2tp_password = luaL_checklstring(L, -1, &conf.l2tp_conf->l2tp_password_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "l2tp_secret") == LUA_TSTRING) {
                conf.l2tp_conf->l2tp_secret = luaL_checklstring(L, -1, &conf.l2tp_conf->l2tp_secret_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "l2tp_mtu") == LUA_TNUMBER) {
                conf.l2tp_conf->l2tp_mtu = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "l2tp_retry_enable") == LUA_TBOOLEAN) {
                conf.l2tp_conf->l2tp_retry_enable = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "l2tp_retry_base_ms") == LUA_TNUMBER) {
                conf.l2tp_conf->l2tp_retry_base_ms = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "l2tp_retry_max_ms") == LUA_TNUMBER) {
                conf.l2tp_conf->l2tp_retry_max_ms = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
        }
        #endif

        #ifdef LUAT_USE_NETDRV_IPSEC
        if (conf.impl == LUAT_NETDRV_IMPL_IPSEC) {
            conf.ipsec_conf = luat_heap_malloc(sizeof(luat_netdrv_ipsec_conf_t));
            if (conf.ipsec_conf == NULL) {
                lua_pushboolean(L, 0);
                return 1;
            }
            memset(conf.ipsec_conf, 0, sizeof(luat_netdrv_ipsec_conf_t));
            // IPsec的配置参数
            if (lua_getfield(L, 3, "ipsec_remote_ip") == LUA_TSTRING) {
                conf.ipsec_conf->ipsec_remote_ip = luaL_checklstring(L, -1, &len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_remote_port") == LUA_TNUMBER) {
                conf.ipsec_conf->ipsec_remote_port = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_username") == LUA_TSTRING) {
                conf.ipsec_conf->ipsec_username = luaL_checklstring(L, -1, &conf.ipsec_conf->ipsec_username_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_password") == LUA_TSTRING) {
                conf.ipsec_conf->ipsec_password = luaL_checklstring(L, -1, &conf.ipsec_conf->ipsec_password_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_ca_cert_pem") == LUA_TSTRING) {
                conf.ipsec_conf->ipsec_ca_cert_pem = luaL_checklstring(L, -1, &conf.ipsec_conf->ipsec_ca_cert_pem_len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_san") == LUA_TSTRING) {
                conf.ipsec_conf->ipsec_san = luaL_checklstring(L, -1, &len);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_insecure_cert_ok") == LUA_TBOOLEAN) {
                conf.ipsec_conf->ipsec_insecure_cert_ok = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_mtu") == LUA_TNUMBER) {
                conf.ipsec_conf->ipsec_mtu = luaL_checkinteger(L, -1);
            };
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_retry_enable") == LUA_TBOOLEAN) {
                conf.ipsec_conf->ipsec_retry_enable = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_mobike_enable") == LUA_TBOOLEAN) {
                conf.ipsec_conf->ipsec_mobike_enable = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_retry_base_ms") == LUA_TNUMBER) {
                conf.ipsec_conf->ipsec_retry_base_ms = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            if (lua_getfield(L, 3, "ipsec_retry_max_ms") == LUA_TNUMBER) {
                conf.ipsec_conf->ipsec_retry_max_ms = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
        }
        #endif
    }
    luat_netdrv_t* ret = luat_netdrv_setup(&conf);
    lua_pushboolean(L, ret != NULL);
    #ifdef LUAT_USE_NETDRV_WG
    if (conf.wg_conf) {
        luat_heap_free(conf.wg_conf);
    }
    #endif
    #ifdef LUAT_USE_NETDRV_OPENVPN
    if (conf.ovpn_conf) {
        luat_heap_free(conf.ovpn_conf);
    }
    #endif
    #ifdef LUAT_USE_NETDRV_L2TP
    if (conf.l2tp_conf) {
        luat_heap_free(conf.l2tp_conf);
    }
    #endif
    #ifdef LUAT_USE_NETDRV_IPSEC
    if (conf.ipsec_conf) {
        luat_heap_free(conf.ipsec_conf);
    }
    #endif
    return 1;
}

/*
开启或关闭DHCP
@api netdrv.dhcp(id, enable, name)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@boolean 开启或者关闭
@string dhcp主机名称, 可选, 最长31字节，填""清除
@return boolean 成功与否
@usage
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
        if(((len + 1) > 32) || (drv == NULL)) {
            LLOGW("adapter %d dhcp name set fail", id);
            lua_pushboolean(L, 0);
            return 1;
        }
        if(0 == len){
            memset(drv->dhcp_client.name, 0x00, 32);
        } else {
            memcpy(drv->dhcp_client.name, data, len + 1);
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
        // 最后一个参数固定传 NULL: IPv4 只更新 IPv4 地址, 不会清空已配置的 IPv6 槽位
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
设置或读取ipv6地址
@api netdrv.ipv6(id, addr, prefix, gw)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@string ipv6地址, 如果是读取就不需要传. 设置时必须是合法的IPv6字面量, 不支持域名
@int 前缀长度, 1~128, 可选, 默认64. 仅设置时有效
@string ipv6网关, 可选. 当前仅用于回显, 不写入路由表
@return table 读取时返回 {linklocal={addr=地址,prefix=前缀长度,state=状态}, global={addr=地址,prefix=前缀长度,state=状态}, gw=网关}; 某类地址不存在时不返回对应字段
@return boolean 设置时返回成功与否
@usage
-- 注意: 并非所有netdrv都支持IPv6, 也不代表平台后端(LWIP实现)支持设置
-- 一次读取链路本地地址和全局可路由地址
local info = netdrv.ipv6(socket.LWIP_ETH)
log.info("netdrv", "linklocal", info.linklocal and info.linklocal.addr)
log.info("netdrv", "global", info.global and info.global.addr)

-- 设置静态IPv6地址, 需要先调用 netdrv.setup 初始化网卡
netdrv.ipv6(socket.LWIP_ETH, "2409:8a00:1234:5678::10", 64)
-- 设置链路本地地址(不常用, 一般由系统根据MAC自动生成)
netdrv.ipv6(socket.LWIP_ETH, "fe80::1", 64)
-- 该函数于 2026.01 新增
-- 该接口受 LUAT_USE_NETDRV_IPV6 宏控制, 关闭时整段不参与编译
*/
#ifdef LUAT_USE_NETDRV_IPV6
static void l_netdrv_push_ipv6_item(lua_State *L, struct netif *netif,
                                     const luat_ip_addr_t *ipv6, uint8_t prefix) {
    char buff[64] = {0};
    const char* state = "valid";
    ip6addr_ntoa_r(&ipv6->u_addr.ip6, buff, sizeof(buff));

    if (netif) {
        for (int i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++) {
            if (0 == memcmp(&netif->ip6_addr[i], &ipv6->u_addr.ip6, sizeof(ip6_addr_t))) {
                state = (IP6_ADDR_PREFERRED == (netif->ip6_addr_state[i] & IP6_ADDR_PREFERRED))
                    ? "preferred" : "valid";
                break;
            }
        }
    }

    lua_newtable(L);
    lua_pushstring(L, buff);
    lua_setfield(L, -2, "addr");
    lua_pushinteger(L, prefix);
    lua_setfield(L, -2, "prefix");
    lua_pushstring(L, state);
    lua_setfield(L, -2, "state");
}

static int l_netdrv_ipv6(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    // 第2参数是字符串时为设置模式; 无第2参数时同时读取两类IPv6地址
    int is_set = lua_isstring(L, 2);
    // 非法id: 读取返回空table(与"网卡不存在/无地址"一致), 设置返回 false
    if (id < 0 || id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        LLOGW("非法的netdrv id %d", id);
        if (is_set) {
            lua_pushboolean(L, 0);
        }
        else {
            lua_newtable(L);
        }
        return 1;
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        LLOGW("对应的netdrv不存在或未就绪 %d", id);
        if (is_set) {
            lua_pushboolean(L, 0);
        }
        else {
            lua_newtable(L);
        }
        return 1;
    }
    if (!net_lwip2_ipv6_supported()) {
        LLOGW("当前构建的lwip不支持IPv6");
        if (is_set) {
            lua_pushboolean(L, 0);
        }
        else {
            lua_newtable(L);
        }
        return 1;
    }

    // ==== 设置模式 ====
    if (is_set) {
        size_t len = 0;
        const char* tmp = luaL_checklstring(L, 2, &len);
        char ipstr[64] = {0};
        if (len == 0 || len >= sizeof(ipstr)) {
            LLOGW("ipv6地址长度非法 %d", (int)len);
            lua_pushboolean(L, 0);
            return 1;
        }
        // 去掉两端的方括号写法 "[fe80::1]"
        if (tmp[0] == '[' && tmp[len - 1] == ']') {
            len -= 2;
            memcpy(ipstr, tmp + 1, len);
        }
        else {
            memcpy(ipstr, tmp, len);
        }
        luat_ip_addr_t ipv6;
        memset(&ipv6, 0, sizeof(ipv6));
        if (0 == ipaddr_aton(ipstr, &ipv6)) {
            LLOGW("非法的IPv6地址 %s", ipstr);
            lua_pushboolean(L, 0);
            return 1;
        }
        if (IP_IS_V4(&ipv6)) {
            // 双栈模式下 ipaddr_aton 会把 IPv4 字面量解析成 type=V4, 这里必须挡住
            LLOGW("netdrv.ipv6 不接受IPv4地址 %s", ipstr);
            lua_pushboolean(L, 0);
            return 1;
        }
        if (ipv6.type != IPADDR_TYPE_V6) {
            LLOGW("非法的IPv6地址 %s", ipstr);
            lua_pushboolean(L, 0);
            return 1;
        }
        int prefix = luaL_optinteger(L, 3, 64);
        if (prefix < 1 || prefix > 128) {
            LLOGW("非法的IPv6前缀长度 %d", prefix);
            lua_pushboolean(L, 0);
            return 1;
        }
        // 网关仅作回显: 当前不写入IPv6路由表(IPv6缺省路由需要ND6 router状态)
        netdrv->ipv6_gw[0] = 0;
        if (lua_isstring(L, 4)) {
            size_t gw_len = 0;
            const char* gw = luaL_checklstring(L, 4, &gw_len);
            if (gw_len > 0 && gw_len < sizeof(netdrv->ipv6_gw)) {
                memcpy(netdrv->ipv6_gw, gw, gw_len);
                netdrv->ipv6_gw[gw_len] = 0;
            }
        }
        int ret = net_lwip2_set_static_ip6_info((uint8_t)id, &ipv6, (uint8_t)prefix);
        if (ret) {
            LLOGW("设置IPv6地址失败 id=%d ret=%d", id, ret);
            lua_pushboolean(L, 0);
            return 1;
        }
        // 写入是投递到 tcpip 线程执行的, 这里短暂等待以便调用方紧接着读取时能看到新地址
        luat_ip_addr_t check_addr;
        uint8_t check_prefix = 0;
        for (int i = 0; i < 20; i++) {
            luat_rtos_task_sleep(10);
            memset(&check_addr, 0, sizeof(check_addr));
            if (0 == net_lwip2_ipv6_addr_info((uint8_t)id, &check_addr, &check_prefix)
                && 0 == memcmp(&check_addr.u_addr.ip6, &ipv6.u_addr.ip6, sizeof(ip6_addr_t))) {
                break;
            }
        }
        lua_pushboolean(L, 1);
        return 1;
    }

    // ==== 读取模式 ====
    lua_newtable(L);
    struct netif* netif = net_lwip2_get_netif((uint8_t)id);
    luat_ip_addr_t ipv6;
    uint8_t prefix = 64;

    // 链路本地地址固定放在 linklocal 子table.
    memset(&ipv6, 0, sizeof(ipv6));
    if (0 == net_lwip2_ipv6_linklocal_addr_info((uint8_t)id, &ipv6, &prefix)) {
        // link-local 的网络前缀固定为 /64, 不复用静态全局地址的 prefix.
        l_netdrv_push_ipv6_item(L, netif, &ipv6, 64);
        lua_setfield(L, -2, "linklocal");
    }

    // addr_info 在没有全局地址时会回退链路本地地址, 这里显式过滤,
    // 保证 global 字段只表示真正可路由的 IPv6 地址.
    memset(&ipv6, 0, sizeof(ipv6));
    prefix = 64;
    if (0 == net_lwip2_ipv6_addr_info((uint8_t)id, &ipv6, &prefix)
        && !ip6_addr_islinklocal(&ipv6.u_addr.ip6)) {
        l_netdrv_push_ipv6_item(L, netif, &ipv6, prefix);
        lua_setfield(L, -2, "global");
    }

    // 网关: 记录用户设置的值; 当前不写入IPv6路由表, 仅作回显.
    lua_pushstring(L, netdrv->ipv6_gw);
    lua_setfield(L, -2, "gw");
    return 1;
}

#endif /* LUAT_USE_NETDRV_IPV6 */

/*
设置ARP表静态表项
@api netdrv.arp(id, ip, mac)
@int 网络适配器编号, 例如 socket.LWIP_ETH
@string ipv4地址, 例如 "192.168.1.1"
@string MAC地址, 6字节原始数据; 传nil或空串表示删除该表项
@return boolean 成功与否
@usage
-- 仅以太网类型的netdrv(CH390H / WHALE虚拟网卡)支持
-- 部分场景(如airlink对端不回ARP、点对点以太网专线)需要手工写入ARP表,
-- 否则LWIP会因解析不到对端MAC而把报文排队直到超时
netdrv.arp(socket.LWIP_ETH, "192.168.1.1", string.char(0x02,0,0,0,0,1))
-- 删除表项
netdrv.arp(socket.LWIP_ETH, "192.168.1.1", nil)
-- 该函数于 2026.01 新增
*/
#ifdef LUAT_NETDRV_HAVE_ARP
static int l_netdrv_arp(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id < 0 || id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        LLOGW("对应的netdrv不存在或未就绪 %d", id);
        lua_pushboolean(L, 0);
        return 1;
    }
    const char* ipstr = luaL_checkstring(L, 2);
    ip4_addr_t ip4;
    if (0 == ip4addr_aton(ipstr, &ip4)) {
        LLOGW("非法的IPv4地址 %s", ipstr);
        lua_pushboolean(L, 0);
        return 1;
    }
    size_t mac_len = 0;
    const char* mac = lua_isstring(L, 3) ? luaL_checklstring(L, 3, &mac_len) : NULL;
    if (mac == NULL || mac_len == 0) {
        // 删除静态表项
        int ret = luat_netdrv_etharp_remove_static_entry_on_netif(netdrv->netif, &ip4);
        lua_pushboolean(L, ret == 0);
        return 1;
    }
    if (mac_len != 6) {
        LLOGW("MAC必须是6字节, 实际 %d", (int)mac_len);
        lua_pushboolean(L, 0);
        return 1;
    }
    struct eth_addr eth;
    memcpy(eth.addr, mac, 6);
    int ret = luat_netdrv_etharp_add_static_entry_on_netif(netdrv->netif, &ip4, &eth);
    if (ret) {
        LLOGW("写入ARP表失败 id=%d %s ret=%d", id, ipstr, ret);
    }
    lua_pushboolean(L, ret == 0);
    return 1;
}
#endif /* LUAT_NETDRV_HAVE_ARP */

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

#ifdef LUAT_USE_NETDRV_DNS_CLIENT
/* 读一个整数字段并做范围检查; 越界返回 -1(拒绝该项, 不静默截断) */
static int l_netdrv_dns_get_int(lua_State *L, const char *key, uint32_t min, uint32_t max, uint32_t *out)
{
    int32_t v;
    if (lua_getfield(L, -1, key) == LUA_TNUMBER) {
        lua_Number n = lua_tonumber(L, -1);
        if (n < 0 || n > (lua_Number)max || n != (lua_Number)(uint32_t)n) {
            lua_pop(L, 1);
            LLOGW("netdrv.CTRL_DNS.%s out of range [%u,%u]", key, min, max);
            return -1;
        }
        v = (int32_t)n;
        if ((uint32_t)v < min) {
            lua_pop(L, 1);
            LLOGW("netdrv.CTRL_DNS.%s out of range [%u,%u]", key, min, max);
            return -1;
        }
        *out = (uint32_t)v;
        lua_pop(L, 1);
        return 0;
    }
    lua_pop(L, 1);
    return 1;   /* 该项不存在, 不改动 */
}

/* 读一个布尔字段 */
static int l_netdrv_dns_get_bool(lua_State *L, const char *key, uint8_t *out)
{
    if (lua_getfield(L, -1, key) == LUA_TBOOLEAN) {
        *out = lua_toboolean(L, -1) ? 1 : 0;
        lua_pop(L, 1);
        return 1;
    }
    lua_pop(L, 1);
    return 0;
}

/* 校验 table 里是否混进了无法识别的 key(不静默吞掉拼写错误) */
static void l_netdrv_dns_check_keys(lua_State *L)
{
    static const char *known[] = {
        "cache_enable", "share", "cache_num", "cache_ttl", "neg_ttl",
        "max_inflight", "timeout", "max_retry", "min_gap",
        "flush", "stat", NULL
    };
    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
        const char *k = lua_tostring(L, -2);
        int i, found = 0;
        if (k == NULL) {
            lua_pop(L, 1);
            continue;
        }
        for (i = 0; known[i]; i++) {
            if (strcmp(k, known[i]) == 0) { found = 1; break; }
        }
        if (!found) {
            LLOGW("netdrv.CTRL_DNS unknown key: %s", k);
        }
        lua_pop(L, 1);
    }
}

static void l_netdrv_dns_push_cfg(lua_State *L, const luat_netdrv_dns_cfg_t *cfg)
{
    lua_pushboolean(L, cfg->cache_enable);
    lua_setfield(L, -2, "cache_enable");
    lua_pushboolean(L, cfg->share);
    lua_setfield(L, -2, "share");
    lua_pushinteger(L, cfg->cache_num);
    lua_setfield(L, -2, "cache_num");
    lua_pushinteger(L, cfg->cache_ttl_ms / 1000);
    lua_setfield(L, -2, "cache_ttl");
    lua_pushinteger(L, cfg->neg_ttl_ms / 1000);
    lua_setfield(L, -2, "neg_ttl");
    lua_pushinteger(L, cfg->max_inflight);
    lua_setfield(L, -2, "max_inflight");
    lua_pushinteger(L, cfg->query_timeout_ms);
    lua_setfield(L, -2, "timeout");
    lua_pushinteger(L, cfg->max_retry);
    lua_setfield(L, -2, "max_retry");
    lua_pushinteger(L, cfg->min_gap_ms);
    lua_setfield(L, -2, "min_gap");
}

static void l_netdrv_dns_push_stat(lua_State *L, const luat_netdrv_dns_stat_t *st)
{
#define PUSH_U(k, v) do { lua_pushinteger(L, (lua_Integer)(v)); lua_setfield(L, -2, k); } while (0)
    PUSH_U("query", st->query);
    PUSH_U("cache_hit", st->cache_hit);
    PUSH_U("cache_miss", st->cache_miss);
    PUSH_U("negative_hit", st->negative_hit);
    PUSH_U("tx", st->tx);
    PUSH_U("rx", st->rx);
    PUSH_U("nxdomain", st->nxdomain);
    PUSH_U("timeout", st->timeout);
    PUSH_U("evict", st->evict);
    PUSH_U("malformed", st->malformed);
    PUSH_U("max_inflight_hit", st->max_inflight_hit);
    PUSH_U("send_err", st->send_err);
    PUSH_U("inflight", st->inflight);
    PUSH_U("cache_used", st->cache_used);
    /* 能力位, 不是计数器: 0 表示本构建的 lwIP 没编入 IPv6, 双栈查询只发 A */
    PUSH_U("ipv6", st->ipv6);
#undef PUSH_U
}

/* netdrv.ctrl(id, netdrv.CTRL_DNS, table) 的实现 */
static int l_netdrv_dns_ctrl(lua_State *L, int id)
{
    net_lwip2_dns_ctl_t ctl;
    luat_netdrv_dns_cfg_t cfg;
    uint32_t v;
    int want_stat = 0;

    /*
     * DNS 客户端是全局单例(缓存跨网卡共享), id 不参与寻址 —— 但也不能默默忽略:
     * 传错网卡号却"成功"会让人以为配置只对某张网卡生效。至少留一条日志。
     */
    if (luat_netdrv_get(id) == NULL) {
        LLOGW("netdrv.CTRL_DNS: no such netdrv %d (DNS client is global, id is ignored)", id);
    }

    if (lua_type(L, 3) != LUA_TTABLE) {
        return luaL_error(L, "netdrv.CTRL_DNS expects a table as the 3rd argument");
    }

    l_netdrv_dns_check_keys(L);

    /*
     * 以"当前生效值"为基准做增量修改: 只传要改的 key,
     * 其余保持不变. 因为真实配置在 tcpip 线程里, 这里先读一次快照再叠加.
     *
     * 第一趟必须 has_cfg = 0(纯读).
     * 曾经写成 1, 结果每读一次统计就把全零配置应用下去,
     * 把 cache_num / cache_ttl 这些默认值冲成 0 —— 表现就是缓存整体失效、
     * 回读全是 0, 而且只在真机上暴露(PC 模拟器不走这条跨线程路径).
     */
    memset(&ctl, 0, sizeof(ctl));
    ctl.done = 0;
    if (netdrv_dns_ctrl(&ctl, NETDRV_DNS_STAT_TIMEOUT) != 0) {
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        return 2;
    }
    cfg = ctl.rcfg;

    /* has_cfg 只在确实有 key 被接受时才置 1, 避免"只读"被当成"修改" */
    if (l_netdrv_dns_get_bool(L, "cache_enable", &cfg.cache_enable) == 1) { ctl.has_cfg = 1; }
    if (l_netdrv_dns_get_bool(L, "share", &cfg.share) == 1) { ctl.has_cfg = 1; }
    if (l_netdrv_dns_get_int(L, "cache_num", 0, LUAT_NETDRV_DNS_LIM_CACHE_NUM_MAX, &v) == 0) {
        cfg.cache_num = v; ctl.has_cfg = 1;
    }
    if (l_netdrv_dns_get_int(L, "cache_ttl", 0, LUAT_NETDRV_DNS_LIM_CACHE_TTL_MAX / 1000, &v) == 0) {
        cfg.cache_ttl_ms = v * 1000; ctl.has_cfg = 1;
    }
    if (l_netdrv_dns_get_int(L, "neg_ttl", 0, LUAT_NETDRV_DNS_LIM_NEG_TTL_MAX / 1000, &v) == 0) {
        cfg.neg_ttl_ms = v * 1000; ctl.has_cfg = 1;
    }
    if (l_netdrv_dns_get_int(L, "max_inflight", 1, LUAT_NETDRV_DNS_LIM_INFLIGHT_MAX, &v) == 0) {
        cfg.max_inflight = (uint8_t)v; ctl.has_cfg = 1;
    }
    if (l_netdrv_dns_get_int(L, "timeout", LUAT_NETDRV_DNS_LIM_TIMEOUT_MIN,
            LUAT_NETDRV_DNS_LIM_TIMEOUT_MAX, &v) == 0) {
        cfg.query_timeout_ms = (uint16_t)v; ctl.has_cfg = 1;
    }
    if (l_netdrv_dns_get_int(L, "max_retry", 0, LUAT_NETDRV_DNS_LIM_RETRY_MAX, &v) == 0) {
        cfg.max_retry = (uint8_t)v; ctl.has_cfg = 1;
    }
    if (l_netdrv_dns_get_int(L, "min_gap", 0, LUAT_NETDRV_DNS_LIM_MIN_GAP_MAX, &v) == 0) {
        cfg.min_gap_ms = (uint16_t)v; ctl.has_cfg = 1;
    }

    ctl.flush = l_netdrv_dns_get_bool(L, "flush", &ctl.flush);
    want_stat = l_netdrv_dns_get_bool(L, "stat", &ctl.want_stat);
    ctl.cfg = cfg;

    if (!ctl.has_cfg && !ctl.flush && !want_stat) {
        /* 什么都没要求: 只回读, 不做任何改动 */
        ctl.want_stat = 1;
    }

    if (netdrv_dns_ctrl(&ctl, NETDRV_DNS_STAT_TIMEOUT) != 0) {
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        return 2;
    }

    lua_pushboolean(L, 1);
    if (!want_stat) {
        return 1;
    }
    lua_newtable(L);
    lua_newtable(L);
    l_netdrv_dns_push_cfg(L, &ctl.rcfg);
    lua_setfield(L, -2, "cfg");
    lua_newtable(L);
    l_netdrv_dns_push_stat(L, &ctl.rstat);
    lua_setfield(L, -2, "stat");
    return 2;
}
#endif /* LUAT_USE_NETDRV_DNS_CLIENT */

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

-- DNS 客户端配置(第三个参数改传 table)
netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_DNS, {
    cache_enable = true,  -- 缓存总开关
    share        = false, -- 缓存是否跨网卡共享, 默认 false(按网卡隔离)
                          --   出口不同 -> 权威DNS可能给出不同答案(地域调度/
                          --   运营商内网/多WAN分流), 共享会把各出口的答案混在一起
    cache_num    = 32,    -- 缓存条目上限, 0=不缓存
    cache_ttl    = 60,    -- 秒, 记录TTL上限, 0=不缓存
    neg_ttl      = 10,    -- 秒, NXDOMAIN 负缓存时长
    max_inflight = 8,     -- 最大在途查询数
    timeout      = 2000,  -- ms, 单次尝试超时
    max_retry    = 2,     -- 单台DNS服务器最大重试次数
    min_gap      = 20,    -- ms, 发送节奏(令牌桶)
})

-- 手动让整个DNS缓存失效
netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_DNS, { flush = true })

-- 读回当前配置与统计(第一个返回值=是否成功)
local ok, info = netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_DNS, { stat = true })
-- info.cfg  = { cache_enable=true, share=false, cache_num=32, cache_ttl=60, ... }
-- info.stat = { query=.., cache_hit=.., tx=.., rx=.., inflight=.., .. }
*/
static int l_netdrv_ctrl(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int cmd = luaL_checkinteger(L, 2);
    int arg = 0;

    /*
     * DNS 分支: 第三个参数是 table, 与整数路径互不影响.
     *
     * 这个分支必须整体包在宏里: l_netdrv_dns_ctrl 只在
     * LUAT_USE_NETDRV_DNS_CLIENT 打开时才存在, 否则链接期会报
     * undefined reference(未开启该宏的 BSP, 例如 Air780EPM/EC7xx 就会踩到).
     * 不能用 #ifdef 之外的写法让它在关闭时"碰巧能用"——那会把 0x10 这个
     * 控制码漏给驱动的私有 cmd.
     */
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
    if (cmd == LUAT_NETDRV_CTRL_DNS) {
        return l_netdrv_dns_ctrl(L, id);
    }
#else
    if (cmd == LUAT_NETDRV_CTRL_DNS) {
        /* 未开启新 DNS 客户端: 明确报错 + 给 Lua 侧一个可判断的 false */
        LLOGW("netdrv.CTRL_DNS unavailable: LUAT_USE_NETDRV_DNS_CLIENT not enabled in this BSP");
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        return 2;
    }
#endif

    arg = luaL_checkinteger(L, 3);
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
模拟一次 IPsec 本地地址变更, 触发 MOBIKE 更新流程
@api netdrv.ipsec_sim_addr_change(id)
@int 网络适配器编号
@return boolean 成功与否
@usage
-- 仅 utest 构建 (PC 模拟器) 可用; 需要 ipsec_mobike_enable = true
netdrv.ipsec_sim_addr_change(socket.LWIP_USER1)
*/
#if defined(LUAT_USE_UTEST) && defined(LUAT_USE_NETDRV_IPSEC)
static int l_netdrv_ipsec_sim_addr_change(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int ret = luat_netdrv_ipsec_sim_addr_change(id);
    lua_pushboolean(L, ret == 0);
    return 1;
}

extern int luat_ipsec_utest(lua_State *L, const char *case_name);
static int l_netdrv_ipsec_utest(lua_State *L) {
    const char *case_name = luaL_optstring(L, 1, "all");
    lua_pushboolean(L, luat_ipsec_utest(L, case_name) == 0);
    return 1;
}
#endif

/*
运行现代 DNS 客户端的 C 层单元测试(假传输层)
@api netdrv.dns_utest(case)
@string 用例名, 省略或传 "all" 跑全部
@return boolean 是否全部通过
@usage
-- 跑全部用例
netdrv.dns_utest()
-- 只跑并发相关用例
netdrv.dns_utest("concurrent_inflight")
*/
#if defined(LUAT_USE_UTEST) && defined(LUAT_USE_NETDRV_DNS_CLIENT)
extern int luat_netdrv_dns_utest(lua_State *L, const char *case_name);
static int l_netdrv_dns_utest(lua_State *L) {
    const char *case_name = luaL_optstring(L, 1, "all");
    lua_pushboolean(L, luat_netdrv_dns_utest(L, case_name) == 0);
    return 1;
}
#endif

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
@int 投递目标 (target/dst):
  - netdrv.CH_HW   = 0x10: 走 dataout 发到物理硬件 (HW TX 出口)
  - netdrv.CH_LWIP = 0x20: 跳过 NAPT, 直接注入 LWIP (相当于 RX 方向 post-NAPT 入口)
  - netdrv.CH_NAPT = 0x30: 先过 NAPT, 未消费则注入 LWIP (相当于 RX 方向 pre-NAPT 入口)
@zbuff 待发送的 zbuff, used 长度即默认发送长度
@int 可选, 发送长度(<= zbuff.used), 默认 zbuff.used
@return int 实际进入发送队列的字节数, 失败返回 nil+err
@usage
-- 立即以默认长度发到硬件
netdrv.send_raw(socket.LWIP_ETH, netdrv.CH_HW, zb)
-- 只发前 64 字节
netdrv.send_raw(socket.LWIP_ETH, netdrv.CH_HW, zb, 64)
-- 注入 LWIP (作为入向包, 等同收到一个网络包)
netdrv.send_raw(socket.LWIP_ETH, netdrv.CH_LWIP, fake_response_zb)
-- 走 NAPT 路径 (走完 NAPT 后再注入 LWIP)
netdrv.send_raw(socket.LWIP_GP, netdrv.CH_NAPT, app_zb)
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

    // target -> 队列提交函数 + 各自 netdrv 前置依赖 (dataout / netif)
    // 注: helper/need_msg 必须在 switch 外声明 (MSVC C89 不允许 case 内任意位置定义变量)
    void (*helper)(void*) = NULL;
    const char* need_msg = NULL;
    switch (target) {
        case LUAT_NETDRV_CH_HW:
            helper   = do_send_raw_to_hw;
            need_msg = "netdrv has no dataout";
            break;
        case LUAT_NETDRV_CH_LWIP:
            helper   = do_send_raw_to_lwip;
            need_msg = "netdrv has no netif";
            break;
        case LUAT_NETDRV_CH_NAPT:
            helper   = do_send_raw_to_napt;
            need_msg = "netdrv has no netif";
            break;
        default:
            return luaL_error(L, "unknown send_raw target %d", target);
    }

    // 共同前置: drv 存在 + target 特定依赖 (dataout / netif)
    // 注: error 字符串用 lua_pushstring 而非 lua_pushliteral, 因后者是宏
    // "" s 拼接, 要求 s 必须是字符串字面量, 不能传 const char* 变量.
    luat_netdrv_t* drv = luat_netdrv_get(id);
    if (drv == NULL) {
        lua_pushnil(L); lua_pushliteral(L, "netdrv not available"); return 2;
    }
    if (target == LUAT_NETDRV_CH_HW && drv->dataout == NULL) {
        lua_pushnil(L); lua_pushstring(L, need_msg); return 2;
    }
    if ((target == LUAT_NETDRV_CH_LWIP || target == LUAT_NETDRV_CH_NAPT)
        && drv->netif == NULL) {
        lua_pushnil(L); lua_pushstring(L, need_msg); return 2;
    }
    // 共同前置: zbuff 合法 + len 合法
    if (buff == NULL || buff->addr == NULL) {
        lua_pushnil(L); lua_pushliteral(L, "zbuff invalid"); return 2;
    }
    if (len == 0) {
        lua_pushnil(L); lua_pushliteral(L, "len is 0"); return 2;
    }
    if (len > buff->used) {
        lua_pushnil(L); lua_pushliteral(L, "len out of range"); return 2;
    }

    // 入队: 拷贝到 netdrv_send_msg_t, 由对应 helper 在 tcpip 线程处理
    netdrv_send_msg_t* m = (netdrv_send_msg_t*)luat_heap_malloc(sizeof(netdrv_send_msg_t) + len - 4);
    if (m == NULL) {
        lua_pushnil(L); lua_pushliteral(L, "oom"); return 2;
    }
    m->drv = drv;
    m->len = len;
    memcpy(m->buff, buff->addr, len);
    if (tcpip_callback_with_block(helper, m, 0) != ERR_OK) {
        luat_heap_free(m);
        lua_pushnil(L); lua_pushliteral(L, "tcpip queue full"); return 2;
    }
    lua_pushinteger(L, len);
    return 1;
}

/* netdrv.arpSleep / netdrv.arpResume 已被移除.
 * ARP 1000ms 定时器整体已删除, 业务侧无需再为休眠主动停止它.
 * 历史实现见 commit b4de806e0. */

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
#if defined(LUAT_USE_UTEST) && defined(LUAT_USE_NETDRV_IPSEC)
    { "ipsec_sim_addr_change", ROREG_FUNC(l_netdrv_ipsec_sim_addr_change)},
    { "ipsec_utest", ROREG_FUNC(l_netdrv_ipsec_utest)},
#endif
#if defined(LUAT_USE_UTEST) && defined(LUAT_USE_NETDRV_DNS_CLIENT)
    { "dns_utest",       ROREG_FUNC(l_netdrv_dns_utest)},
#endif
    { "on",             ROREG_FUNC(l_netdrv_on)},
    { "send_raw",       ROREG_FUNC(l_netdrv_send_raw)},
#ifdef LUAT_USE_MREPORT
    { "mreport",        ROREG_FUNC(l_mreport_config)},
#endif
#ifdef LUAT_USE_ICMP
    { "ping",           ROREG_FUNC(l_icmp_ping)},
#endif
#ifdef LUAT_USE_NETDRV_IPV6
    { "ipv6",           ROREG_FUNC(l_netdrv_ipv6)},
#ifdef LUAT_NETDRV_HAVE_ARP
    { "arp",            ROREG_FUNC(l_netdrv_arp)},
#endif
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
    #ifdef LUAT_USE_NETDRV_L2TP
    { "L2TP",           ROREG_INT(LUAT_NETDRV_IMPL_L2TP)}, // L2TPv2虚拟网卡
    #endif
    #ifdef LUAT_USE_NETDRV_IPSEC
    { "IPSEC",          ROREG_INT(LUAT_NETDRV_IMPL_IPSEC)}, // IKEv2/IPsec隧道虚拟网卡
    #endif

    //@const CTRL_RESET number 控制类型-复位,当前仅支持CH390H
    { "CTRL_RESET",     ROREG_INT(LUAT_NETDRV_CTRL_RESET)},
    //@const CTRL_UPDOWN number 控制类型-1=启动UP，0关闭DOWN
    { "CTRL_UPDOWN",    ROREG_INT(LUAT_NETDRV_CTRL_UPDOWN)},
    //@const RESET_HARD number 请求对网卡硬复位,当前仅支持CH390H
    { "RESET_HARD",     ROREG_INT(0x101)},
    //@const RESET_SOFT number 请求对网卡软复位,当前仅支持CH390H
    { "RESET_SOFT",     ROREG_INT(0x102)},
#ifdef LUAT_USE_NETDRV_DNS_CLIENT
    //@const CTRL_DNS number 控制类型-DNS客户端配置,第三个参数传table
    { "CTRL_DNS",       ROREG_INT(LUAT_NETDRV_CTRL_DNS)},
#endif

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

#ifdef LUAT_USE_NETDRV_IPV6
    //@const IPV6_PREFIX_DEFAULT number IPv6默认前缀长度, 即64
    { "IPV6_PREFIX_DEFAULT", ROREG_INT(64)},
    //@const IPV6_PREFIX_MAX number IPv6最大前缀长度, 即128
    { "IPV6_PREFIX_MAX", ROREG_INT(128)},
#endif

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_netdrv( lua_State *L ) {
    luat_newlib2(L, reg_netdrv);
    return 1;
}
