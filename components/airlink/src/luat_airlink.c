
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_crypto.h"
#include "luat_netdrv.h"
#include "luat_netdrv_whale.h"
#include "lwip/prot/ethernet.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#ifdef LUAT_USE_PSRAM
#define AIRLINK_MEM_TYPE LUAT_HEAP_PSRAM
#else
#define AIRLINK_MEM_TYPE LUAT_HEAP_SRAM
#endif

luat_rtos_queue_t airlink_cmd_queue;
luat_rtos_queue_t airlink_ippkg_queue;

extern int luat_airlink_start_slave(void);
extern int luat_airlink_start_master(void);
luat_airlink_newdata_notify_cb g_airlink_newdata_notify_cb;
luat_airlink_spi_conf_t g_airlink_spi_conf;

int luat_airlink_init(void)
{
    // TODO Air8000自动新增设备?
    return 0;
}

int luat_airlink_start(int id)
{
    if (airlink_cmd_queue == NULL)
    {
        luat_rtos_queue_create(&airlink_cmd_queue, 2048, sizeof(airlink_queue_item_t));
    }
    if (airlink_ippkg_queue == NULL)
    {
        luat_rtos_queue_create(&airlink_ippkg_queue, 2048, sizeof(airlink_queue_item_t));
    }
    if (id == 0)
    {
        luat_airlink_start_slave();
    }
    else
    {
        luat_airlink_start_master();
    }
    return 0;
}

int luat_airlink_stop(int id)
{
    return 0;
}

void luat_airlink_print_buff(const char *tag, uint8_t *buff, size_t len)
{
    static char tmpbuff[1024] = {0};
    for (size_t i = 0; i < len; i += 8)
    {
        // sprintf(tmpbuff + i * 2, "%02X", buff[i]);
        // LLOGD("SPI TX[%d] 0x%02X", i, buff[i]);
        LLOGD("%s [%04X-%04X] %02X%02X%02X%02X%02X%02X%02X%02X", tag, i, i + 8,
              buff[i + 0], buff[i + 1], buff[i + 2], buff[i + 3],
              buff[i + 4], buff[i + 5], buff[i + 6], buff[i + 7]);
    }
    // LLOGD("SPI0 %s", tmpbuff);
}

int luat_airlink_queue_send(int tp, airlink_queue_item_t *item)
{
    int ret = -1;
    if (tp == LUAT_AIRLINK_QUEUE_CMD)
    {
        if (airlink_cmd_queue == NULL)
        {
            return -1;
        }
        else {
            ret = luat_rtos_queue_send(airlink_cmd_queue, item, 0, 0);
        }
    }
    if (tp == LUAT_AIRLINK_QUEUE_IPPKG)
    {
        if (airlink_ippkg_queue == NULL)
        {
            return -2;
        }
        else {
            ret = luat_rtos_queue_send(airlink_ippkg_queue, item, 0, 0);
        } 
    }
    if (ret == 0) {
        if (g_airlink_newdata_notify_cb) {
            g_airlink_newdata_notify_cb();
        }
        return 0;
    }
    return -2;
}

int luat_airlink_queue_get_cnt(int tp)
{
    size_t len = 0;
    int ret = -2;
    if (tp == LUAT_AIRLINK_QUEUE_CMD)
    {
        if (airlink_cmd_queue == NULL)
        {
            return -1;
        }
        ret = luat_rtos_queue_get_cnt(airlink_cmd_queue, &len);
    }
    if (tp == LUAT_AIRLINK_QUEUE_IPPKG)
    {
        if (airlink_ippkg_queue == NULL)
        {
            return -1;
        }
        ret = luat_rtos_queue_get_cnt(airlink_ippkg_queue, &len);
    }
    if (ret)
    {
        return ret;
    }
    return len;
}

int luat_airlink_cmd_recv(int tp, airlink_queue_item_t *item, size_t timeout)
{
    int ret = -2;
    if (tp == LUAT_AIRLINK_QUEUE_CMD)
    {
        if (airlink_cmd_queue == NULL)
        {
            return -1;
        }
        ret = luat_rtos_queue_recv(airlink_cmd_queue, item, 0, timeout);
    }
    if (tp == LUAT_AIRLINK_QUEUE_IPPKG)
    {
        if (airlink_ippkg_queue == NULL)
        {
            return -1;
        }
        ret = luat_rtos_queue_recv(airlink_ippkg_queue, item, 0, timeout);
    }
    return ret;
}

int luat_airlink_queue_send_ippkg(uint8_t adapter_id, uint8_t *data, size_t len)
{
    int ret = 0;
    if (len < 8)
    {
        LLOGE("数据包太小了, 抛弃掉");
        return -1;
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(adapter_id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        LLOGW("应该是BUG了, netdrv为空或者没有netif %d", adapter_id);
        return -2;
    }
    struct eth_hdr* eth = (struct eth_hdr*)data;
    if (netdrv->netif->flags & NETIF_FLAG_ETHARP) {
        if (eth->type == PP_HTONS(ETHTYPE_IP) || eth->type == PP_HTONS(ETHTYPE_ARP)) {
            // LLOGD("是ARP/IP包,继续转发");
        }
        else {
            // LLOGD("不是ARP/IP包,丢弃掉");
            return -3;
        }
    }
    // 检查内存状态, 如果内存不足, 就直接丢弃掉
    size_t total = 0;
    size_t used = 0;
    size_t max_used = 0;
    luat_meminfo_opt_sys(AIRLINK_MEM_TYPE, &total, &used, &max_used);
    if (total - used < 32*1024 && len > 512) {
        LLOGW("内存相对不足(%d), 丢弃掉大包(%d)", total - used, len);
        return -3;
    }
    else if (total - used < 8*1024) {
        // 内存严重不足, 抛弃所有的包
        LLOGW("内存严重不足(%d), 丢弃掉所有包(%d)", total - used, len);
        return -4;
    }

    airlink_queue_item_t item = {
        .len = len + 5,
        .cmd = luat_heap_opt_zalloc(AIRLINK_MEM_TYPE, len + 8),
    };
    if (item.cmd == NULL)
    {
        return -2;
    }
    memcpy(item.cmd->data + 1, data, len);
    item.cmd->cmd = 0x100;
    item.cmd->len = len + 1;
    item.cmd->data[0] = adapter_id;
    ret = luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_IPPKG, &item);
    if (ret != 0) {
        luat_heap_free(item.cmd);
        LLOGD("发送消息失败 长度 %d ret %d", len, ret);
        return -4;
    }
    return 0;
}

int luat_airlink_cmd_recv_simple(airlink_queue_item_t *cmd)
{
    // 看待发送队列里有没有数据, 有就发送
    int ret = luat_airlink_queue_get_cnt(LUAT_AIRLINK_QUEUE_CMD);
    // LLOGD("待发送CMD队列长度 %d", ret);
    airlink_queue_item_t item = {0};
    if (ret > 0)
    {
        ret = luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_CMD, &item, 0);
    }
    else
    {
        ret = luat_airlink_queue_get_cnt(LUAT_AIRLINK_QUEUE_IPPKG);
        // LLOGD("待发送IPPKG队列长度 %d", ret);
        if (ret > 0)
        {
            ret = luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_IPPKG, &item, 0);
            // LLOGD("从队列获取到IP数据包 %d %p", item.len, item.cmd);
            // luat_airlink_hexdump("从队列获取到IP数据包", item.cmd->data + 1, item.len - 1);
        }
    }
    memcpy(cmd, &item, sizeof(airlink_queue_item_t));
    return 0;
}

void luat_airlink_print_mac_pkg(uint8_t* buff, uint16_t len) {
    if (len < 24 || len > 1600) {
        LLOGW("非法的pkg长度 %d", len);
        return;
    }
    LLOGD("pkg len %d 前24个字节 " MACFMT MACFMT MACFMT MACFMT, len, MAC_ARG(buff), MAC_ARG(buff + 6), MAC_ARG(buff+12), MAC_ARG(buff + 18));
    
    struct eth_hdr* eth = (struct eth_hdr*)buff;
    struct ip_hdr* iphdr = (struct ip_hdr*)(buff + SIZEOF_ETH_HDR);
    struct etharp_hdr* arp = (struct etharp_hdr*)(buff + SIZEOF_ETH_HDR);
    // LLOGD("eth " MACFMT " -> " MACFMT " tp %02X", MAC_ARG(eth->src.addr), MAC_ARG(eth->dest.addr), (u16_t)lwip_htons(eth->type));
    switch (eth->type) {
        case PP_HTONS(ETHTYPE_IP):
            // LLOGD("  ipv%d %d len %d", (u16_t)IPH_V(iphdr), (u16_t)IPH_PROTO(iphdr),(u16_t)IPH_LEN(iphdr));
            break;
        case PP_HTONS(ETHTYPE_ARP):
            // LLOGD("  arp proto %d", arp->proto);
            break;
    }
}

void luat_airlink_hexdump(const char* tag, uint8_t* buff, uint16_t len) {
    if (len > 500) {
        len = 500;
    }
    uint8_t* tmp = luat_heap_opt_zalloc(AIRLINK_MEM_TYPE, len * 2 + 1);
    if (tmp == NULL) {
        return;
    }
    for (size_t i = 0; i < len; i++)
    {
        sprintf((char*)(tmp + i * 2), "%02X", buff[i]);
    }
    LLOGD("%s %s", tag, tmp);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, tmp);
}

static uint64_t next_cmd_id;

uint64_t luat_airlink_get_next_cmd_id() {
    // TODO 加锁?
    return next_cmd_id++;
}

luat_airlink_cmd_t* luat_airlink_cmd_new(uint16_t cmd_id, uint16_t data_len) {
    luat_airlink_cmd_t* cmd = luat_heap_opt_zalloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + data_len);
    if (cmd) {
        cmd->len = data_len;
        cmd->cmd = cmd_id;
    }
    return cmd;
}

void luat_airlink_cmd_free(luat_airlink_cmd_t* cmd) {
    if (cmd) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    }
}
