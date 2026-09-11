#ifndef LUAT_NETDRV_H
#define LUAT_NETDRV_H

#include "lwip/pbuf.h"
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "luat_rtos.h"
#include "luat_network_adapter.h"
#include "dhcp_def.h"

struct luat_netdrv;

typedef void (*luat_netdrv_dataout_cb)(struct luat_netdrv* drv, void* userdata, uint8_t* buff, uint16_t len);
typedef int (*luat_netdrv_bootup_cb)(struct luat_netdrv* drv, void* userdata);
typedef int (*luat_netdrv_ready_cb)(struct luat_netdrv* drv, void* userdata);
typedef int (*luat_netdrv_dhcp_set)(struct luat_netdrv* drv, void* userdata, int enable);
typedef int (*luat_netdrv_ctrl_cb)(struct luat_netdrv* drv, void* userdata, int cmd, void* param);
typedef int (*luat_netdrv_debug_cb)(struct luat_netdrv* drv, void* userdata, int enable);

#define MACFMT "%02X%02X%02X%02X%02X%02X"
#define MAC_ARG(x) ((uint8_t*)(x))[0],((uint8_t*)(x))[1],((uint8_t*)(x))[2],((uint8_t*)(x))[3],((uint8_t*)(x))[4],((uint8_t*)(x))[5]

enum {
    LUAT_NETDRV_TP_NATIVE,
    LUAT_NETDRV_TP_CH390H,
    LUAT_NETDRV_TP_W5100,
    LUAT_NETDRV_TP_W5500,
    LUAT_NETDRV_TP_SPINET,
    LUAT_NETDRV_TP_UARTNET,
    LUAT_NETDRV_TP_USB
};

enum {
    LUAT_NETDRV_CTRL_RESET,
    LUAT_NETDRV_CTRL_UPDOWN,
};

typedef struct luat_netdrv_ip_conf
{
    ip4_addr_t ip;
    ip4_addr_t netmask;
    ip4_addr_t gw;
}luat_netdrv_ip_conf_t;

typedef struct luat_netdrv_wg_conf
{
    const char* wg_private_key;
    uint16_t wg_listen_port;
    uint16_t wg_keepalive;
    const char* wg_preshared_key;
    const char* wg_endpoint_key;
    const char* wg_endpoint_ip;
    uint16_t wg_endpoint_port;
}luat_netdrv_wg_conf_t;

typedef struct luat_netdrv_openvpn_conf
{
    const char* ovpn_remote_ip;     // VPN服务器IP地址
    uint16_t ovpn_remote_port;      // VPN服务器端口
    const char* ovpn_ca_cert;       // CA证书 (PEM格式)
    size_t ovpn_ca_cert_len;
    const char* ovpn_client_cert;   // 客户端证书 (PEM格式)
    size_t ovpn_client_cert_len;
    const char* ovpn_client_key;    // 客户端私钥 (PEM格式)
    size_t ovpn_client_key_len;
    uint8_t ovpn_retry_enable;      // 失败后自动重试
    uint32_t ovpn_retry_base_ms;    // 重试基础延迟
    uint32_t ovpn_retry_max_ms;     // 重试最大延迟
    const char* ovpn_username;      // auth-user-pass 用户名 (可选)
    size_t ovpn_username_len;
    const char* ovpn_password;      // auth-user-pass 密码 (可选)
    size_t ovpn_password_len;
}luat_netdrv_openvpn_conf_t;

typedef struct luat_netdrv_l2tp_conf
{
    const char* l2tp_remote_ip;     // LNS IP地址 (仅IP字面量)
    uint16_t l2tp_remote_port;      // LNS端口, 默认1701
    const char* l2tp_username;      // PPP用户名 (可选)
    size_t l2tp_username_len;
    const char* l2tp_password;      // PPP密码 (可选)
    size_t l2tp_password_len;
    const char* l2tp_secret;        // L2TP隧道共享密钥 (可选)
    size_t l2tp_secret_len;
    uint16_t l2tp_mtu;              // PPP MRU, 默认1450
    uint8_t l2tp_retry_enable;      // 失败后自动重连
    uint32_t l2tp_retry_base_ms;    // 重试基础延迟
    uint32_t l2tp_retry_max_ms;     // 重试最大延迟
}luat_netdrv_l2tp_conf_t;

typedef struct luat_netdrv_ipsec_conf
{
    const char* ipsec_remote_ip;    // IKEv2 网关 IP (仅IP字面量)
    uint16_t ipsec_remote_port;     // IKE 端口, 默认500
    const char* ipsec_username;     // EAP-MSCHAPv2 用户名
    size_t ipsec_username_len;
    const char* ipsec_password;     // EAP-MSCHAPv2 密码
    size_t ipsec_password_len;
    const char* ipsec_ca_cert_pem;  // 服务器证书信任锚 PEM (可选; 未配置时默认 fail-closed, 需显式 ipsec_insecure_cert_ok=true 才接受证书)
    size_t ipsec_ca_cert_pem_len;
    const char* ipsec_san;          // 服务器 SAN 校验 (可选, 缺省用网关IP)
    uint8_t ipsec_insecure_cert_ok;// 允许无 CA 时仅校验 SAN (默认关闭, fail-closed)
    uint16_t ipsec_mtu;             // 隧道 MTU, 默认1400
    uint8_t ipsec_retry_enable;     // 失败后自动重连
    uint8_t ipsec_mobike_enable;    // MOBIKE 双向地址更新, 默认关闭
    uint32_t ipsec_retry_base_ms;   // 重试基础延迟
    uint32_t ipsec_retry_max_ms;    // 重试最大延迟
}luat_netdrv_ipsec_conf_t;


typedef struct luat_netdrv_conf
{
    int32_t id;
    int32_t impl;
    uint8_t spiid;
    uint8_t cspin;
    uint8_t rstpin;
    uint8_t irqpin;
    uint16_t mtu;
    uint8_t flags;
    uint8_t mac[6];         // 虚拟网卡的初始MAC, 由 netdrv.setup(id, tp, {mac=...}) 传入; 全0表示不指定

    luat_netdrv_ip_conf_t *ip_conf;
    luat_netdrv_wg_conf_t *wg_conf;
    luat_netdrv_openvpn_conf_t *ovpn_conf;
    luat_netdrv_l2tp_conf_t *l2tp_conf;
    luat_netdrv_ipsec_conf_t *ipsec_conf;
}luat_netdrv_conf_t;

typedef struct luat_netdrv_statics_item
{
    uint64_t counter;
    uint64_t bytes;
}luat_netdrv_statics_item_t;

typedef struct luat_netdrv_statics
{
    luat_netdrv_statics_item_t in;
    luat_netdrv_statics_item_t out;
    luat_netdrv_statics_item_t drop;
}luat_netdrv_statics_t;

typedef struct luat_netdrv {
    int32_t id;
    struct netif* netif;
    luat_netdrv_dataout_cb dataout;
    luat_netdrv_bootup_cb boot;
    luat_netdrv_ready_cb ready;
    luat_netdrv_dhcp_set dhcp;
    uint8_t dhcp_enable;            // DHCP开关, 0=关闭 1=开启
    dhcp_client_info_t dhcp_client; // DHCP客户端状态机
    luat_rtos_timer_t dhcp_timer;   // DHCP定时器
    luat_netdrv_statics_t statics;
    void* userdata;
    luat_netdrv_ctrl_cb ctrl;
    uint8_t gw_mac[6];
    luat_netdrv_debug_cb debug;
    char ipv6_gw[46];               // 用户设置的IPv6网关, 仅用于回显(最长45字符+结束符)
}luat_netdrv_t;

luat_netdrv_t* luat_netdrv_setup(luat_netdrv_conf_t *conf);

int luat_netdrv_dhcp(int32_t id, int32_t enable);

int luat_netdrv_ready(int32_t id);

int luat_netdrv_register(int32_t id, luat_netdrv_t* drv);

int luat_netdrv_mac(int32_t id, const char* new, char* old);

void luat_netdrv_stat_inc(luat_netdrv_statics_item_t* stat, size_t len);

#define NETDRV_STAT_IN(ndrv, len) luat_netdrv_stat_inc(&ndrv->statics.in, len)
#define NETDRV_STAT_OUT(ndrv, len) luat_netdrv_stat_inc(&ndrv->statics.out, len)
#define NETDRV_STAT_DROP(ndrv, len) luat_netdrv_stat_inc(&ndrv->statics.drop, len)


luat_netdrv_t* luat_netdrv_get(int id);

void luat_netdrv_print_pkg(const char* tat, uint8_t* buff, size_t len);

// 辅助传递函数: 只携带pbuf指针, 整帧缓冲在RX任务里一次分配/拷贝
typedef struct netdrv_pkg_msg
{
    struct netif * netif;
    struct pbuf * p;
}netdrv_pkg_msg_t;

void luat_netdrv_netif_input(void* args);

int luat_netdrv_netif_input_proxy(struct netif * netif, uint8_t* buff, uint16_t len);

void luat_netdrv_rx_stat_reset(void);
void luat_netdrv_rx_stat_print(void);

void luat_netdrv_print_tm(const char * tag);

void luat_netdrv_debug_set(int id, int enable);

void luat_netdrv_netif_set_down(struct netif* netif);

void luat_netdrv_netif_set_link_down(struct netif* netif);

int luat_netdrv_dhcp_opt(luat_netdrv_t* drv, void* userdata, int enable);

extern uint32_t g_netdrv_debug_enable;

int luat_netdrv_simple_stat(void);

int luat_netdrv_is_ready(int id);

#ifndef __NETDRV_CODE_IN_RAM__
#ifdef __LUAT_C_CODE_IN_RAM__
#define __NETDRV_CODE_IN_RAM__ __LUAT_C_CODE_IN_RAM__
#else
#define __NETDRV_CODE_IN_RAM__
#endif
#endif

#ifndef __NETDRV_CODE_IN_ISR__
#ifdef __LUAT_C_CODE_IN_ISR__
#define __NETDRV_CODE_IN_ISR__ __LUAT_C_CODE_IN_ISR__
#else
#define __NETDRV_CODE_IN_ISR__
#endif
#endif

#endif
