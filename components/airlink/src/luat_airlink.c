
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_crypto.h"
#include "luat_netdrv.h"
#include "luat_netdrv_whale.h"
#include "luat_mcu.h"
#include "luat_hmeta.h"

#include "lwip/prot/ethernet.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#ifdef LUAT_USE_PSRAM
#define AIRLINK_MEM_TYPE LUAT_HEAP_PSRAM
#define AIRLINK_QUEUE_SIZE (4*1024)
#else
#define AIRLINK_MEM_TYPE LUAT_HEAP_SRAM
#define AIRLINK_QUEUE_SIZE (2*1024)
#endif

luat_rtos_queue_t airlink_cmd_queue;
luat_rtos_queue_t airlink_ippkg_queue;

extern int luat_airlink_start_slave(void);
extern int luat_airlink_start_master(void);
luat_airlink_newdata_notify_cb g_airlink_newdata_notify_cb;
luat_airlink_spi_conf_t g_airlink_spi_conf;
airlink_statistic_t g_airlink_statistic;
uint32_t g_airlink_spi_task_mode;
uint64_t g_airlink_last_cmd_timestamp;
uint32_t g_airlink_debug;
uint32_t g_airlink_pause;

int luat_airlink_init(void)
{
    // TODO Air8000自动新增设备?
    return 0;
}

int luat_airlink_start(int id)
{
    if (airlink_cmd_queue == NULL)
    {
        luat_rtos_queue_create(&airlink_cmd_queue, AIRLINK_QUEUE_SIZE, sizeof(airlink_queue_item_t));
    }
    if (airlink_ippkg_queue == NULL)
    {
        luat_rtos_queue_create(&airlink_ippkg_queue, AIRLINK_QUEUE_SIZE, sizeof(airlink_queue_item_t));
    }
    if (id == 0)
    {
        g_airlink_spi_task_mode = 0;
        luat_airlink_start_slave();
    }
    else
    {
        g_airlink_spi_task_mode = 1;
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
    g_airlink_statistic.tx_ip.total ++;
    g_airlink_statistic.tx_bytes.total += len;
    if (len < 8)
    {
        LLOGE("数据包太小了, 抛弃掉");
        g_airlink_statistic.tx_ip.drop ++;
        g_airlink_statistic.tx_bytes.drop += len;
        return -1;
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(adapter_id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        LLOGW("应该是BUG了, netdrv为空或者没有netif %d", adapter_id);
        g_airlink_statistic.tx_ip.drop ++;
        g_airlink_statistic.tx_bytes.drop += len;
        return -2;
    }
    struct eth_hdr* eth = (struct eth_hdr*)data;
    if (netdrv->netif->flags & NETIF_FLAG_ETHARP) {
        if (eth->type == PP_HTONS(ETHTYPE_IP) || eth->type == PP_HTONS(ETHTYPE_ARP)) {
            // LLOGD("是ARP/IP包,继续转发");
        }
        else {
            // LLOGD("不是ARP/IP包,丢弃掉");
            g_airlink_statistic.tx_ip.drop ++;
            g_airlink_statistic.tx_bytes.drop += len;
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
        g_airlink_statistic.tx_ip.drop ++;
        g_airlink_statistic.tx_bytes.drop += len;
        return -3;
    }
    else if (total - used < 8*1024) {
        // 内存严重不足, 抛弃所有的包
        LLOGW("内存严重不足(%d), 丢弃掉所有包(%d)", total - used, len);
        g_airlink_statistic.tx_ip.drop ++;
        g_airlink_statistic.tx_bytes.drop += len;
        return -4;
    }

    airlink_queue_item_t item = {
        .len = len + 5,
        .cmd = luat_heap_opt_zalloc(AIRLINK_MEM_TYPE, len + 8),
    };
    if (item.cmd == NULL)
    {
        g_airlink_statistic.tx_ip.drop ++;
        g_airlink_statistic.tx_bytes.drop += len;
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
        g_airlink_statistic.tx_ip.drop ++;
        g_airlink_statistic.tx_bytes.drop += len;
        return -4;
    }
    g_airlink_statistic.tx_ip.ok ++;
    g_airlink_statistic.tx_bytes.ok += len;
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


void luat_airlink_send2slave(luat_airlink_cmd_t* cmd) {
    airlink_queue_item_t item = {0};
    int ret = 0;
    item.len = cmd->len + sizeof(luat_airlink_cmd_t);
    item.cmd = luat_airlink_cmd_new(cmd->cmd, cmd->len);
    if (item.cmd == NULL) {
        LLOGD("luat_airlink_send2slave 内存不足, 丢弃掉");
        return;
    }
    memcpy(item.cmd->data, cmd->data, cmd->len);
    ret = luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    if (ret != 0) {
        LLOGD("luat_airlink_send2slave 发送消息失败 长度 %d ret %d", cmd->len, ret);
        luat_airlink_cmd_free(item.cmd);
        return;
    }
}

int luat_airlink_ready(void) {
    uint64_t tnow = luat_mcu_tick64_ms();
    uint64_t diff = tnow - g_airlink_last_cmd_timestamp;
    // LLOGD("tnow %lld", tnow);
    // LLOGD("gt %lld", g_airlink_last_cmd_timestamp);
    // LLOGD("diff %lld", diff);
    if (diff < 2000) {
        return 1;
    }
    return 0;
}

int luat_airlink_send_cmd_simple_nodata(uint16_t cmd_id) {
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(cmd_id, 8);
    uint64_t pkgid = luat_airlink_get_next_cmd_id();
    memcpy(cmd->data, &pkgid, 8);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    return 0;
}

int luat_airlink_send_cmd_simple(uint16_t cmd_id, uint8_t* data, uint16_t len) {
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + len);
    cmd->cmd = cmd_id;
    cmd->len = len;
    memcpy(cmd->data, data, len);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    return 0;
}

// 添加syspub所需的数据

int luat_airlink_syspub_addstring(const char* str, size_t len, uint8_t *dst, uint32_t limit) {
    if (len + 2 > limit) {
        return -1;
    }
    uint8_t tmp = LUA_TSTRING;
    memcpy(dst, &tmp, 1);
    tmp = (uint8_t)len;
    memcpy(dst + 1, &tmp, 1);
    memcpy(dst + 2, str, len);
    return len + 2;
}

int luat_airlink_syspub_addfloat32(const float val, uint8_t *dst, uint32_t limit) {
    if (4 + 2 > limit) {
        return -1;
    }
    uint8_t tmp = LUA_TNUMBER;
    memcpy(dst, &tmp, 1);
    tmp = (uint8_t)4;
    memcpy(dst + 1, &tmp, 1);
    memcpy(dst + 2, &val, 4);
    return 4 + 2;
}

int luat_airlink_syspub_addint32(const int32_t val, uint8_t *dst, uint32_t limit) {
    if (4 + 2 > limit) {
        return -1;
    }
    uint8_t tmp = LUA_TINTEGER;
    memcpy(dst, &tmp, 1);
    tmp = (uint8_t)4;
    memcpy(dst + 1, &tmp, 1);
    memcpy(dst + 2, &val, 4);
    return 4 + 2;
}

int luat_airlink_syspub_addnil(const uint8_t *dst, uint32_t limit) {
    if (2 > limit) {
        return -1;
    }
    uint8_t tmp = LUA_TBOOLEAN;
    memcpy(dst, &tmp, 1);
    tmp = (uint8_t)4;
    memcpy(dst + 1, &tmp, 1);
    return 2;
}
int luat_airlink_syspub_addbool(const uint8_t b, uint8_t *dst, uint32_t limit) {
    if (1 + 2 > limit) {
        return -1;
    }
    uint8_t tmp = LUA_TINTEGER;
    memcpy(dst, &tmp, 1);
    tmp = (uint8_t)4;
    memcpy(dst + 1, &tmp, 1);
    memcpy(dst + 2, &b, 1);
    return 1 + 2;
}

int luat_airlink_syspub_send(uint8_t* buff, size_t len) {
    // LLOGD("传输syspub命令数据 %d", len);
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x80, 8 + len);
    uint64_t pkgid = luat_airlink_get_next_cmd_id();
    memcpy(cmd->data, &pkgid, 8);
    memcpy(cmd->data + 8, buff, len);
    luat_airlink_send2slave(cmd);
    luat_airlink_cmd_free(cmd);
    return 0;
}


static luat_rtos_mutex_t reg_mutex;
static luat_airlink_result_reg_t regs[64];

int luat_airlink_result_reg(luat_airlink_result_reg_t* reg) {
    if (reg_mutex == NULL) {
        reg_mutex = luat_rtos_mutex_create(&reg_mutex);
    }
    luat_rtos_mutex_lock(reg_mutex, 1000);
    for (size_t i = 0; i < 64; i++)
    {
        if (regs[i].tm == 0) {
            memcpy(&regs[i], reg, sizeof(luat_airlink_result_reg_t));
            luat_rtos_mutex_unlock(reg_mutex);
            return 0;
        }
    }
    luat_rtos_mutex_unlock(reg_mutex);
    return -1;
}

int luat_airlink_cmd_exec_result(luat_airlink_cmd_t* cmd, void* userdata) {
    if (reg_mutex == NULL) {
        reg_mutex = luat_rtos_mutex_create(&reg_mutex);
    }
    if (cmd->len < 16) {
        LLOGE("对端设备返回的result长度不足16字节 %d", cmd->len); 
        return 0;
    }
    uint64_t id = 0;
    memcpy(&id, cmd->data + 8, 8);

    luat_rtos_mutex_lock(reg_mutex, 1000);
    for (size_t i = 0; i < 64; i++)
    {
        if (memcmp(&regs[i].id, &id, 8) == 0) {
            regs[i].exec(&regs[i], cmd);
            memset(&regs[i], 0, sizeof(luat_airlink_result_reg_t));
            luat_rtos_mutex_unlock(reg_mutex);
            return 0;
        }
    }
    luat_rtos_mutex_unlock(reg_mutex);
    return -1;
}

int luat_airlink_result_send(uint8_t* buff, size_t len) {
    // LLOGD("传输syspub命令数据 %d", len);
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x08, 8 + len);
    uint64_t pkgid = luat_airlink_get_next_cmd_id();
    memcpy(cmd->data, &pkgid, 8);
    memcpy(cmd->data + 8, buff, len);
    luat_airlink_send2slave(cmd);
    luat_airlink_cmd_free(cmd);
    return 0;
}

void luat_airlink_wait_ready(void) {
  // Air8000硬等最多200ms, 梁健要加的, 有问题找他
  char model[32] = {0};
  luat_hmeta_model_name(model);
  if (memcmp("Air8000\0", model, 8) == 0 || memcmp("Air8000W\0", model, 9) == 0 || memcmp("Air8000A\0", model, 9) == 0) {
    // LLOGD("等待Air8000s启动");
	  size_t count = 0;
	  #define AIRLINK_WAIT_MS (5)
    extern uint64_t g_airlink_last_cmd_timestamp;
	  while (g_airlink_last_cmd_timestamp == 0 && count < 200) {
		  luat_rtos_task_sleep(AIRLINK_WAIT_MS);
		  count += AIRLINK_WAIT_MS;
	  }
    if (g_airlink_last_cmd_timestamp > 0) {
      // 启动完成, 把wifi的GPIO24设置为高电平, 防止充电ic被关闭
      luat_gpio_mode(24 + 128, Luat_GPIO_OUTPUT, LUAT_GPIO_PULLUP, 1);
    }
    // LLOGD("等待Air8000s结束");
  }
}
