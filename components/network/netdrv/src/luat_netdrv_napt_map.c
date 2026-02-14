#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_napt.h"
#include "luat_mcu.h"
#include "luat_mem.h"

#include "lwip/ip.h"
#include "lwip/udp.h"
#include "lwip/tcp.h"
#include "lwip/ip_addr.h"

#define LUAT_LOG_TAG "netdrv.napt.map"
#include "luat_log.h"

// 端口分配范围
#define NAPT_PORT_RANGE_START     0x1BBC
#define NAPT_PORT_RANGE_END       0x6AAA
#define NAPT_PORT_BITMAP_LEN      ((NAPT_PORT_RANGE_END - NAPT_PORT_RANGE_START + 31) / 32)

// 全局NAPT上下文（供TCP/UDP处理使用）
luat_netdrv_napt_ctx_t *g_napt_tcp_ctx;
luat_netdrv_napt_ctx_t *g_napt_udp_ctx;

// 简单FNV-1a哈希
static inline uint32_t napt_hash_fnv1a(const uint8_t *data, size_t len) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < len; i++) {
        h ^= data[i];
        h *= 16777619u;
    }
    return h;
}

static inline uint32_t napt_hash_wan2lan_key(const luat_netdrv_napt_tcpudp_t *it) {
    return napt_hash_fnv1a((const uint8_t *)&it->wnet_ip, 8u);
}

static inline uint32_t napt_hash_lan2wan_key(const luat_netdrv_napt_tcpudp_t *it) {
    return napt_hash_fnv1a((const uint8_t *)&it->inet_ip, 12u);
}

static void napt_hash_reset(luat_netdrv_napt_ctx_t *ctx) {
    if (ctx->hash_table_wan2lan) {
        for (size_t i = 0; i < NAPT_HASH_TABLE_SIZE; i++) {
            ctx->hash_table_wan2lan[i].item_index = NAPT_HASH_INVALID_INDEX;
        }
    }
    if (ctx->hash_table_lan2wan) {
        for (size_t i = 0; i < NAPT_HASH_TABLE_SIZE; i++) {
            ctx->hash_table_lan2wan[i].item_index = NAPT_HASH_INVALID_INDEX;
        }
    }
}

static void napt_hash_insert_w2l(luat_netdrv_napt_ctx_t *ctx, uint16_t item_index) {
    if (!ctx->hash_table_wan2lan) return;
    const luat_netdrv_napt_tcpudp_t *it = &ctx->items[item_index];
    uint32_t h = napt_hash_wan2lan_key(it);
    uint32_t idx = h % NAPT_HASH_TABLE_SIZE;
    for (uint32_t p = 0; p < NAPT_HASH_MAX_PROBE; p++) {
        uint32_t slot = (idx + p) % NAPT_HASH_TABLE_SIZE;
        if (ctx->hash_table_wan2lan[slot].item_index == NAPT_HASH_INVALID_INDEX) {
            ctx->hash_table_wan2lan[slot].item_index = item_index;
            return;
        }
    }
}

static void napt_hash_insert_l2w(luat_netdrv_napt_ctx_t *ctx, uint16_t item_index) {
    if (!ctx->hash_table_lan2wan) return;
    const luat_netdrv_napt_tcpudp_t *it = &ctx->items[item_index];
    uint32_t h = napt_hash_lan2wan_key(it);
    uint32_t idx = h % NAPT_HASH_TABLE_SIZE;
    for (uint32_t p = 0; p < NAPT_HASH_MAX_PROBE; p++) {
        uint32_t slot = (idx + p) % NAPT_HASH_TABLE_SIZE;
        if (ctx->hash_table_lan2wan[slot].item_index == NAPT_HASH_INVALID_INDEX) {
            ctx->hash_table_lan2wan[slot].item_index = item_index;
            return;
        }
    }
}

static uint16_t napt_hash_lookup_w2l(luat_netdrv_napt_ctx_t *ctx, const luat_netdrv_napt_tcpudp_t *key_like) {
    if (!ctx->hash_table_wan2lan) return NAPT_HASH_INVALID_INDEX;
    uint32_t h = napt_hash_fnv1a((const uint8_t *)&key_like->wnet_ip, 8u);
    uint32_t idx = h % NAPT_HASH_TABLE_SIZE;
    for (uint32_t p = 0; p < NAPT_HASH_MAX_PROBE; p++) {
        uint32_t slot = (idx + p) % NAPT_HASH_TABLE_SIZE;
        uint16_t ii = ctx->hash_table_wan2lan[slot].item_index;
        if (ii == NAPT_HASH_INVALID_INDEX) return NAPT_HASH_INVALID_INDEX;
        const luat_netdrv_napt_tcpudp_t *it = &ctx->items[ii];
        if (memcmp(&key_like->wnet_ip, &it->wnet_ip, 8u) == 0) return ii;
    }
    return NAPT_HASH_INVALID_INDEX;
}

static uint16_t napt_hash_lookup_l2w(luat_netdrv_napt_ctx_t *ctx, const luat_netdrv_napt_tcpudp_t *key_like) {
    if (!ctx->hash_table_lan2wan) return NAPT_HASH_INVALID_INDEX;
    uint32_t h = napt_hash_fnv1a((const uint8_t *)&key_like->inet_ip, 12u);
    uint32_t idx = h % NAPT_HASH_TABLE_SIZE;
    for (uint32_t p = 0; p < NAPT_HASH_MAX_PROBE; p++) {
        uint32_t slot = (idx + p) % NAPT_HASH_TABLE_SIZE;
        uint16_t ii = ctx->hash_table_lan2wan[slot].item_index;
        if (ii == NAPT_HASH_INVALID_INDEX) return NAPT_HASH_INVALID_INDEX;
        const luat_netdrv_napt_tcpudp_t *it = &ctx->items[ii];
        if (memcmp(&key_like->inet_ip, &it->inet_ip, 12u) == 0) return ii;
    }
    return NAPT_HASH_INVALID_INDEX;
}

static void napt_hash_rebuild(luat_netdrv_napt_ctx_t *ctx) {
    if (!ctx->hash_table_wan2lan || !ctx->hash_table_lan2wan) return;
    napt_hash_reset(ctx);
    for (uint16_t i = 0; i < ctx->item_last; i++) {
        napt_hash_insert_w2l(ctx, i);
        napt_hash_insert_l2w(ctx, i);
    }
}

// 内部：初始化单个上下文
static int ctx_init(luat_netdrv_napt_ctx_t **ctx_ptrptr) {
    luat_netdrv_napt_ctx_t *ctx = luat_heap_malloc(sizeof(luat_netdrv_napt_ctx_t));
    if (ctx == NULL) {
        LLOGE("初始化napt_ctx失败");
        return -1;
    }
    memset(ctx, 0, sizeof(luat_netdrv_napt_ctx_t));
    luat_rtos_mutex_create(&ctx->lock);
    size_t port_len = (NAPT_PORT_RANGE_END - NAPT_PORT_RANGE_START) / 4;
    ctx->port_used = luat_heap_malloc(port_len + 8);
    memset(ctx->port_used, 0, port_len + 8);
    ctx->clean_tm = 1;
    ctx->item_max = NAPT_TCP_MAP_ITEM_MAX;
    // 分配哈希表
    ctx->hash_table_wan2lan = (napt_hash_entry_t *)luat_heap_malloc(sizeof(napt_hash_entry_t) * NAPT_HASH_TABLE_SIZE);
    ctx->hash_table_lan2wan = (napt_hash_entry_t *)luat_heap_malloc(sizeof(napt_hash_entry_t) * NAPT_HASH_TABLE_SIZE);
    if (!ctx->hash_table_wan2lan || !ctx->hash_table_lan2wan) {
        LLOGE("分配哈希表失败");
        // 即使失败也允许继续（回退为线性扫描）
        if (ctx->hash_table_wan2lan) memset(ctx->hash_table_wan2lan, 0xFF, sizeof(napt_hash_entry_t) * NAPT_HASH_TABLE_SIZE);
        if (ctx->hash_table_lan2wan) memset(ctx->hash_table_lan2wan, 0xFF, sizeof(napt_hash_entry_t) * NAPT_HASH_TABLE_SIZE);
    } else {
        napt_hash_reset(ctx);
    }
    *ctx_ptrptr = ctx;
    return 0;
}

int luat_netdrv_napt_init_contexts(void) {
    if (g_napt_tcp_ctx == NULL) {
        if (ctx_init(&g_napt_tcp_ctx)) return -1;
        g_napt_tcp_ctx->ip_tp = IP_PROTO_TCP;
    }
    if (g_napt_udp_ctx == NULL) {
        if (ctx_init(&g_napt_udp_ctx)) return -1;
        g_napt_udp_ctx->ip_tp = IP_PROTO_UDP;
    }
    // 初始构建（空表）
    if (g_napt_tcp_ctx) napt_hash_rebuild(g_napt_tcp_ctx);
    if (g_napt_udp_ctx) napt_hash_rebuild(g_napt_udp_ctx);
    return 0;
}

__NETDRV_CODE_IN_RAM__ static size_t luat_napt_tcp_port_alloc(luat_netdrv_napt_ctx_t *napt_ctx) {
    size_t offset;
    size_t soffset;
    for (size_t i = 0; i <= NAPT_PORT_RANGE_END - NAPT_PORT_RANGE_START; i++) {
        offset = i / (4 * 8);
        soffset = i % (4 * 8);
        if ((napt_ctx->port_used[offset] & (1 << soffset)) == 0) {
            napt_ctx->port_used[offset] |= (1 << soffset);
            return i + NAPT_PORT_RANGE_START;
        }
    }
    return 0;
}

__NETDRV_CODE_IN_RAM__ static void mapping_cleanup(luat_netdrv_napt_ctx_t *napt_ctx) {
    uint64_t tnow = luat_mcu_tick64_ms();
    luat_netdrv_napt_tcpudp_t *it = NULL;
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
            if (tdiff > 20 * 60 * 1000) { // TCP 20分钟
                flag = 1;
            } else if ((((it->finack1 && it->finack2) || !it->synack) && tdiff > IP_NAPT_TIMEOUT_MS_TCP_DISCON)) {
                flag = 1;
            }
        } else if (napt_ctx->ip_tp == IP_PROTO_UDP) {
            if (tdiff > 2 * 60 * 1000) { // UDP 2分钟
                flag = 1;
            }
        }
        if (flag == 1) {
            it->is_vaild = 0;
            it->tm_ms = 0;
            port = it->wnet_local_port - NAPT_PORT_RANGE_START;
            offset = port / (4 * 8);
            soffset = port % (4 * 8);
            if (offset < NAPT_PORT_BITMAP_LEN) {
                napt_ctx->port_used[offset] &= (~(1 << soffset));
            } else {
                LLOGE("非法的offset %d", (int)offset);
            }
        } else {
            if (cur_index != i) {
                memcpy(&napt_ctx->items[cur_index], it, sizeof(luat_netdrv_napt_tcpudp_t));
                memset(&napt_ctx->items[i], 0, sizeof(luat_netdrv_napt_tcpudp_t));
            }
            cur_index++;
        }
    }
    napt_ctx->item_last = cur_index;
    // 重建哈希表以同步位置变化
    napt_hash_rebuild(napt_ctx);
}

__NETDRV_CODE_IN_RAM__ static void update_tcp_stat_wnet(struct tcp_hdr *tcphdr, luat_netdrv_napt_tcpudp_t *t) {
    if ((TCPH_FLAGS(tcphdr) & (TCP_SYN | TCP_ACK)) == (TCP_SYN | TCP_ACK)) {
        t->synack = 1;
    }
    if ((TCPH_FLAGS(tcphdr) & TCP_FIN)) {
        t->fin1 = 1;
    }
    if (t->fin2 && (TCPH_FLAGS(tcphdr) & TCP_ACK)) {
        t->finack2 = 1;
    }
    if (TCPH_FLAGS(tcphdr) & TCP_RST) {
        t->rst = 1;
    }
}

__NETDRV_CODE_IN_RAM__ static void update_tcp_stat_inet(struct tcp_hdr *tcphdr, luat_netdrv_napt_tcpudp_t *t) {
    if ((TCPH_FLAGS(tcphdr) & TCP_FIN))
        t->fin2 = 1;
    if (t->fin1 && (TCPH_FLAGS(tcphdr) & TCP_ACK))
        t->finack1 = 1;
    if (TCPH_FLAGS(tcphdr) & TCP_RST)
        t->rst = 1;
}

// 外网到内网
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_tcp_wan2lan(napt_ctx_t *ctx, luat_netdrv_napt_tcpudp_t *mapping, luat_netdrv_napt_ctx_t *napt_ctx) {
    int ret = -1;
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    uint64_t tnow = luat_mcu_tick64_ms();
    uint32_t tsec = (uint32_t)(tnow / 1000);
    luat_netdrv_napt_tcpudp_t tmp = {0};
    luat_netdrv_napt_tcpudp_t *it = NULL;
    struct tcp_hdr *tcp_hdr = (struct tcp_hdr *)(((uint8_t *)ctx->iphdr) + iphdr_len);
    struct udp_hdr *udp_hdr = (struct udp_hdr *)(((uint8_t *)ctx->iphdr) + iphdr_len);

    tmp.wnet_ip = ctx->iphdr->src.addr;
    if (napt_ctx->ip_tp == IP_PROTO_TCP) {
        tmp.wnet_port = tcp_hdr->src;
        tmp.wnet_local_port = tcp_hdr->dest;
    } else {
        tmp.wnet_port = udp_hdr->src;
        tmp.wnet_local_port = udp_hdr->dest;
    }

    luat_rtos_mutex_lock(napt_ctx->lock, 5000);
    if (tsec - napt_ctx->clean_tm > 5) {
        mapping_cleanup(napt_ctx);
        napt_ctx->clean_tm = tsec;
    }
    uint16_t idx = napt_hash_lookup_w2l(napt_ctx, &tmp);
    if (idx != NAPT_HASH_INVALID_INDEX) {
        it = &napt_ctx->items[idx];
        it->tm_ms = tnow;
        memcpy(mapping, it, sizeof(luat_netdrv_napt_tcpudp_t));
        ret = 0;
        if (napt_ctx->ip_tp == IP_PROTO_TCP) {
            update_tcp_stat_wnet(tcp_hdr, it);
        }
    } else {
        // 回退线性扫描（极端冲突或无哈希表）
        for (size_t i = 0; i < napt_ctx->item_last; i++) {
            it = &napt_ctx->items[i];
            if (memcmp(&tmp.wnet_ip, &it->wnet_ip, 8) == 0) {
                it->tm_ms = tnow;
                memcpy(mapping, it, sizeof(luat_netdrv_napt_tcpudp_t));
                ret = 0;
                if (napt_ctx->ip_tp == IP_PROTO_TCP) {
                    update_tcp_stat_wnet(tcp_hdr, it);
                }
                break;
            }
        }
    }
    luat_rtos_mutex_unlock(napt_ctx->lock);
    return ret;
}

// 内网到外网
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_tcp_lan2wan(napt_ctx_t *ctx, luat_netdrv_napt_tcpudp_t *mapping, luat_netdrv_napt_ctx_t *napt_ctx) {
    int ret = -1;
    luat_netdrv_napt_tcpudp_t *it = NULL;
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    uint64_t tnow = luat_mcu_tick64_ms();
    uint32_t tsec = (uint32_t)(tnow / 1000);
    luat_netdrv_napt_tcpudp_t tmp = {0};
    struct tcp_hdr *tcp_hdr = (struct tcp_hdr *)(((uint8_t *)ctx->iphdr) + iphdr_len);
    struct udp_hdr *udp_hdr = (struct udp_hdr *)(((uint8_t *)ctx->iphdr) + iphdr_len);

    tmp.inet_ip = ctx->iphdr->src.addr;
    tmp.wnet_ip = ctx->iphdr->dest.addr;
    if (napt_ctx->ip_tp == IP_PROTO_TCP) {
        tmp.inet_port = tcp_hdr->src;
        tmp.wnet_port = tcp_hdr->dest;
    } else {
        tmp.inet_port = udp_hdr->src;
        tmp.wnet_port = udp_hdr->dest;
    }

    ret = luat_rtos_mutex_lock(napt_ctx->lock, 1000);
    if (ret) {
        LLOGE("napt加锁失败!!! ret %d", ret);
        return NAPT_RET_INVALID_CTX;
    }
    ret = -1;

    if (tsec - napt_ctx->clean_tm > 5) {
        mapping_cleanup(napt_ctx);
        napt_ctx->clean_tm = tsec;
    }
    uint16_t idx = napt_hash_lookup_l2w(napt_ctx, &tmp);
    if (idx != NAPT_HASH_INVALID_INDEX) {
        it = &napt_ctx->items[idx];
        it->tm_ms = tnow;
        ret = 0;
        memcpy(mapping, it, sizeof(luat_netdrv_napt_tcpudp_t));
        if (napt_ctx->ip_tp == IP_PROTO_TCP) {
            update_tcp_stat_inet(tcp_hdr, it);
        }
    } else {
        // 回退线性扫描（极端冲突或无哈希表）
        for (size_t i = 0; i < napt_ctx->item_last; i++) {
            it = &napt_ctx->items[i];
            if (memcmp(&tmp.inet_ip, &it->inet_ip, 12u) == 0) {
                it->tm_ms = tnow;
                ret = 0;
                memcpy(mapping, it, sizeof(luat_netdrv_napt_tcpudp_t));
                if (napt_ctx->ip_tp == IP_PROTO_TCP) {
                    update_tcp_stat_inet(tcp_hdr, it);
                }
                break;
            }
        }
    }
    while (ret != 0) {
        if (napt_ctx->item_max == 0) {
            napt_ctx->item_max = NAPT_TCP_MAP_ITEM_MAX;
        }
        if (napt_ctx->item_last >= napt_ctx->item_max) {
            LLOGE("TCP映射关系已经用完");
            ret = NAPT_RET_NO_MEMORY;
            break;
        }
        tmp.wnet_local_port = luat_napt_tcp_port_alloc(napt_ctx);
        if (tmp.wnet_local_port == 0) {
            LLOGE("可用映射端口已经用完");
            ret = NAPT_RET_NO_MEMORY;
            break;
        }
        tmp.adapter_id = ctx->net->id;
        tmp.tm_ms = tnow;
        it = &napt_ctx->items[napt_ctx->item_last];
        memcpy(it, &tmp, sizeof(luat_netdrv_napt_tcpudp_t));
        napt_ctx->item_last++;
        if (ctx->eth) {
            memcpy(it->inet_mac, ctx->eth->src.addr, 6);
        } else {
            memset(it->inet_mac, 0, 6);
        }
        memcpy(mapping, it, sizeof(luat_netdrv_napt_tcpudp_t));
        // 新增项写入哈希表
        uint16_t new_index = (uint16_t)(napt_ctx->item_last - 1);
        napt_hash_insert_w2l(napt_ctx, new_index);
        napt_hash_insert_l2w(napt_ctx, new_index);
        ret = 0;
        break;
    }

    luat_rtos_mutex_unlock(napt_ctx->lock);
    return ret;
}
