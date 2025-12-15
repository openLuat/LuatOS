#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#ifdef __LUATOS__
#include "luat_netdrv_ch390h.h"
#endif
#include "luat_netdrv_napt.h"
#include "luat_mcu.h"
#include "luat_mem.h"

#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/etharp.h"
#include "lwip/icmp.h"
#include "lwip/prot/etharp.h"
#include "lwip/tcpip.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"
#include "lwip/prot/tcp.h"
#include "lwip/prot/udp.h"
#include "lwip/ip_addr.h"

#define LUAT_LOG_TAG "netdrv.napt"
#include "luat_log.h"

// 超时时间定义
#define NAPT_TCP_TIMEOUT_MS        (20*60*1000)   // TCP连接超时: 20分钟
#define NAPT_TCP_DISCON_TIMEOUT_MS (20*1000)      // TCP断开连接超时: 20秒
#define NAPT_UDP_TIMEOUT_MS        (2*60*1000)    // UDP超时: 2分钟
#define NAPT_CLEANUP_INTERVAL_SEC  (5)            // 清理周期: 5秒

#define ICMP_MAP_SIZE (32)
#define UDP_MAP_TIMEOUT (60 * 1000)
#define NAPT_MAX_PACKET_SIZE (1520)
/* napt icmp id range: 3000-65535 */
#define NAPT_ICMP_ID_RANGE_START     0xBB8
#define NAPT_ICMP_ID_RANGE_END       0xFFFF

static int s_gw_adapter_id = -1;

// --- TCP/UDP的映射关系维护
luat_netdrv_napt_ctx_t *g_napt_tcp_ctx;
luat_netdrv_napt_ctx_t *g_napt_udp_ctx;

// 端口分配
#define NAPT_PORT_RANGE_START     0x1BBC
#define NAPT_PORT_RANGE_END       0x6AAA
#define NAPT_PORT_COUNT           (NAPT_PORT_RANGE_END - NAPT_PORT_RANGE_START + 1)
#define NAPT_PORT_BITMAP_SIZE     ((NAPT_PORT_COUNT + 31) / 32 * sizeof(uint32_t))

#define u32 uint32_t
#define u16 uint16_t
#define u8 uint8_t
#define NAPT_ETH_HDR_LEN             sizeof(struct ethhdr)
#define NAPT_CHKSUM_16BIT_LEN        sizeof(u16)

static void check_it(const char* tag, luat_netdrv_napt_llist_t* it, luat_netdrv_napt_llist_t* prev, size_t id) {
    uint32_t tmp = (uint32_t)it;
    if (tmp == 0 || tmp > 0xc300000) {
        LLOGE("why %s cur %p prev %p id %ld", tag, it, prev, id);
    }
}

// ============ 哈希表优化函数 ============

// WAN->LAN方向的哈希函数：基于(wnet_ip, wnet_port, wnet_local_port)
__NETDRV_CODE_IN_RAM__ static inline uint32_t napt_hash_wan2lan(uint32_t wnet_ip, uint16_t wnet_port, uint16_t wnet_local_port) {
    // 简单的FNV-1a哈希变种
    uint32_t hash = 2166136261U;
    hash ^= wnet_ip;
    hash *= 16777619U;
    hash ^= ((uint32_t)wnet_port << 16) | wnet_local_port;
    hash *= 16777619U;
    return hash % NAPT_HASH_TABLE_SIZE;
}

// LAN->WAN方向的哈希函数：基于(inet_ip, inet_port, wnet_ip, wnet_port)
__NETDRV_CODE_IN_RAM__ static inline uint32_t napt_hash_lan2wan(uint32_t inet_ip, uint16_t inet_port, uint32_t wnet_ip, uint16_t wnet_port) {
    uint32_t hash = 2166136261U;
    hash ^= inet_ip;
    hash *= 16777619U;
    hash ^= ((uint32_t)inet_port << 16) | wnet_port;
    hash *= 16777619U;
    hash ^= wnet_ip;
    hash *= 16777619U;
    return hash % NAPT_HASH_TABLE_SIZE;
}

// 初始化哈希表
static void napt_hash_init(luat_netdrv_napt_ctx_t *ctx) {
    if (ctx->hash_table_wan2lan == NULL) {
        ctx->hash_table_wan2lan = luat_heap_malloc(NAPT_HASH_TABLE_SIZE * sizeof(napt_hash_entry_t));
        if (ctx->hash_table_wan2lan) {
            for (size_t i = 0; i < NAPT_HASH_TABLE_SIZE; i++) {
                ctx->hash_table_wan2lan[i].item_index = NAPT_HASH_INVALID_INDEX;
                ctx->hash_table_wan2lan[i].next_index = NAPT_HASH_INVALID_INDEX;
            }
        }
    }
    if (ctx->hash_table_lan2wan == NULL) {
        ctx->hash_table_lan2wan = luat_heap_malloc(NAPT_HASH_TABLE_SIZE * sizeof(napt_hash_entry_t));
        if (ctx->hash_table_lan2wan) {
            for (size_t i = 0; i < NAPT_HASH_TABLE_SIZE; i++) {
                ctx->hash_table_lan2wan[i].item_index = NAPT_HASH_INVALID_INDEX;
                ctx->hash_table_lan2wan[i].next_index = NAPT_HASH_INVALID_INDEX;
            }
        }
    }
}

// 向哈希表添加映射（WAN->LAN）
__NETDRV_CODE_IN_RAM__ static void napt_hash_add_wan2lan(luat_netdrv_napt_ctx_t *ctx, uint16_t item_idx, luat_netdrv_napt_tcpudp_t *item) {
    if (ctx->hash_table_wan2lan == NULL) return;
    
    uint32_t hash = napt_hash_wan2lan(item->wnet_ip, item->wnet_port, item->wnet_local_port);
    napt_hash_entry_t *entry = &ctx->hash_table_wan2lan[hash];
    
    if (entry->item_index == NAPT_HASH_INVALID_INDEX) {
        // 空槽，直接放置
        entry->item_index = item_idx;
        entry->next_index = NAPT_HASH_INVALID_INDEX;
    } else {
        // 冲突，使用线性探测找下一个空槽
        for (size_t i = 1; i < NAPT_HASH_TABLE_SIZE; i++) {
            uint32_t probe = (hash + i) % NAPT_HASH_TABLE_SIZE;
            if (ctx->hash_table_wan2lan[probe].item_index == NAPT_HASH_INVALID_INDEX) {
                ctx->hash_table_wan2lan[probe].item_index = item_idx;
                ctx->hash_table_wan2lan[probe].next_index = NAPT_HASH_INVALID_INDEX;
                entry->next_index = probe;
                break;
            }
        }
    }
}

// 向哈希表添加映射（LAN->WAN）
__NETDRV_CODE_IN_RAM__ static void napt_hash_add_lan2wan(luat_netdrv_napt_ctx_t *ctx, uint16_t item_idx, luat_netdrv_napt_tcpudp_t *item) {
    if (ctx->hash_table_lan2wan == NULL) return;
    
    uint32_t hash = napt_hash_lan2wan(item->inet_ip, item->inet_port, item->wnet_ip, item->wnet_port);
    napt_hash_entry_t *entry = &ctx->hash_table_lan2wan[hash];
    
    if (entry->item_index == NAPT_HASH_INVALID_INDEX) {
        entry->item_index = item_idx;
        entry->next_index = NAPT_HASH_INVALID_INDEX;
    } else {
        for (size_t i = 1; i < NAPT_HASH_TABLE_SIZE; i++) {
            uint32_t probe = (hash + i) % NAPT_HASH_TABLE_SIZE;
            if (ctx->hash_table_lan2wan[probe].item_index == NAPT_HASH_INVALID_INDEX) {
                ctx->hash_table_lan2wan[probe].item_index = item_idx;
                ctx->hash_table_lan2wan[probe].next_index = NAPT_HASH_INVALID_INDEX;
                entry->next_index = probe;
                break;
            }
        }
    }
}

// 从哈希表查找映射（WAN->LAN）
__NETDRV_CODE_IN_RAM__ static int napt_hash_find_wan2lan(luat_netdrv_napt_ctx_t *ctx, uint32_t wnet_ip, uint16_t wnet_port, uint16_t wnet_local_port) {
    if (ctx->hash_table_wan2lan == NULL) return -1;
    
    uint32_t hash = napt_hash_wan2lan(wnet_ip, wnet_port, wnet_local_port);
    napt_hash_entry_t *entry = &ctx->hash_table_wan2lan[hash];
    
    while (entry->item_index != NAPT_HASH_INVALID_INDEX) {
        luat_netdrv_napt_tcpudp_t *item = &ctx->items[entry->item_index];
        if (item->wnet_ip == wnet_ip && item->wnet_port == wnet_port && item->wnet_local_port == wnet_local_port) {
            return entry->item_index;
        }
        if (entry->next_index == NAPT_HASH_INVALID_INDEX) break;
        entry = &ctx->hash_table_wan2lan[entry->next_index];
    }
    return -1;
}

// 从哈希表查找映射（LAN->WAN）
__NETDRV_CODE_IN_RAM__ static int napt_hash_find_lan2wan(luat_netdrv_napt_ctx_t *ctx, uint32_t inet_ip, uint16_t inet_port, uint32_t wnet_ip, uint16_t wnet_port) {
    if (ctx->hash_table_lan2wan == NULL) return -1;
    
    uint32_t hash = napt_hash_lan2wan(inet_ip, inet_port, wnet_ip, wnet_port);
    napt_hash_entry_t *entry = &ctx->hash_table_lan2wan[hash];
    
    while (entry->item_index != NAPT_HASH_INVALID_INDEX) {
        luat_netdrv_napt_tcpudp_t *item = &ctx->items[entry->item_index];
        if (item->inet_ip == inet_ip && item->inet_port == inet_port && 
            item->wnet_ip == wnet_ip && item->wnet_port == wnet_port) {
            return entry->item_index;
        }
        if (entry->next_index == NAPT_HASH_INVALID_INDEX) break;
        entry = &ctx->hash_table_lan2wan[entry->next_index];
    }
    return -1;
}

// 重建哈希表（在清理后调用）
static void napt_hash_rebuild(luat_netdrv_napt_ctx_t *ctx) {
    if (ctx->hash_table_wan2lan) {
        for (size_t i = 0; i < NAPT_HASH_TABLE_SIZE; i++) {
            ctx->hash_table_wan2lan[i].item_index = NAPT_HASH_INVALID_INDEX;
            ctx->hash_table_wan2lan[i].next_index = NAPT_HASH_INVALID_INDEX;
        }
    }
    if (ctx->hash_table_lan2wan) {
        for (size_t i = 0; i < NAPT_HASH_TABLE_SIZE; i++) {
            ctx->hash_table_lan2wan[i].item_index = NAPT_HASH_INVALID_INDEX;
            ctx->hash_table_lan2wan[i].next_index = NAPT_HASH_INVALID_INDEX;
        }
    }
    
    // 重新添加所有有效映射
    for (size_t i = 0; i < ctx->item_last; i++) {
        napt_hash_add_wan2lan(ctx, i, &ctx->items[i]);
        napt_hash_add_lan2wan(ctx, i, &ctx->items[i]);
    }
}

// ============ 哈希表优化函数结束 ============

#if !defined(LUAT_USE_PSRAM) && !defined(LUAT_USE_NETDRV_NAPT)
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
    return 0;
}
#else
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
    if (s_gw_adapter_id < 0) {
        // LLOGD("NAPT 未开启");
        return 0; // NAPT没有开启
    }
    luat_netdrv_t* drv = luat_netdrv_get(id);
    if (drv == NULL || drv->netif == NULL) {
        LLOGD("网关netif不存在,无法转发");
        return 0;
    }
    if (len < 24 || len > 1600) {
        LLOGD("包长度不合法, 拒绝改写 %d", len);
        return 0;
    }
    luat_netdrv_t* gw = luat_netdrv_get(s_gw_adapter_id);
    if (gw == NULL || gw->netif == NULL) {
        return 0; // 网关不存在, 那就没有转发
    }
    // 首先, 如果是eth网卡, 需要先判断是不是广播包
    napt_ctx_t ctx = {
        .buff = buff,
        .len = len,
        .iphdr = (struct ip_hdr*)(buff + SIZEOF_ETH_HDR),
        .eth = (struct eth_hdr*)buff,
        .is_wnet = s_gw_adapter_id == id,
        .net = drv,
        .drv_gw = gw,
    };

    if (drv->netif->flags & NETIF_FLAG_ETHARP) {
        // LLOGD("是ETH包, 先判断是不是广播包");
        if (memcmp(ctx.eth->dest.addr, "\xFF\xFF\xFF\xFF\xFF\xFF", 6) == 0 ||
            ctx.eth->dest.addr[0] == 0x01
        ) {
            // LLOGD("是广播包,不需要执行napt");
            return 0;
        }
        // LLOGD("ETH包 " MACFMT " -> " MACFMT " %04X", MAC_ARG(ctx.eth->src.addr), MAC_ARG(ctx.eth->dest.addr), ctx.eth->type);
        if (ctx.eth->type == PP_HTONS(ETHTYPE_ARP)) {
            // LLOGD("ETH包 " MACFMT " -> " MACFMT " %04X", MAC_ARG(ctx.eth->src.addr), MAC_ARG(ctx.eth->dest.addr), ctx.eth->type);
            if (s_gw_adapter_id == id) {
                // LLOGD("ETH包 " MACFMT " -> " MACFMT " %04X", MAC_ARG(ctx.eth->src.addr), MAC_ARG(ctx.eth->dest.addr), ctx.eth->type);
                // 这是网关侧的ARP包, 需要分析是否网关的ARP包, 然后更新到本地ARP表
                struct etharp_hdr* hdr = (struct etharp_hdr*)(buff + SIZEOF_ETH_HDR);
                ip4_addr_t sipaddr, dipaddr;
                // 是不是ARP回应
                // LLOGD("ARP数据 %04X %04X", hdr->opcode, PP_HTONS(ARP_REPLY));
                memcpy(&sipaddr, &hdr->sipaddr, 4);
                memcpy(&dipaddr, &hdr->dipaddr, 4);
                char tmp[16];
                ip4addr_ntoa_r(&sipaddr, tmp, 16);
                // LLOGD("ARP数据 %04X %04X from %s", hdr->opcode, PP_HTONS(ARP_REPLY), tmp);
                // if (hdr->opcode == PP_HTONS(ARP_REPLY)) {
                    // memcpy(&dipaddr, &hdr->dipaddr, 4);
                    if (gw && gw->netif) {
                        // LLOGD("sipaddr.addr %08X", sipaddr.addr);
                        memcpy(gw->gw_mac, hdr->shwaddr.addr, 6);
                        // LLOGD("网关MAC更新成功 %02X%02X%02X%02X%02X%02X", gw->gw_mac[0], gw->gw_mac[1], gw->gw_mac[2], gw->gw_mac[3], gw->gw_mac[4], gw->gw_mac[5]);
                        // return 0;
                    }
                    else {
                        // LLOGD("不是网关的ARP包? gw %p", gw);
                    }
                // }
            }
        }
        if (ctx.eth->type != PP_HTONS(ETHTYPE_IP)) {
            // LLOGD("不是IP包, 不需要执行napt");
            return 0;
        }
    }
    else {
        // LLOGD("不是ETH包, 裸IP包");
        ctx.iphdr = (struct ip_hdr*)(buff);
        ctx.eth = NULL;
    }

    // 看来是IP包了, 判断一下版本号
    u8_t ipVersion;
    ipVersion = IPH_V(ctx.iphdr);
    if (ipVersion != 4) {
        // LLOGD("不是ipv4包, 不需要执行napt");
        return 0;
    }
    if (s_gw_adapter_id != id && ctx.iphdr->dest.addr == ip_addr_get_ip4_u32(&drv->netif->ip_addr)) {
        // LLOGD("是本网关的包, 不需要执行napt");
        return 0;
    }
    if (IPH_PROTO(ctx.iphdr) != IP_PROTO_UDP && IPH_PROTO(ctx.iphdr) != IP_PROTO_TCP && IPH_PROTO(ctx.iphdr) != IP_PROTO_ICMP) {
        // LLOGD("不是tcp/udp/icmp包, 不需要执行napt");
        return 0;
    }
    // LLOGD("按协议类型, 使用对应的NAPT修改器进行处理 id %d proto %d", id, IPH_PROTO(ctx.iphdr));
    // uint64_t tbegin = luat_mcu_tick64();
    int ret = 0;
    switch (IPH_PROTO(ctx.iphdr))
    {
    case IP_PROTO_ICMP:
        ret = luat_napt_icmp_handle(&ctx);
        break;
    case IP_PROTO_TCP:
        ret = luat_napt_tcp_handle(&ctx);
        break;
    case IP_PROTO_UDP:
        ret = luat_napt_udp_handle(&ctx);
        break;
    default:
        // LLOGD("不是tcp/udp/icmp包, 不需要执行napt");
        return 0;
    }
    // uint64_t tend = luat_mcu_tick64();
    // uint64_t tused_us = (tend - tbegin) / luat_mcu_us_period();
    // if (tused_us > 100) {
    //     LLOGI("time used %4lld us tp %2d way %d", tused_us, IPH_PROTO(ctx.iphdr), s_gw_adapter_id == id);
    // }
    return ret;
}
#endif

static uint8_t* napt_buff;
err_t netdrv_ip_input_cb(int id, struct pbuf *p, struct netif *inp) {
    size_t len = p->tot_len;
    if (len > NAPT_MAX_PACKET_SIZE || len < 24) {
        return 1;
    }
    if (napt_buff == NULL) {
        napt_buff = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, 1600);
        if (napt_buff == NULL) {
            return ERR_MEM;
        }
    }
    pbuf_copy_partial(p, napt_buff, len, 0);
    int ret = luat_netdrv_napt_pkg_input(id, napt_buff, len);
    // LLOGD("napt_pkg_input ret %d", ret);
    // 返回: NAPT_RET_OK(0)表示已转发，其他值表示LWIP继续处理
    return ret == NAPT_RET_OK ? NAPT_RET_OK : NAPT_RET_SKIP;
    // return 1;
}

// 辅助函数
int luat_netdrv_napt_pkg_input_pbuf(int id, struct pbuf* p) {
    if (p == NULL || p->tot_len > NAPT_MAX_PACKET_SIZE) {
        return 0;
    }
    // LLOGD("pbuf情况 total %d len %d", p->tot_len, p->len);
    if (p->tot_len == p->len) {
        // LLOGD("其实就是单个pbuf");
        return luat_netdrv_napt_pkg_input(id, p->payload, p->tot_len);
    }
    uint8_t* tmp = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, p->tot_len);
    if (tmp) {
        pbuf_copy_partial(p, tmp, p->tot_len, 0);
        int ret = luat_netdrv_napt_pkg_input(id, tmp, p->tot_len);
        luat_heap_free(tmp);
        return ret;
    }
    return 0; // lwip继续处理 
}

static int ctx_init(luat_netdrv_napt_ctx_t** ctx_ptrptr) {
    luat_netdrv_napt_ctx_t* ctx = NULL;
    ctx = luat_heap_malloc(sizeof(luat_netdrv_napt_ctx_t));
    if (ctx == NULL) {
        LLOGE("初始化napt_ctx失败");
        return -1;
    }
    memset(ctx, 0, sizeof(luat_netdrv_napt_ctx_t));
    luat_rtos_mutex_create(&ctx->lock);
    // 正确计算端口位图大小: (端口数 + 31) / 32 * 4 字节
    size_t port_len = NAPT_PORT_BITMAP_SIZE;
    ctx->port_used = luat_heap_malloc(port_len);
    if (ctx->port_used == NULL) {
        LLOGE("初始化napt port_used失败");
        luat_heap_free(ctx);
        return -1;
    }
    memset(ctx->port_used, 0, port_len);
    ctx->clean_tm = 1;
    ctx->item_max = NAPT_TCP_MAP_ITEM_MAX;
    
    // 初始化哈希表
    ctx->hash_table_wan2lan = NULL;
    ctx->hash_table_lan2wan = NULL;
    napt_hash_init(ctx);

    *ctx_ptrptr = ctx;
    return 0;
}

void luat_netdrv_napt_enable(int adapter_id) {
    if (adapter_id > 0) {
        if (g_napt_tcp_ctx == NULL) {
            ctx_init(&g_napt_tcp_ctx);
            g_napt_tcp_ctx->ip_tp = IP_PROTO_TCP;
        }
        if (g_napt_udp_ctx == NULL) {
            ctx_init(&g_napt_udp_ctx);
            g_napt_udp_ctx->ip_tp = IP_PROTO_UDP;
        }
    }
    s_gw_adapter_id = adapter_id;
}

void luat_netdrv_napt_disable(void) {
    s_gw_adapter_id = -1;
    
    // 清理TCP上下文
    if (g_napt_tcp_ctx) {
        if (g_napt_tcp_ctx->port_used) {
            luat_heap_free(g_napt_tcp_ctx->port_used);
            g_napt_tcp_ctx->port_used = NULL;
        }
        if (g_napt_tcp_ctx->hash_table_wan2lan) {
            luat_heap_free(g_napt_tcp_ctx->hash_table_wan2lan);
            g_napt_tcp_ctx->hash_table_wan2lan = NULL;
        }
        if (g_napt_tcp_ctx->hash_table_lan2wan) {
            luat_heap_free(g_napt_tcp_ctx->hash_table_lan2wan);
            g_napt_tcp_ctx->hash_table_lan2wan = NULL;
        }
        luat_rtos_mutex_delete(g_napt_tcp_ctx->lock);
        luat_heap_free(g_napt_tcp_ctx);
        g_napt_tcp_ctx = NULL;
    }
    
    // 清理UDP上下文
    if (g_napt_udp_ctx) {
        if (g_napt_udp_ctx->port_used) {
            luat_heap_free(g_napt_udp_ctx->port_used);
            g_napt_udp_ctx->port_used = NULL;
        }
        if (g_napt_udp_ctx->hash_table_wan2lan) {
            luat_heap_free(g_napt_udp_ctx->hash_table_wan2lan);
            g_napt_udp_ctx->hash_table_wan2lan = NULL;
        }
        if (g_napt_udp_ctx->hash_table_lan2wan) {
            luat_heap_free(g_napt_udp_ctx->hash_table_lan2wan);
            g_napt_udp_ctx->hash_table_lan2wan = NULL;
        }
        luat_rtos_mutex_delete(g_napt_udp_ctx->lock);
        luat_heap_free(g_napt_udp_ctx);
        g_napt_udp_ctx = NULL;
    }
    
    // 清理缓冲区
    if (napt_buff) {
        luat_heap_free(napt_buff);
        napt_buff = NULL;
    }
    
    // 调用TCP/UDP的cleanup函数
    luat_netdrv_napt_tcp_cleanup();
    luat_netdrv_napt_udp_cleanup();
}
__NETDRV_CODE_IN_RAM__ static size_t luat_napt_tcp_port_alloc(luat_netdrv_napt_ctx_t *napt_ctx) {
    size_t offset;
    size_t soffset;
    for (size_t i = 0; i < NAPT_PORT_COUNT; i++) {
        offset = i / 32;  // 每个uint32_t占32位
        soffset = i % 32;
        if ((napt_ctx->port_used[offset] & (1 << soffset)) == 0) {
            napt_ctx->port_used[offset] |= (1 << soffset);
            return i + NAPT_PORT_RANGE_START;
        }
    }
    return 0;
}

static void print_item(const char* tag, luat_netdrv_napt_tcpudp_t* it) {
    char buff[32] = {0};
    char buff2[32] = {0};
    ip_addr_t ipaddr = {0};
    // 输出可视化的本地ip
    ip_addr_set_ip4_u32(&ipaddr, it->inet_ip);
    ipaddr_ntoa_r(&ipaddr, buff, 32);

    // 输出可视化的远程ip
    ip_addr_set_ip4_u32(&ipaddr, it->wnet_ip);
    ipaddr_ntoa_r(&ipaddr, buff2, 32);

    LLOGD("%s %s:%d -> %s:%d local %d", tag, buff2, it->wnet_port, buff, it->inet_port, it->wnet_local_port);
}

__NETDRV_CODE_IN_RAM__ static void mapping_cleanup(luat_netdrv_napt_ctx_t *napt_ctx) {
    uint64_t tnow = luat_mcu_tick64_ms();
    luat_netdrv_napt_tcpudp_t* it = NULL;
    uint64_t tdiff = 0;
    size_t offset;
    size_t soffset;
    size_t port;
    int flag = 0;
    size_t cur_index = 0;

    if (napt_ctx->item_last == 0) {
        return;
    }
    for (size_t i = 0; i < napt_ctx->item_last; i++) {
        flag = 0;
        it = &napt_ctx->items[i];
        tdiff = tnow - it->tm_ms;
        if (napt_ctx->ip_tp == IP_PROTO_TCP) {
            if (tdiff > NAPT_TCP_TIMEOUT_MS) { // TCP是20分钟
                flag = 1;
            }
            else if ((((it->finack1 && it->finack2) || !it->synack) && tdiff > NAPT_TCP_DISCON_TIMEOUT_MS)) {
                // print_item("TCP链接已关闭,移除", it);
                flag = 1;
            }
        }
        else if (napt_ctx->ip_tp == IP_PROTO_UDP) {
            if (tdiff > NAPT_UDP_TIMEOUT_MS) { // UDP 是2分钟
                flag = 1;
            }
        }
        if (flag == 1) {
            // 标记为删除
            it->is_vaild = 0;
            it->tm_ms = 0;
            port = it->wnet_local_port - NAPT_PORT_RANGE_START;
            offset = port / 32;  // 每个uint32_t占32位
            soffset = port % 32;
            // 检查offset是否在有效范围内
            size_t max_offset = (NAPT_PORT_COUNT + 31) / 32;
            if (offset >= max_offset) {
                LLOGE("非法的offset %d, 最大值应为 %d", offset, max_offset - 1);
            }
            else {
                napt_ctx->port_used[offset] &= (~(1 << soffset));
            }
        }
        else {
            // 需要保留的记录, 是否需要往前移动呢
            if (cur_index != i) {
                memcpy(&napt_ctx->items[cur_index], it, sizeof(luat_netdrv_napt_tcpudp_t));
                memset(&napt_ctx->items[i], 0, sizeof(luat_netdrv_napt_tcpudp_t));
            }
            cur_index ++;
        }
    }
    // 全部标记完成了, 记录最后的位置
    // LLOGD("清理前后对比 %ld -> %ld", ctx->item_last, cur_index);
    napt_ctx->item_last = cur_index;
    
    // 重建哈希表
    napt_hash_rebuild(napt_ctx);
}


__NETDRV_CODE_IN_RAM__ static void update_tcp_stat_wnet(struct tcp_hdr *tcphdr, luat_netdrv_napt_tcpudp_t* t) {
    if ((TCPH_FLAGS(tcphdr) & (TCP_SYN|TCP_ACK)) == (TCP_SYN|TCP_ACK)) {
      t->synack = 1;
    //   LLOGD("收到TCP SYN ACK, 连接已建立");
    }
    if ((TCPH_FLAGS(tcphdr) & TCP_FIN)) {
      t->fin1 = 1;
    }
    if (t->fin2 && (TCPH_FLAGS(tcphdr) & TCP_ACK)) {
      t->finack2 = 1; /* FIXME: Currently ignoring ACK seq... */
    //   LLOGD("收到TCP FIN2 ACK, 连接完成断开");
    }
    if (TCPH_FLAGS(tcphdr) & TCP_RST) {
      t->rst = 1;
    }
//   LLOGD("TCP链路状态 synack %d fin1 %d finack2 %d rst %d", t->synack, t->fin1, t->finack2, t->rst);
}

__NETDRV_CODE_IN_RAM__ static void update_tcp_stat_inet(struct tcp_hdr *tcphdr, luat_netdrv_napt_tcpudp_t* t) {
    if ((TCPH_FLAGS(tcphdr) & TCP_FIN))
        t->fin2 = 1;
    if (t->fin1 && (TCPH_FLAGS(tcphdr) & TCP_ACK))
        t->finack1 = 1; /* FIXME: Currently ignoring ACK seq... */
    if (TCPH_FLAGS(tcphdr) & TCP_RST)
        t->rst = 1;
    // LLOGD("TCP链路状态 synack %d fin1 %d finack2 %d rst %d", t->synack, t->fin1, t->finack2, t->rst);
}

// 外网到内网
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_tcp_wan2lan(napt_ctx_t* ctx, luat_netdrv_napt_tcpudp_t* mapping, luat_netdrv_napt_ctx_t *napt_ctx) {
    int ret = -1;
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    // struct ip_hdr* ip_hdr = ctx->iphdr;
    uint64_t tnow = luat_mcu_tick64_ms();
    uint32_t tsec = (uint32_t)(tnow / 1000);
    luat_netdrv_napt_tcpudp_t tmp = {0};
    luat_netdrv_napt_tcpudp_t* it = NULL;
    struct tcp_hdr *tcp_hdr = (struct tcp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);
    struct udp_hdr *udp_hdr = (struct udp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);

    tmp.wnet_ip = ctx->iphdr->src.addr;
    if (napt_ctx->ip_tp == IP_PROTO_TCP) {
        tmp.wnet_port = tcp_hdr->src;
        tmp.wnet_local_port = tcp_hdr->dest;
    }
    else {
        tmp.wnet_port = udp_hdr->src;
        tmp.wnet_local_port = udp_hdr->dest;
    }

    luat_rtos_mutex_lock(napt_ctx->lock, 5000);
    // 清理映射关系
    if (tsec - napt_ctx->clean_tm > NAPT_CLEANUP_INTERVAL_SEC) {
        // LLOGD("执行映射关系清理 %ld %ld", tsec, napt_ctx->clean_tm);
        mapping_cleanup(napt_ctx);
        napt_ctx->clean_tm = tsec;
        // LLOGD("完成映射关系清理 %ld %ld", tsec, napt_ctx->clean_tm);
    }
    
    // 使用哈希表快速查找
    int idx = napt_hash_find_wan2lan(napt_ctx, tmp.wnet_ip, tmp.wnet_port, tmp.wnet_local_port);
    if (idx >= 0 && idx < (int)napt_ctx->item_last) {
        it = &napt_ctx->items[idx];
        it->tm_ms = tnow;
        memcpy(mapping, it, sizeof(luat_netdrv_napt_tcpudp_t));
        ret = NAPT_RET_OK;
        if (napt_ctx->ip_tp == IP_PROTO_TCP) {
            update_tcp_stat_wnet(tcp_hdr, it);
        }
    }
    
    luat_rtos_mutex_unlock(napt_ctx->lock);
    return ret;
}

// 内网到外网
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_tcp_lan2wan(napt_ctx_t* ctx, luat_netdrv_napt_tcpudp_t* mapping, luat_netdrv_napt_ctx_t *napt_ctx) {
    int ret = -1;
    luat_netdrv_napt_tcpudp_t* it = NULL;
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    // struct ip_hdr* ip_hdr = ctx->iphdr;
    uint64_t tnow = luat_mcu_tick64_ms();
    uint32_t tsec = (uint32_t)(tnow / 1000);
    luat_netdrv_napt_tcpudp_t tmp = {0};
    // size_t tmpaddr = 0;
    struct tcp_hdr *tcp_hdr = (struct tcp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);
    struct udp_hdr *udp_hdr = (struct udp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);
    size_t c_all = 0;

    tmp.inet_ip = ctx->iphdr->src.addr;
    tmp.wnet_ip = ctx->iphdr->dest.addr;
    if (napt_ctx->ip_tp == IP_PROTO_TCP) {
        tmp.inet_port = tcp_hdr->src;
        tmp.wnet_port = tcp_hdr->dest;
    }
    else {
        tmp.inet_port = udp_hdr->src;
        tmp.wnet_port = udp_hdr->dest;
    }
    
    ret = luat_rtos_mutex_lock(napt_ctx->lock, 1000);
    if (ret) {
        LLOGE("napt加锁失败!!! ret %d", ret);
        return -4;
    }
    ret = -1;

    // 清理映射关系
    if (tsec - napt_ctx->clean_tm > NAPT_CLEANUP_INTERVAL_SEC) {
        mapping_cleanup(napt_ctx);
        napt_ctx->clean_tm = tsec;
    }
    
    // 使用哈希表快速查找
    int idx = napt_hash_find_lan2wan(napt_ctx, tmp.inet_ip, tmp.inet_port, tmp.wnet_ip, tmp.wnet_port);
    if (idx >= 0 && idx < (int)napt_ctx->item_last) {
        it = &napt_ctx->items[idx];
        it->tm_ms = tnow;
        ret = NAPT_RET_OK;
        memcpy(mapping, it, sizeof(luat_netdrv_napt_tcpudp_t));
        // 映射关系找到了,那就关联一下情况
        if (napt_ctx->ip_tp == IP_PROTO_TCP) {
            update_tcp_stat_inet(tcp_hdr, it);
        }
    }
    while (ret != 0) {
        if (napt_ctx->item_max == 0) {
            napt_ctx->item_max = NAPT_TCP_MAP_ITEM_MAX;
        }
        if (napt_ctx->item_last >= napt_ctx->item_max) {
            LLOGE("TCP映射关系已经用完");
            ret = - 2;
            break;
        }
        tmp.wnet_local_port = luat_napt_tcp_port_alloc(napt_ctx);
        if (tmp.wnet_local_port == 0) {
            LLOGE("可用映射端口已经用完"); // 实际应该是不可能的, 因为映射总数小于端口范围
            ret = - 2;
            break;
        }
        tmp.adapter_id = ctx->net->id;
        tmp.tm_ms = tnow;
        it = &napt_ctx->items[napt_ctx->item_last];
        memcpy(it, &tmp, sizeof(luat_netdrv_napt_tcpudp_t));
        
        // 添加到哈希表
        napt_hash_add_wan2lan(napt_ctx, napt_ctx->item_last, it);
        napt_hash_add_lan2wan(napt_ctx, napt_ctx->item_last, it);
        
        napt_ctx->item_last ++;
        if (ctx->eth) {
            memcpy(it->inet_mac, ctx->eth->src.addr, 6);
        }
        else {
            memset(it->inet_mac, 0, 6);
        }
        memcpy(mapping, it, sizeof(luat_netdrv_napt_tcpudp_t));
        ret = NAPT_RET_OK;
        break;
    }

    // unlock
    luat_rtos_mutex_unlock(napt_ctx->lock);

    return ret;
}
