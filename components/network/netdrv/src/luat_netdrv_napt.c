#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_ch390h.h"
#include "luat_malloc.h"
#include "luat_netdrv_napt.h"
#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/etharp.h"
#include "lwip/icmp.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "netdrv.napt"
#include "luat_log.h"

#define ICMP_MAP_SIZE (32)
#define IP_MAP_SIZE (1024)

/* napt icmp id range: 3000-65535 */
#define NAPT_ICMP_ID_RANGE_START     0xBB8
#define NAPT_ICMP_ID_RANGE_END       0xFFFF

int luat_netdrv_gw_adapter_id = -1;

static luat_netdrv_napt_item_t icmps[ICMP_MAP_SIZE];

static luat_netdrv_napt_item_t ips[IP_MAP_SIZE];

#define u32 uint32_t
#define u16 uint16_t
#define u8 uint8_t
#define NAPT_ETH_HDR_LEN             sizeof(struct ethhdr)
#define NAPT_CHKSUM_16BIT_LEN        sizeof(u16)

int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
    if (luat_netdrv_gw_adapter_id < 0) {
        // LLOGD("NAPT 未开启");
        return 0; // NAPT没有开启
    }
    luat_netdrv_t* net = luat_netdrv_get(id);
    if (net == NULL || net->netif == NULL) {
        LLOGD("网关netif不存在,无法转发");
        return 0;
    }
    if (len < 40 || len > 1600) {
        LLOGD("包长度不合法, 拒绝改写 %d", len);
        return 0;
    }
    
    // 首先, 如果是eth网卡, 需要先判断是不是广播包
    napt_ctx_t ctx = {
        .buff = buff,
        .len = len,
        .iphdr = (struct ip_hdr*)(buff + SIZEOF_ETH_HDR),
        .eth = (struct eth_hdr*)buff,
        .is_wnet = luat_netdrv_gw_adapter_id == id,
        .net = net
    };

    if (net->netif->flags & NETIF_FLAG_ETHARP) {
        // LLOGD("是ETH包, 先判断是不是广播包");
        if (memcmp(ctx.eth->dest.addr, "\xFF\xFF\xFF\xFF\xFF\xFF", 6) == 0 ||
            ctx.eth->dest.addr[0] == 0x01
        ) {
            LLOGD("是广播包,不需要执行napt");
            return 0;
        }
        // LLOGD("ETH包 " MACFMT " -> " MACFMT " %04X", MAC_ARG(ctx.eth->src.addr), MAC_ARG(ctx.eth->dest.addr), ctx.eth->type);
        if (ctx.eth->type != PP_HTONS(ETHTYPE_IP)) {
            LLOGD("不是IP包, 不需要执行napt");
            return 0;
        }
    }
    else {
        LLOGD("不是ETH包, 裸IP包");
        ctx.iphdr = (struct ip_hdr*)(buff);
        ctx.eth = NULL;
    }

    // 看来是IP包了, 判断一下版本号
    u8_t ipVersion;
    ipVersion = IPH_V(ctx.iphdr);
    if (ipVersion != 4) {
        LLOGD("不是ipv4包, 不需要执行napt");
        return 0;
    }
    if (IPH_PROTO(ctx.iphdr) != IP_PROTO_UDP && IPH_PROTO(ctx.iphdr) != IP_PROTO_TCP && IPH_PROTO(ctx.iphdr) != IP_PROTO_ICMP) {
        LLOGD("不是tcp/udp/icmp包, 不需要执行napt");
        return 0;
    }
    LLOGD("按协议类型, 使用对应的NAPT修改器进行处理");
    switch (IPH_PROTO(ctx.iphdr))
    {
    case IP_PROTO_ICMP:
        return luat_napt_icmp_handle(&ctx);
    case IP_PROTO_TCP:
        return luat_napt_tcp_handle(&ctx);
    case IP_PROTO_UDP:
        return luat_napt_udp_handle(&ctx);
    default:
        LLOGD("不是tcp/udp/icmp包, 不需要执行napt");
        return 0;
    }

    return 0;
}

int luat_napt_tcp_handle(napt_ctx_t* ctx) {
    LLOGD("当前不支持TCP包改写");
    return 0;
}

int luat_napt_udp_handle(napt_ctx_t* ctx) {
    LLOGD("当前不支持UDP包改写");
    return 0;
}

static uint8_t napt_buff[1600];
err_t netdrv_ip_input_cb(int id, struct pbuf *p, struct netif *inp) {
    if (p->tot_len > 1600) {
        return 1;
    }
    if (p->tot_len < 40) {
        return 1;
    }
    pbuf_copy_partial(p, napt_buff, p->tot_len, 0);
    int ret = luat_netdrv_napt_pkg_input(id, napt_buff, p->tot_len);
    LLOGD("napt_pkg_input ret %d", ret);
    return ret == 0 ? 1 : 0;
    // return 1;
}
