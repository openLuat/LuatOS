#ifndef LUAT_AIRLINK_H
#define LUAT_AIRLINK_H

#ifdef LUAT_USE_PSRAM
#define AIRLINK_MEM_TYPE LUAT_HEAP_PSRAM
#else
#define AIRLINK_MEM_TYPE LUAT_HEAP_SRAM
#endif

extern uint64_t g_airlink_last_cmd_timestamp;

int luat_airlink_ready(void);

typedef struct luat_airlink_cmd_ext
{
    uint64_t pkgid;
    uint8_t cdata[0];
}luat_airlink_cmd_ext_t;


typedef struct luat_airlink_cmd
{
    uint16_t cmd; // 命令, 从0x0001开始, 到0xfffe结束
    uint16_t len; // 数据长度,最高64k, 实际使用最高2k
    uint8_t data[0];
}luat_airlink_cmd_t;

typedef struct airlink_flags {
    uint8_t mem_is_high: 1;
    uint8_t queue_cmd: 1; // 用于指示命令包的队列是否还有数据
    uint8_t queue_ip: 1; // 用于ip包的队列是否还有数据
    uint8_t irq_ready: 1; // 是否切换到IRQ模式
    uint8_t irq_pin: 4;   // 中断管脚号, 这是传给SLAVE的, 从 GPIO12(GPIO140)开始算
    uint32_t revert: 24; // 保留位, 用于扩展
}airlink_flags_t;

typedef struct airlink_link_data {
    uint8_t magic[4];
    uint16_t len;
    uint16_t crc16;
    uint32_t pkgid; // 包序号,为了重传
    airlink_flags_t flags; // 包头标志,首先是为了支持流量控制
    uint8_t data[0];
}airlink_link_data_t;

typedef struct airlink_statistic_part {
    uint64_t total;
    uint64_t ok;
    uint64_t err;
    uint64_t drop;
}airlink_statistic_part_t;

typedef struct airlink_statistic {
    // 传输统计信息
    airlink_statistic_part_t rx_pkg;
    airlink_statistic_part_t tx_pkg;
    airlink_statistic_part_t wait_rdy;
    airlink_statistic_part_t rx_ip;
    airlink_statistic_part_t tx_ip;
    airlink_statistic_part_t rx_bytes;
    airlink_statistic_part_t tx_bytes;
    airlink_statistic_part_t rx_napt_ip;
    airlink_statistic_part_t rx_napt_bytes;

    // Task等待事件
    airlink_statistic_part_t event_timeout;
    airlink_statistic_part_t event_rdy_irq;
    airlink_statistic_part_t event_new_data;
}airlink_statistic_t;

int luat_airlink_init(void);
int luat_airlink_start(int id);
int luat_airlink_stop(int id);

void luat_airlink_data_pack(uint8_t* buff, size_t len, uint8_t* dst);
airlink_link_data_t* luat_airlink_data_unpack(uint8_t *buff, size_t len);

void luat_airlink_task_start(void);
void luat_airlink_print_buff(const char* tag, uint8_t* buff, size_t len);
void luat_airlink_on_data_recv(uint8_t *data, size_t len);

void airlink_wait_for_slave_ready(size_t timeout_ms);
void airlink_transfer_and_exec(uint8_t *txbuff, uint8_t *rxbuff);
void airlink_wait_and_prepare_data(uint8_t *txbuff);

typedef void (*luat_airlink_newdata_notify_cb)(void);

typedef int (*luat_airlink_cmd_exec)(luat_airlink_cmd_t* cmd, void* userdata);

typedef int (*luat_airlink_link_data_cb)(airlink_link_data_t* link);

typedef struct luat_airlink_cmd_reg
{
    uint16_t id;
    luat_airlink_cmd_exec exec;
}luat_airlink_cmd_reg_t;

enum {
    LUAT_AIRLINK_QUEUE_CMD = 1,
    LUAT_AIRLINK_QUEUE_IPPKG
};

typedef struct airlink_queue_item {
    size_t len;
    luat_airlink_cmd_t* cmd;
}airlink_queue_item_t;

int luat_airlink_queue_send(int tp, airlink_queue_item_t* item);

int luat_airlink_queue_get_cnt(int tp);

int luat_airlink_cmd_recv(int tp, airlink_queue_item_t* cmd, size_t timeout);

int luat_airlink_cmd_recv_simple(airlink_queue_item_t* cmd);

int luat_airlink_queue_send_ippkg(uint8_t adapter_id, uint8_t* data, size_t len);

void luat_airlink_send2slave(luat_airlink_cmd_t* cmd);
int luat_airlink_result_send(uint8_t* buff, size_t len);

void luat_airlink_print_mac_pkg(uint8_t* buff, uint16_t len);
void luat_airlink_hexdump(const char* tag, uint8_t* buff, uint16_t len);

typedef struct luat_airlink_dev_wifi_info {
    uint8_t sta_mac[6];
    uint8_t ap_mac[6];
    uint8_t bt_mac[6];
    uint8_t sta_state;
    uint8_t ap_state;
    uint8_t reverted[32]; // 预留的空位
    uint8_t version[4];
    uint8_t fw_type[2];
    uint8_t unique_id_len;
    uint8_t unique_id[24];

    // 2025.5.29 新增
    uint8_t sta_ap_bssid[6]; // AP的MAC地址(BSSID)
    int32_t sta_ap_rssi;     // AP信号强度
    uint8_t sta_ap_channel;  // AP所属的通道
}luat_airlink_dev_wifi_info_t;

typedef struct luat_airlink_dev_cat_info {
    uint8_t ipv4[4];
    uint8_t ipv6[16];
    uint8_t cat_state;
    uint8_t sim_state;
    uint8_t imei[16];
    uint8_t iccid[20];
    uint8_t imsi[16];
    uint8_t reverted[32]; // 预留的空位
    uint8_t version[4];
    uint8_t fw_type[4];
    uint8_t unique_id_len;
    uint8_t unique_id[24];
}luat_airlink_dev_wifi_cat_t;

typedef struct luat_airlink_dev_info
{
    uint8_t tp;
    union
    {
        luat_airlink_dev_wifi_info_t wifi;
        luat_airlink_dev_wifi_cat_t cat1;
    };
}luat_airlink_dev_info_t;


extern luat_airlink_newdata_notify_cb g_airlink_newdata_notify_cb;

typedef struct luat_airlink_spi_conf
{
    uint8_t spi_id;
    uint8_t master; // 主从
    uint8_t cs_pin; // cs引脚, 拉低开始传输, 拉高结束传输, 从机收到上升沿会立即拉高rdy,然后处理数据,处理完成后会拉低rdy
    uint8_t rdy_pin; // 从机就绪引脚, 低电平状态代表就绪,才能开始SPI传输
    uint8_t irq_pin; // 新数据通知脚, 从机还有新数据时, 会拉低该脚
    uint32_t irq_timeout;
}luat_airlink_spi_conf_t;

extern luat_airlink_spi_conf_t g_airlink_spi_conf;
extern luat_airlink_link_data_cb g_airlink_link_data_cb;

uint64_t luat_airlink_get_next_cmd_id(void);

luat_airlink_cmd_t* luat_airlink_cmd_new(uint16_t cmd, uint16_t data_len);

void luat_airlink_cmd_free(luat_airlink_cmd_t* cmd);
int luat_airlink_send_cmd_simple_nodata(uint16_t cmd_id);
int luat_airlink_send_cmd_simple(uint16_t cmd_id, uint8_t* data, uint16_t len);

enum {
    LUAT_AIRLINK_CONF_SPI_ID = 0x100,
    LUAT_AIRLINK_CONF_SPI_MODE,
    LUAT_AIRLINK_CONF_SPI_CS,
    LUAT_AIRLINK_CONF_SPI_RDY,
    LUAT_AIRLINK_CONF_SPI_IRQ,

    LUAT_AIRLINK_CONF_UART_ID,
    LUAT_AIRLINK_CONF_IRQ_TIMEOUT,
};

// GPIO 操作, 临时放这里
#include "luat_gpio.h"
int luat_airlink_drv_gpio_setup(luat_gpio_t* gpio);
int luat_airlink_drv_gpio_set(int pin, int level);
int luat_airlink_drv_gpio_open(luat_gpio_cfg_t* gpio);

// WLAN, 也就是wifi
#include "luat_wlan.h"
int luat_airlink_drv_wlan_init(luat_wlan_config_t *conf);

int luat_airlink_drv_wlan_mode(luat_wlan_config_t *conf);

int luat_airlink_drv_wlan_ready(void);

int luat_airlink_drv_wlan_connect(luat_wlan_conninfo_t* info);

int luat_airlink_drv_wlan_disconnect(void);

int luat_airlink_drv_wlan_scan(void);

int luat_airlink_drv_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit);

int luat_airlink_drv_wlan_set_station_ip(luat_wlan_station_info_t *info);

int luat_airlink_drv_wlan_smartconfig_start(int tp);

int luat_airlink_drv_wlan_smartconfig_stop(void);

// 数据类
int luat_airlink_drv_wlan_get_mac(int id, char* mac);
int luat_airlink_drv_wlan_set_mac(int id, const char* mac);

int luat_airlink_drv_wlan_get_ip(int type, char* data);

const char* luat_airlink_drv_wlan_get_hostname(int id);

int luat_airlink_drv_wlan_set_hostname(int id, const char* hostname);

// 设置和获取省电模式
int luat_airlink_drv_wlan_set_ps(int mode);

int luat_airlink_drv_wlan_get_ps(void);

int luat_airlink_drv_wlan_get_ap_bssid(char* buff);

int luat_airlink_drv_wlan_get_ap_rssi(void);

int luat_airlink_drv_wlan_get_ap_gateway(char* buff);


// AP类
int luat_airlink_drv_wlan_ap_start(luat_wlan_apinfo_t *apinfo);
int luat_airlink_drv_wlan_ap_stop(void);


// uart参数
#include "luat_uart.h"
int luat_airlink_drv_uart_setup(luat_uart_t* uart);
int luat_airlink_drv_uart_write(int uart_id, void* data, size_t length);
int luat_airlink_drv_uart_read(int uart_id, void* buffer, size_t length);
int luat_airlink_drv_uart_close(int uart_id);

extern uint32_t g_airlink_debug;

int luat_airlink_syspub_addstring(const char* str, size_t len, uint8_t *dst, uint32_t limit);
int luat_airlink_syspub_addfloat32(const float val, uint8_t *dst, uint32_t limit);
int luat_airlink_syspub_addint32(const int32_t val, uint8_t *dst, uint32_t limit);
int luat_airlink_syspub_addnil(const uint8_t *dst, uint32_t limit);
int luat_airlink_syspub_addbool(const uint8_t b, uint8_t *dst, uint32_t limit);

int luat_airlink_syspub_send(uint8_t* buff, size_t len);

struct luat_airlink_result_reg;
typedef void (*airlink_result_exec)(struct luat_airlink_result_reg *reg, luat_airlink_cmd_t* cmd);

typedef struct luat_airlink_result_reg
{
    uint64_t tm;
    uint64_t id;
    void* userdata;
    void* userdata2;
    airlink_result_exec exec;
    airlink_result_exec cleanup;
}luat_airlink_result_reg_t;

int luat_airlink_result_reg(luat_airlink_result_reg_t* reg);

typedef struct luat_airlink_irq_ctx
{
    int enable;
    int master_pin;
    int slave_pin;
    int slave_ready;
}luat_airlink_irq_ctx_t;

int luat_airlink_irqmode(luat_airlink_irq_ctx_t *ctx);

#ifdef TYPE_EC718M
#include "platform_def.h"
#endif

#ifndef __USER_FUNC_IN_RAM__
#define __USER_FUNC_IN_RAM__ 
#endif

#endif
