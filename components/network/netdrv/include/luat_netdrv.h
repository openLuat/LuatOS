#ifndef LUAT_NETDRV_H
#define LUAT_NETDRV_H

#include "lwip/pbuf.h"

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
};

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
    luat_netdrv_statics_t statics;
    void* userdata;
    luat_netdrv_ctrl_cb ctrl;
    uint8_t gw_mac[6];
    luat_netdrv_debug_cb debug;
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

// 辅助函数
uint32_t alg_hdr_16bitsum(const uint16_t *buff, uint16_t len);
uint16_t alg_iphdr_chksum(const uint16_t *buff, uint16_t len);
uint16_t alg_tcpudphdr_chksum(uint32_t src_addr, uint32_t dst_addr, uint8_t proto, const uint16_t *buff, uint16_t len);

// 辅助传递函数
typedef struct netdrv_pkg_msg
{
    struct netif * netif;
    uint16_t len;
    uint8_t buff[4];
}netdrv_pkg_msg_t;

void luat_netdrv_netif_input(void* args);

int luat_netdrv_netif_input_proxy(struct netif * netif, uint8_t* buff, uint16_t len);

void luat_netdrv_print_tm(const char * tag);

void luat_netdrv_debug_set(int id, int enable);

extern uint32_t g_netdrv_debug_enable;

#endif
