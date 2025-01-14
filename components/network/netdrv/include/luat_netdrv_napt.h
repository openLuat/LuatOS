#ifndef LUAT_NETDRV_NAPT_H
#define LUAT_NETDRV_NAPT_H

#include "lwip/pbuf.h"

typedef struct napt_map_item
{
    uint8_t adapter_id;
    uint16_t port;
    uint32_t ipv4;
    uint8_t mac[6];
}napt_map_item_t;


typedef struct luat_netdrv_napt_item
{
    uint8_t     is_vaild;
    // uint8_t     tp; // tcp, udp, icmp
    napt_map_item_t inet;  // 内网信息
    napt_map_item_t wnet; // 外网信息
    uint64_t tm_ms; // 最后通信时间
}luat_netdrv_napt_item_t;

typedef struct luat_netdrv_napt_tcpudp
{
    uint8_t  is_vaild;
    uint8_t adapter_id;
    uint16_t inet_port;
    uint16_t wnet_port;
    uint16_t wnet_local_port;
    uint32_t inet_ip;
    uint32_t wnet_ip;
    uint8_t  inet_mac[6];
    uint64_t tm_ms; // 最后通信时间
}luat_netdrv_napt_tcpudp_t;

typedef struct napt_ctx
{
    luat_netdrv_t* net;
    uint8_t* buff;
    size_t len;
    struct eth_hdr* eth;
    struct ip_hdr* iphdr;
    int is_wnet;
}napt_ctx_t;

int luat_napt_icmp_handle(napt_ctx_t* ctx);
int luat_napt_tcp_handle(napt_ctx_t* ctx);
int luat_napt_udp_handle(napt_ctx_t* ctx);

int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len);

#endif
