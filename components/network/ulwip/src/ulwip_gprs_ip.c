
#include "luat_base.h"
#include "luat_ulwip.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "ulwip"
#include "luat_log.h"

#include "lwip/ip.h"
#include "lwip/udp.h"
#include "lwip/tcp.h"
#include "luat_napt.h"

// 针对EC618/EC7xx平台的IP包输入回调
static uint8_t napt_tmpbuff[1600];

uint8_t napt_target_adapter;

err_t ulwip_ip_input_cb(struct pbuf *p, struct netif *inp) {
    //LLOGD("收到IP数据包(len=%d)", p->tot_len);
    u8_t ipVersion;
    if (napt_target_adapter == 0) {
        // 没有注册NAPT目标适配器(内网的), 不需要转发
        return 1;
    }
    ipVersion = IP_HDR_GET_VERSION(p->payload);
    if (ipVersion != 4) {
        // LLOGD("仅转发IPv4的包, 忽略%p %d", p, p->tot_len);
        return 1; // 当前仅考虑IPv4的转发
    }
    // 包太大的话也不处理
    if (p->tot_len > sizeof(napt_tmpbuff) - 14) {
        LLOGD("IP包太大了, 忽略%p %d", p, p->tot_len);
        return 1;
    }
    int offset = 14; // MAC头长度, 传入luat_napt_input需要是MAC包
    struct pbuf *q;
    for (q = p; q != NULL; q = q->next) {
        memcpy(napt_tmpbuff + offset, q->payload, q->len);
        offset += q->len;
    }
    struct ip_hdr *ip = (struct ip_hdr *)(napt_tmpbuff + 14);
    if (ip->_proto == IP_PROTO_TCP) {
        // TCP协议
        struct tcp_hdr *tcp = (struct tcp_hdr *)((char*)ip + sizeof(struct ip_hdr));
        u16_t tcpPort = tcp->dest;
        if(!luat_napt_port_is_used(tcpPort)) {
            // 目标端口没有被占用, 不需要转发
            // LLOGD("IP包的目标端口未使用, 忽略%p %d", p, p->tot_len);
            return 1;
        }
    }
    else if (ip->_proto == IP_PROTO_UDP) {
        // UDP协议
        struct udp_hdr *udp = (struct udp_hdr *)((char*)ip + sizeof(struct ip_hdr));
        u16_t udpPort = udp->dest;
        if(!luat_napt_port_is_used(udpPort)) {
            // 目标端口没有被占用, 不需要转发
            // LLOGD("IP包的目标端口未使用, 忽略%p %d", p, p->tot_len);
            return 1;
        }
    }
    // 如果已经注册了netif, 就转发了
    struct netif* tmp = ulwip_find_netif(NW_ADAPTER_INDEX_LWIP_GPRS);
    struct netif* gw = ulwip_find_netif(napt_target_adapter);
    if (gw && tmp == inp) {
        int rc = luat_napt_input(0, napt_tmpbuff, q->tot_len + 14, &gw->ip_addr);
        // LLOGD("luat_napt_input %d", rc);
        if (rc == 0) {
            char* ptr = luat_heap_malloc(p->tot_len + 14);
            if (ptr == NULL) {
                LLOGE("IP包改造完成,但系统内存不足,导致无法转发到lua层");
                return 4;
            }
            memcpy(napt_tmpbuff + 6, gw->hwaddr, 6);
            napt_tmpbuff[12] = 0x08;
            napt_tmpbuff[13] = 0x00;
            memcpy(ptr, napt_tmpbuff, p->tot_len + 14);
            rtos_msg_t msg = {0};
            msg.handler = l_ulwip_netif_output_cb;
            msg.arg1 = p->tot_len + 14;
            msg.arg2 = NW_ADAPTER_INDEX_LWIP_WIFI_AP;
            msg.ptr = ptr;
            luat_msgbus_put(&msg, 0);
            return ERR_OK;
        }
    }
    else {
        // LLOGD("转发目标不存在, 跳过NAPT流程 %p %d", p, p->tot_len);
    }
    return 2;
}
