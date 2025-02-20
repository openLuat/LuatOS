#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_napt.h"
#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/icmp.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "netdrv.napt.icmp"
#include "luat_log.h"

#define ICMP_MAP_SIZE (64)
#define ICMP_MAP_TIMEOUT (5000)

/* napt icmp id range: 3000-65535 */
#define NAPT_ICMP_ID_RANGE_START     0x1BB8
#define NAPT_ICMP_ID_RANGE_END       0xFFFF

extern int luat_netdrv_gw_adapter_id;
static uint16_t napt_curr_id = NAPT_ICMP_ID_RANGE_START;
static luat_netdrv_napt_icmp_t icmps[ICMP_MAP_SIZE];

#define u32 uint32_t
#define u16 uint16_t
#define u8 uint8_t
#define NAPT_ETH_HDR_LEN             sizeof(struct ethhdr)


static u16 luat_napt_icmp_id_alloc(void)
{
    u16 cnt = 0;

again:
    if (napt_curr_id++ == NAPT_ICMP_ID_RANGE_END)
    {
        napt_curr_id = NAPT_ICMP_ID_RANGE_START;
    }

    for (size_t i = 0; i < ICMP_MAP_SIZE; i++)
    {
        if (napt_curr_id == icmps[i].wnet_id)
        {
            if (++cnt > (NAPT_ICMP_ID_RANGE_END - NAPT_ICMP_ID_RANGE_START))
            {
                return 0;
            }

	       goto again;
        }
    }

    return napt_curr_id;
}

static uint8_t icmp_buff[1600];
int luat_napt_icmp_handle(napt_ctx_t* ctx) {
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    struct ip_hdr* ip_hdr = ctx->iphdr;
    struct icmp_echo_hdr *icmp_hdr = (struct icmp_echo_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);
    luat_netdrv_t* gw = luat_netdrv_get(luat_netdrv_gw_adapter_id);
    if (gw == NULL || gw->netif == NULL || ip_addr_isany(&gw->netif->ip_addr)) {
        LLOGD("网关指针不正常的状态!!!");
        return 0;
    }
    luat_netdrv_napt_icmp_t* it = NULL;
    if (ctx->is_wnet) {
        // 这是从外网到内网的PONG
        for (size_t i = 0; i < ICMP_MAP_SIZE; i++)
        {
            if (icmps[i].is_vaild == 0) {
                continue;
            }
            if (icmp_hdr->id != icmps[i].wnet_id) {
                continue;
            }
            if (ip_hdr->src.addr != icmps[i].wnet_ip) {
                continue;
            }
            // 找到映射关系了!!!
            // LLOGD("ICMP id wnet %d inet %u", icmp_hdr->id, icmps[i].inet_id);
            // 修改目标ID
            icmp_hdr->id = icmps[i].inet_id;
            // 重新计算icmp的checksum
            icmp_hdr->chksum = 0;
            icmp_hdr->chksum = alg_iphdr_chksum((u16 *)icmp_hdr, ntohs(ip_hdr->_len) - iphdr_len);

            // 修改目标地址,并重新计算ip的checksum
            ip_hdr->dest.addr = icmps[i].inet_ip;
            ip_hdr->_chksum = 0;
            ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

            // 如果是ETH包, 那还需要修改源MAC和目标MAC
            if (ctx->eth) {
                memcpy(ctx->eth->src.addr, ctx->net->netif->hwaddr, 6);
                memcpy(ctx->eth->dest.addr, icmps[i].inet_mac, 6);
            }
            luat_netdrv_t* dst = luat_netdrv_get(icmps[i].adapter_id);
            if (dst == NULL) {
                LLOGE("能找到ICMP映射关系, 但目标netdrv不存在, 这肯定是BUG啊!!");
                return 1;
            }
            if (dst->dataout) {
                if (ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP) {
                    LLOGD("输出到内网netdrv,无需额外添加eth头");
                    dst->dataout(dst->userdata, icmp_buff, ctx->len);
                }
                else if (!ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP) {
                    // 需要补全一个ETH头部
                    memcpy(icmp_buff, icmps[i].inet_mac, 6);
                    memcpy(icmp_buff + 6, dst->netif->hwaddr, 6);
                    memcpy(icmp_buff + 12, "\x08\x00", 2);
                    memcpy(icmp_buff + 14, ip_hdr, ctx->len);
                    dst->dataout(dst->userdata, icmp_buff, ctx->len + 14);
                    // LLOGD("输出到内网netdrv,已额外添加eth头");
                    // luat_netdrv_print_pkg("下行数据", icmp_buff, ctx->len + 14);
                }
            }
            else {
                LLOGE("能找到ICMP映射关系, 但目标netdrv不支持dataout!!");
            }
            // icmps[i].is_vaild = 0;
            return 1; // 全部修改完成
        }
        // LLOGD("没有找到ICMP映射关系, 不是非内网PING");
        return 0;
    }
    else {
        // 内网, 尝试对外网的请求吗?
        // LLOGD("ICMP request!!!");
        if (ip_hdr->dest.addr == ip_addr_get_ip4_u32(&ctx->net->netif->ip_addr)) {
            return 0; // 对网关的ICMP/PING请求, 交给LWIP处理
        }

        if (NULL == gw->dataout) {
            return 0;
        }
        // 首先, 有没有已有的映射呢?
        uint64_t tnow = luat_mcu_tick64_ms();
        for (size_t i = 0; i < ICMP_MAP_SIZE; i++)
        {
            if (icmps[i].is_vaild && (tnow - icmps[i].tm_ms) > ICMP_MAP_TIMEOUT) {
                icmps[i].is_vaild = 0;
                continue;
            }
            if (icmps[i].inet_ip != ip_hdr->src.addr || icmps[i].wnet_ip != ip_hdr->dest.addr) {
                continue;
            }
            if (icmps[i].inet_id == icmp_hdr->id) {
                it = &icmps[i];
                it->tm_ms = tnow;
                break;
            }
        }
        // 寻找一个空位
        if (it == NULL) {
            tnow = luat_mcu_tick64_ms();
            for (size_t i = 0; i < ICMP_MAP_SIZE; i++) {
                if (icmps[i].is_vaild && (tnow - icmps[i].tm_ms) < ICMP_MAP_TIMEOUT) {
                    continue;
                }
                it = &icmps[i];
                // 1. 保存信息
                icmps[i].adapter_id = ctx->net->id;
                icmps[i].inet_id = icmp_hdr->id;
                icmps[i].inet_ip = ip_hdr->src.addr;
                icmps[i].wnet_id = luat_napt_icmp_id_alloc();
                icmps[i].wnet_ip = ip_hdr->dest.addr;
                icmps[i].tm_ms = tnow;
                icmps[i].is_vaild = 1;
                LLOGD("新映射 wnet %d inet %d", icmps[i].wnet_id, icmps[i].inet_id);
                break;
            }
            if (it == NULL) {
                LLOGD("没有ICMP空位了");
                return 0;
            }
        }
        // 2. 修改信息
        ip_hdr->src.addr = ip_addr_get_ip4_u32(&gw->netif->ip_addr);
        icmp_hdr->id = it->wnet_id;
        // 3. 重新计算checksum
        icmp_hdr->chksum = 0;
        icmp_hdr->chksum = alg_iphdr_chksum((u16 *)icmp_hdr, ntohs(ip_hdr->_len) - iphdr_len);
        // 4. 计算IP包的checksum
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

        // 5. 如果是ETH包, 还得修正MAC地址
        if (ctx->eth) {
            memcpy(it->inet_mac, ctx->eth->src.addr, 6);
        }
        if (gw->netif->flags & NETIF_FLAG_ETHARP) {
            // TODO 网关设备也是ETHARP? 还不支持
            LLOGD("网关netdrv也是ETH, 当前不支持");
            return 0;
        }
        else {
            if (ctx->eth) {
                gw->dataout(gw->userdata, ip_hdr, ctx->len - 14);
            }
            else {
                gw->dataout(gw->userdata, ip_hdr, ctx->len);
            }
            return 1;
        }
    }
    return 0;
}
