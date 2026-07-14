/*
 * AirLink HSPI Master 传输任务 — 通过 XT804 寄存器协议通信
 *
 * SPI 配置: Mode 0, MSB first, 全双工
 * 地址空间协议: wr(0x10)/rd(0x02)/rd(0x03)/rd(0x10)
 *
 * 启动: airlink.start(airlink.MODE_HSPI_MASTER)
 * 之后标准 API (gpio/uart/wlan) 自动转发到 XT804 从机
 */

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_HSPI_MASTER

#include "luat_airlink.h"
#include "luat_airlink_hspi_master.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_spi.h"
#include "luat_mcu.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "airlink.hspi"
#include "luat_log.h"

// ==================== 平台 SPI 回调 ====================

#define HSPI_SPI_ID      1           // 使用 SPI1
#define HSPI_CS_PIN      8           // CS GPIO, 按实际板子修改
#define HSPI_SPEED       4000000     // 起始 4MHz

static uint8_t g_spi_inited = 0;

int xt804_hspi_spi_xfer(const uint8_t *tx, uint8_t *rx, uint16_t len) {
    if (!g_spi_inited) {
        luat_spi_t cfg = {
            .id = HSPI_SPI_ID,
            .CPHA = 0, .CPOL = 0,
            .dataw = 8, .bit_dict = 1,
            .master = 1, .mode = 1,
            .bandrate = HSPI_SPEED,
            .cs = 255,              // 软件 CS，手动 GPIO 控制
        };
        if (luat_spi_setup(&cfg) != 0) return -1;
        luat_gpio_cfg_t cs_cfg = {0};
        luat_gpio_set_default_cfg(&cs_cfg);
        cs_cfg.pin = HSPI_CS_PIN;
        cs_cfg.mode = Luat_GPIO_OUTPUT;
        cs_cfg.pull = Luat_GPIO_PULLUP;
        cs_cfg.output_level = 1;    // CS 默认高（非选中）
        luat_gpio_open(&cs_cfg);
        g_spi_inited = 1;
    }
    // CS 低 → 传输 → CS 高（确保 XT804 检测到 CS 上升沿）
    luat_gpio_set(HSPI_CS_PIN, 0);
    int ret = luat_spi_transfer(HSPI_SPI_ID, (const char*)tx, len, (char*)rx, len);
    luat_gpio_set(HSPI_CS_PIN, 1);
    return ret;
}

uint32_t xt804_hspi_get_tick_ms(void) {
    return (uint32_t)(luat_mcu_tick64_ms() & 0xFFFFFFFF);
}

// ==================== 传输任务 ====================

static luat_rtos_task_handle g_task_hdl;
static volatile uint8_t g_running = 0;

/* 重建完整 luat_airlink_cmd_t 并分发 */
static void dispatch_cmd(uint16_t cmd_id, uint8_t *data, uint16_t len) {
    if (!data || len == 0) return;
    uint16_t total = sizeof(luat_airlink_cmd_t) + len;
    uint8_t *buf = luat_heap_malloc(total);
    if (!buf) return;
    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)buf;
    cmd->cmd = cmd_id;
    cmd->len = len;
    memcpy(cmd->data, data, len);
    luat_airlink_on_data_recv(buf, total);
    luat_heap_free(buf);
}

static void hspi_transport_task(void *param) {
    LLOGI("HSPI master transport started");
    // 设置当前模式，使命令能路由到 HSPI 队列
    luat_airlink_current_mode_set(LUAT_AIRLINK_MODE_HSPI_MASTER);
    // 设置 peer 标志，使 RPC NOTIFY 事件能被注册和接收
    airlink_flags_t peer_flags = {.rpc_supported = 1, .frag_supported = 1};
    luat_airlink_peer_flags_update(&peer_flags);
    g_running = 1;

    while (g_running) {
        /* 1. 读所有可用响应（最多 10 次，确保 NOTIFY 不被遗漏） */
        for (int i = 0; i < 10; i++) {
            uint8_t resp[1600] = {0};
            uint16_t resp_len = sizeof(resp);
            uint16_t cmd_id = 0;
            int ret = xt804_hspi_read_response(resp, &resp_len, &cmd_id, 30);
            if (ret == 0 && resp_len > 0) { dispatch_cmd(cmd_id, resp, resp_len); }
        }

        /* 2. 从全局命令队列取命令 (CMD优先, 再查IPPKG, 与SPI Master/Slave行为一致) */
        airlink_queue_item_t item = {0};
        int has_cmd = luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_CMD, &item, 0);
        if (has_cmd != 0) {
            has_cmd = luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_IPPKG, &item, 50);
        }

        if (has_cmd == 0 && item.cmd) {
            LLOGI("hspi TX cmd=0x%04X len=%d", item.cmd->cmd, item.cmd->len);
            xt804_hspi_send_cmd(item.cmd->cmd, item.cmd->data, item.cmd->len,
                                NULL, NULL, 500);
            luat_airlink_cmd_free(item.cmd);
        }
    }

    LLOGI("HSPI master transport stopped");
    g_running = 0;
    luat_rtos_task_delete(NULL);
}

// ==================== AirLink 启动/停止接口 ====================

int luat_airlink_start_hspi_master(void) {
    if (g_running) {
        LLOGE("HSPI master already running");
        return -1;
    }
    g_running = 1;
    int ret = luat_rtos_task_create(&g_task_hdl, 8 * 1024, 50,
                                    "hspi", hspi_transport_task, NULL, 0);
    if (ret != 0) {
        LLOGE("HSPI master task create failed %d", ret);
        g_running = 0;
    }
    return ret;
}

int luat_airlink_stop_hspi_master(void) {
    g_running = 0;
    return 0;
}

#endif /* LUAT_USE_AIRLINK_HSPI_MASTER */
