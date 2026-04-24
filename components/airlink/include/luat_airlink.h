#ifndef LUAT_AIRLINK_H
#define LUAT_AIRLINK_H

#ifdef LUAT_USE_PSRAM
#define AIRLINK_MEM_TYPE LUAT_HEAP_PSRAM
#else
#define AIRLINK_MEM_TYPE LUAT_HEAP_SRAM
#endif


typedef void (*AIRLINK_DEV_INFO_UPDATE_CB)(void);

extern uint64_t g_airlink_last_cmd_timestamp;

int luat_airlink_ready(void);

typedef struct luat_airlink_cmd_ext
{
    uint64_t pkgid;
    uint8_t cdata[0];
}luat_airlink_cmd_ext_t;

enum {
    LUAT_AIRLINK_MODE_SPI_SLAVE = 0,
    LUAT_AIRLINK_MODE_SPI_MASTER = 1,
    LUAT_AIRLINK_MODE_UART = 2,
    LUAT_AIRLINK_MODE_LOOPBACK = 3, // PC simulator self-test loopback
    LUAT_AIRLINK_MODE_UNKNOW = -1
};


typedef struct luat_airlink_cmd
{
    uint16_t cmd; // 命令, 从0x0001开始, 到0xfffe结束
    uint16_t len; // 数据长度,最高64k, 实际使用最高2k
    uint8_t data[0];
}luat_airlink_cmd_t;

typedef struct airlink_flags {
    uint32_t mem_is_high: 1;
    uint32_t queue_cmd: 1; // 用于指示命令包的队列是否还有数据
    uint32_t queue_ip: 1; // 用于ip包的队列是否还有数据
    uint32_t irq_ready: 1; // 是否切换到IRQ模式
    uint32_t irq_pin: 4;   // 中断管脚号, 这是传给SLAVE的, 从 GPIO12(GPIO140)开始算
    uint32_t rpc_supported: 1; // 是否支持nanopb RPC指令 (cmd 0x30)
    uint32_t reserved: 23; // 保留位, 用于扩展
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

int airlink_wait_for_slave_reply(size_t timeout_ms);
void airlink_transfer_and_exec(uint8_t *txbuff, uint8_t *rxbuff);
void airlink_wait_and_prepare_data(uint8_t *txbuff);

typedef void (*luat_airlink_newdata_notify_cb)(void);

typedef int (*luat_airlink_cmd_exec)(luat_airlink_cmd_t* cmd, void* userdata);

typedef int (*luat_airlink_link_data_cb)(airlink_link_data_t* link);

int luat_airlink_mode_cb_register(uint8_t mode, luat_airlink_newdata_notify_cb newdata_cb, luat_airlink_link_data_cb link_data_cb, AIRLINK_DEV_INFO_UPDATE_CB dev_info_update_cb);
int luat_airlink_mode_cb_unregister(uint8_t mode);
luat_airlink_newdata_notify_cb luat_airlink_mode_newdata_cb_get(void);
luat_airlink_link_data_cb luat_airlink_mode_link_data_cb_get(void);
AIRLINK_DEV_INFO_UPDATE_CB luat_airlink_mode_dev_info_update_cb_get(void);


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

typedef struct luat_airlink_spi_conf
{
    uint8_t spi_id;
    uint8_t master; // 主从
    uint8_t cs_pin; // cs引脚, 拉低开始传输, 拉高结束传输, 从机收到上升沿会立即拉高rdy,然后处理数据,处理完成后会拉低rdy
    uint8_t rdy_pin; // 从机就绪引脚, 低电平状态代表就绪,才能开始SPI传输
    uint8_t irq_pin; // 新数据通知脚, 从机还有新数据时, 会拉低该脚
    uint32_t irq_timeout;
    uint8_t uart_id;
    uint32_t speed;
}luat_airlink_spi_conf_t;

extern luat_airlink_spi_conf_t g_airlink_spi_conf;

#include "luat_rtos.h"
extern luat_rtos_mutex_t g_airlink_pause_mutex;
void luat_airlink_pause_init(void);
void luat_airlink_set_pause(uint32_t val);

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
    LUAT_AIRLINK_CONF_SPI_SPEED,

    LUAT_AIRLINK_CONF_UART_ID,
    LUAT_AIRLINK_CONF_IRQ_TIMEOUT,
};

extern uint32_t g_airlink_debug;

void luat_airlink_ip2br_init(void);

typedef struct luat_airlink_irq_ctx
{
    int enable;
    int master_pin;
    int slave_pin;
    int slave_ready;
    int irq_mode;
}luat_airlink_irq_ctx_t;

int luat_airlink_irqmode(luat_airlink_irq_ctx_t *ctx);
int luat_airlink_wakeup_irqmode(luat_airlink_irq_ctx_t *ctx);

int luat_airlink_has_wifi(void);

uint32_t luat_airlink_sversion(void);

void luat_airlink_current_mode_set(int mode);
int luat_airlink_current_mode_get(void);

// 对端 flags 追踪: 传输层在收到每个链路包后调用 luat_airlink_peer_flags_update
// 更新对端的能力标志 (如 rpc_supported).
// 上层调用 luat_airlink_peer_rpc_supported() 来查询对端是否支持 nanopb RPC.
void luat_airlink_peer_flags_update(const airlink_flags_t* flags);
int luat_airlink_peer_rpc_supported(void);

#ifdef TYPE_EC718M
#include "platform_def.h"
#endif

#ifndef __AIRLINK_CODE_IN_RAM__
#ifdef __LUAT_C_CODE_IN_RAM__
#define __AIRLINK_CODE_IN_RAM__ __LUAT_C_CODE_IN_RAM__
#else
#define __AIRLINK_CODE_IN_RAM__
#endif
#endif

// =====================================================================
// 子功能头文件 (按需单独 include, 或通过本文件统一引入)
// =====================================================================

#include "luat_airlink_devinfo.h"
#include "luat_airlink_result.h"
#include "luat_airlink_transport.h"
#include "luat_airlink_rpc.h"

#include "luat_airlink_drv_gpio.h"
#include "luat_airlink_drv_uart.h"
#include "luat_airlink_drv_wlan.h"
#include "luat_airlink_drv_pm.h"
#include "luat_airlink_drv_mobile.h"

#endif /* LUAT_AIRLINK_H */
