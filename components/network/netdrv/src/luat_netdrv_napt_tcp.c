#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_ch390h.h"
#include "luat_malloc.h"
#include "luat_netdrv_napt.h"
#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/etharp.h"
#include "lwip/tcp.h"
#include "lwip/prot/tcp.h"
#include "luat_mcu.h"
#include "lwip/ip_addr.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "netdrv.napt.tcp"
#include "luat_log.h"

#define TCP_MAP_SIZE (2048)
#define TCP_MAP_TIMEOUT (15*60*1000)

/* napt tcp port range: 7100-65535 */
#define NAPT_TCP_RANGE_START     0x1BBC
#define NAPT_TCP_RANGE_END       0x5AAA

extern int luat_netdrv_gw_adapter_id;
static uint16_t napt_curr_id = NAPT_TCP_RANGE_START;
static luat_netdrv_napt_tcpudp_t* tcps;

#define u32 uint32_t
#define u16 uint16_t
#define u8 uint8_t
#define NAPT_ETH_HDR_LEN             sizeof(struct ethhdr)

static u16 luat_napt_tcp_port_alloc(void)
{
    u16 cnt = 0;

again:
    if (napt_curr_id++ == NAPT_TCP_RANGE_END)
    {
        napt_curr_id = NAPT_TCP_RANGE_START;
    }

    for (size_t i = 0; i < TCP_MAP_SIZE; i++)
    {
        if (napt_curr_id == tcps[i].wnet_local_port)
        {
            if (++cnt > (NAPT_TCP_RANGE_END - NAPT_TCP_RANGE_START))
            {
                return 0;
            }

	       goto again;
        }
    }

    return napt_curr_id;
}

static void print_item(const char* tag, luat_netdrv_napt_tcpudp_t* it) {
    char buff[16] = {0};
    char buff2[16] = {0};
    ip_addr_t ip;
    
    ip_addr_set_ip4_u32(&ip, it->inet_ip);
    ipaddr_ntoa_r(&ip, buff, 16);

    ip_addr_set_ip4_u32(&ip, it->wnet_ip);
    ipaddr_ntoa_r(&ip, buff2, 16);

    LLOGD("%s (%5d) 内网 %s:%d <-> 外网 %s:%d", tag, it->wnet_local_port,
        buff, ntohs(it->inet_port),
        buff2, ntohs(it->wnet_port)
    );
}

static void update_tcp_stat_wnet(struct tcp_hdr *tcphdr, luat_netdrv_napt_tcpudp_t* t) {
      if ((TCPH_FLAGS(tcphdr) & (TCP_SYN|TCP_ACK)) == (TCP_SYN|TCP_ACK))
        t->synack = 1;
      if ((TCPH_FLAGS(tcphdr) & TCP_FIN))
        t->fin1 = 1;
      if (t->fin2 && (TCPH_FLAGS(tcphdr) & TCP_ACK))
        t->finack2 = 1; /* FIXME: Currently ignoring ACK seq... */
      if (TCPH_FLAGS(tcphdr) & TCP_RST)
        t->rst = 1;
    // LLOGD("TCP链路状态 synack %d fin1 %d finack2 %d rst %d", t->synack, t->fin1, t->finack2, t->rst);
}

static void update_tcp_stat_inet(struct tcp_hdr *tcphdr, luat_netdrv_napt_tcpudp_t* t) {
    if ((TCPH_FLAGS(tcphdr) & TCP_FIN))
        t->fin2 = 1;
    if (t->fin1 && (TCPH_FLAGS(tcphdr) & TCP_ACK))
        t->finack1 = 1; /* FIXME: Currently ignoring ACK seq... */
    if (TCPH_FLAGS(tcphdr) & TCP_RST)
        t->rst = 1;
    // LLOGD("TCP链路状态 synack %d fin1 %d finack2 %d rst %d", t->synack, t->fin1, t->finack2, t->rst);
}

static uint8_t tcp_buff[1600];
int luat_napt_tcp_handle(napt_ctx_t* ctx) {
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    struct ip_hdr* ip_hdr = ctx->iphdr;
    struct tcp_hdr *tcp_hdr = (struct tcp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);
    luat_netdrv_t* gw = luat_netdrv_get(luat_netdrv_gw_adapter_id);
    luat_netdrv_napt_tcpudp_t* it = NULL;
    luat_netdrv_napt_tcpudp_t* it_map = NULL;
    if (gw == NULL || gw->netif == NULL) {
        return 0;
    }
    if (tcps == NULL) {
        tcps = luat_heap_opt_zalloc(LUAT_HEAP_PSRAM, sizeof(luat_netdrv_napt_tcpudp_t) * TCP_MAP_SIZE);
    }
    uint64_t tnow = luat_mcu_tick64_ms();
    if (ctx->is_wnet) {
        // 这是从外网到内网的TCP包
        // LLOGD("wnet.search dst port %d", ntohs(tcp_hdr->dest));
        for (size_t i = 0; i < TCP_MAP_SIZE; i++)
        {
            it = &tcps[i];
            if (it->is_vaild == 0) {
                continue;
            }
            tnow = luat_mcu_tick64_ms();
            if (it->is_vaild && tnow > it->tm_ms &&  (tnow - it->tm_ms) > TCP_MAP_TIMEOUT) {
                LLOGD("映射关系超时了!!设置为无效 %lld %lld %lld", tnow, it->tm_ms, tnow - it->tm_ms);
                it->is_vaild = 0;
                continue;
            }
            // print_item("wnet.search item", it);
            // 校验远程IP与预期IP是否相同
            if (ip_hdr->src.addr != it->wnet_ip) {
                // LLOGD("IP地址不匹配,下一条");
                continue;
            }
            // 下行的目标端口, 与本地端口, 是否一直
            if (tcp_hdr->dest != tcps[i].wnet_local_port) {
                // LLOGD("port不匹配,下一条");
                continue;
            }
            // 找到映射关系了!!!
            // LLOGD("TCP port %u -> %d", ntohs(tcp_hdr->dest), ntohs(tcps[i].inet_port));
            tcps[i].tm_ms = tnow;
            // 修改目标端口
            tcp_hdr->dest = tcps[i].inet_port;

            // 修改目标地址到内网地址,并重新计算ip的checksu
            ip_hdr->dest.addr = tcps[i].inet_ip;
            ip_hdr->_chksum = 0;
            ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

            // 重新计算icmp的checksum
            // if (tcp_hdr->chksum) {
                tcp_hdr->chksum = 0;
                tcp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                               ip_hdr->dest.addr,
                                               IP_PROTO_TCP,
                                               (u16 *)tcp_hdr,
                                               ntohs(ip_hdr->_len) - iphdr_len);
            // }

            // 如果是ETH包, 那还需要修改源MAC和目标MAC
            if (ctx->eth) {
                memcpy(ctx->eth->src.addr, ctx->net->netif->hwaddr, 6);
                memcpy(ctx->eth->dest.addr, tcps[i].inet_mac, 6);
            }
            update_tcp_stat_wnet(tcp_hdr, &tcps[i]);
            luat_netdrv_t* dst = luat_netdrv_get(tcps[i].adapter_id);
            if (dst == NULL) {
                LLOGE("能找到TCP映射关系, 但目标netdrv不存在, 这肯定是BUG啊!!");
                return 1;
            }
            if (dst->dataout) {
                if (ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP) {
                    LLOGD("输出到内网netdrv,无需额外添加eth头");
                    dst->dataout(dst->userdata, tcp_buff, ctx->len);
                }
                else if (!ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP) {
                    // 需要补全一个ETH头部
                    memcpy(tcp_buff, tcps[i].inet_mac, 6);
                    memcpy(tcp_buff + 6, dst->netif->hwaddr, 6);
                    memcpy(tcp_buff + 12, "\x08\x00", 2);
                    memcpy(tcp_buff + 14, ip_hdr, ctx->len);
                    dst->dataout(dst->userdata, tcp_buff, ctx->len + 14);
                    // LLOGD("输出到内网netdrv,已额外添加eth头");
                    // luat_netdrv_print_pkg("下行数据", tcp_buff, ctx->len + 14);
                }
            }
            else {
                LLOGE("能找到TCP映射关系, 但目标netdrv不支持dataout!!");
            }
            return 1; // 全部修改完成
        }
        // LLOGD("没有找到TCP映射关系, 放行给LWIP处理");
        return 0;
    }
    else {
        // 内网, 尝试对外网的请求吗?
        if (ip_hdr->dest.addr == ip_addr_get_ip4_u32(&ctx->net->netif->ip_addr)) {
            return 0; // 对网关的TCP请求, 交给LWIP处理
        }
        // 第一轮循环, 是否有已知映射
        // LLOGD("inet.search src port %d -> %d", ntohs(tcp_hdr->src), ntohs(tcp_hdr->dest));
        for (size_t i = 0; i < TCP_MAP_SIZE; i++)
        {
            it = &tcps[i];
            if (it->is_vaild == 0) {
                continue;
            }
            tnow = luat_mcu_tick64_ms();
            if (tnow > it->tm_ms && (tnow - it->tm_ms) > TCP_MAP_TIMEOUT) {
                LLOGD("映射关系超时了!!设置为无效 %lld %lld %lld", tnow, it->tm_ms, tnow - it->tm_ms);
                it->is_vaild = 0;
                it->tm_ms = 0;
                continue;
            }

            // 判断TCP链路状态
            if ((((it->finack1 && it->finack2) || !it->synack) &&
                  tnow - it->tm_ms > IP_NAPT_TIMEOUT_MS_TCP_DISCON)) {
                LLOGD("映射的TCP链路已经断开%lldms, 超过 %ld ms, 设置为无效", tnow - it->tm_ms, IP_NAPT_TIMEOUT_MS_TCP_DISCON);
                it->is_vaild = 0;
                it->tm_ms = 0;
                continue;
            }
            
            // print_item("inet.search", it);
            // 几个要素都要相同 源IP/源端口/目标IP/目标端口, 如果是MAC包, 源MAC也要相同
            if (it->inet_ip != ip_hdr->src.addr || it->inet_port != tcp_hdr->src) {
                // LLOGD("源ip/port不匹配, 继续下一条");
                continue;
            }
            if (it->wnet_ip != ip_hdr->dest.addr || it->wnet_port != tcp_hdr->dest) {
                // LLOGD("目标ip/port不匹配, 继续下一条");
                continue;
            }
            if (ctx->eth && memcmp(ctx->eth->src.addr, it->inet_mac, 6)) {
                // LLOGD("源MAC不匹配, 继续下一条");
                continue;
            }
            // 都相同, 那就是同一个映射了, 可以复用
            it->tm_ms = tnow;
            it_map = it;
            break;
        }
        // 寻找一个空位
        if (it_map == NULL) {
            if ((TCPH_FLAGS(tcp_hdr) & (TCP_SYN|TCP_ACK)) == TCP_SYN && PP_NTOHS(tcp_hdr->src) >= 1024) {
                // 允许新增映射
            }
            else {
                LLOGI("非SYN包/源端口小于1024,且没有已知映射,不允许新增映射 %02X %d", TCPH_FLAGS(tcp_hdr), PP_NTOHS(tcp_hdr->src));
                // TODO 应该返回RST?
                return 0;
            }
            for (size_t i = 0; i < TCP_MAP_SIZE; i++) {
                it = &tcps[i];
                if (it->is_vaild) {
                    continue;
                }
                // 有空位了, 马上分配
                it_map = it;
                break;
            }
            if (it_map == NULL) {
                LLOGE("没有空闲的TCP映射了!!!!");
                return 0;
            }
            memset(it_map, 0, sizeof(luat_netdrv_napt_tcpudp_t));
            it->adapter_id = ctx->net->id;
            it->inet_port = tcp_hdr->src;
            it->wnet_port = tcp_hdr->dest;
            it->inet_ip = ip_hdr->src.addr;
            it->wnet_ip = ip_hdr->dest.addr;
            it->wnet_local_port = luat_napt_tcp_port_alloc();
            it->tm_ms = tnow;
            if (ctx->eth) {
                memcpy(it->inet_mac, ctx->eth->src.addr, 6);
            }
            it->is_vaild = 1;
            LLOGD("分配新的TCP映射 inet %d wnet %d", it->inet_port, it->wnet_local_port);
        }
        else {
            update_tcp_stat_inet(tcp_hdr, it_map);
        }
        // 2. 修改信息
        ip_hdr->src.addr = ip_addr_get_ip4_u32(&gw->netif->ip_addr);
        tcp_hdr->src = it_map->wnet_local_port;
        // 3. 与ICMP不同, 先计算IP的checksum
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);
        // 4. 计算IP包的checksum
        // if (tcp_hdr->chksum) {
            tcp_hdr->chksum = 0;
            tcp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                   ip_hdr->dest.addr,
                                                   IP_PROTO_TCP,
                                                   (u16 *)tcp_hdr,
                                                   ntohs(ip_hdr->_len) - iphdr_len);
        // }

        // 发送出去
        if (gw && gw->dataout && gw->netif) {
            // LLOGD("ICMP改写完成, 发送到GW");
            if (gw->netif->flags & NETIF_FLAG_ETHARP) {
                // TODO 网关设备也是ETHARP? 还不支持
                LLOGD("网关netdrv也是ETH, 当前不支持");
            }
            else {
                if (ctx->eth) {
                    gw->dataout(gw->userdata, ip_hdr, ctx->len - 14);
                }
                else {
                    gw->dataout(gw->userdata, ip_hdr, ctx->len);
                }
            }
        }
        else {
            LLOGD("TCP改写完成, 但GW不支持dataout回调?!!");
        }
        return 1;
    }
    return 0;
}
