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

extern airlink_statistic_t g_airlink_statistic;
#include "luat_gpio.h"
/* FreeRTOS — 用于 vTaskNotifyGiveFromISR / ulTaskNotifyTake / xTaskGetCurrentTaskHandle */
#include "FreeRTOS.h"
#include "task.h"

#define LUAT_LOG_TAG "airlink.hspi"
#include "luat_log.h"

// ==================== HSPI FOTA ====================
#include "luat_airlink_fota.h"
#include "luat_fs.h"

/**
 * HSPI 版 FOTA exec — 用 xt804_hspi_send_cmd 代替 airlink_transfer_and_exec
 * 流程: fota_init(0x04) → fota_write(0x05)×N → fota_done(0x06) → fota_end(0x07)
 */
static void hspi_fota_exec(void) {
    extern luat_airlink_fota_t *g_airlink_fota;
    FILE *fd = luat_fs_fopen(g_airlink_fota->path, "rb");
    if (fd == NULL) {
        LLOGE("HSPI FOTA: open file fail %s", g_airlink_fota->path);
        g_airlink_fota->state = 0;
        return;
    }
    g_airlink_fota->total_size = luat_fs_fsize(g_airlink_fota->path);
    LLOGI("HSPI FOTA start, size=%ld", g_airlink_fota->total_size);

    // 1. fota_init — 从机同步擦除 OTA 区 (376KB, ~4.2秒)
    xt804_hspi_send_cmd(0x04, NULL, 0, NULL, NULL, 0);
    LLOGI("HSPI FOTA init sent, waiting for erase (~4.2s)...");
    luat_rtos_task_sleep(5000);

    // 2. fota_write chunks
    uint8_t *chunk = luat_heap_malloc(1050);
    size_t sent = 0;
    while (g_airlink_fota->state) {
        int ret = (int)luat_fs_fread(chunk, 1, 1024, fd);
        if (ret < 1) break;
        if (xt804_hspi_send_cmd(0x05, chunk, ret, NULL, NULL, 0) != 0) {
            LLOGE("HSPI FOTA: send fail at %zu", sent);
            break;
        }
        sent += ret;
        if (sent == 8 * 1024) {
            LLOGI("HSPI FOTA 8KB, waiting for flash erase...");
            luat_rtos_task_sleep(8000);
        } else if (sent == 16 * 1024) {
            luat_rtos_task_sleep(3000);
        } else {
            luat_rtos_task_sleep(10);
        }
    }
    luat_heap_free(chunk);
    luat_fs_fclose(fd);
    LLOGI("HSPI FOTA sent %zu bytes", sent);

    // 3. fota_done
    xt804_hspi_send_cmd(0x06, NULL, 0, NULL, NULL, 0);
    luat_rtos_task_sleep(500);

    // 4. fota_end
    xt804_hspi_send_cmd(0x07, NULL, 0, NULL, NULL, 0);
    luat_rtos_task_sleep(500);

    // 5. 发送复位指令 (CMD 0x03) → 从机重启加载新固件
    LLOGI("HSPI FOTA done, sending reset...");
    xt804_hspi_send_cmd(0x03, NULL, 0, NULL, NULL, 0);
    luat_rtos_task_sleep(3000);

    g_airlink_fota->state = 0;
    LLOGI("HSPI FOTA done");
}

// ==================== HSPI INT 引脚（XT804 PB_07 → 1601 GPIO12）====================

#define HSPI_INT_PIN      12

static TaskHandle_t g_hspi_task_handle = NULL;  // 传输任务句柄 (ISR→定向通知)

static int hspi_int_irq_cb(int pin, void* args) {
    if (g_hspi_task_handle != NULL) {
        BaseType_t xHigherPriorityTaskWoken = pdFALSE;
        vTaskNotifyGiveFromISR(g_hspi_task_handle, &xHigherPriorityTaskWoken);
        portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
    }
    return 0;
}

static void hspi_int_gpio_init(void) {
    luat_gpio_cfg_t cfg = {0};
    luat_gpio_set_default_cfg(&cfg);
    cfg.pin = HSPI_INT_PIN;
    cfg.mode = Luat_GPIO_IRQ;
    cfg.pull = Luat_GPIO_PULLUP;
    cfg.irq_type = Luat_GPIO_FALLING;
    cfg.irq_cb = hspi_int_irq_cb;
    int ret = luat_gpio_open(&cfg);
    if (ret == 0) {
        LLOGI("HSPI INT GPIO%d configured, falling edge", HSPI_INT_PIN);
    } else {
        LLOGE("HSPI INT GPIO%d open failed %d", HSPI_INT_PIN, ret);
    }
}

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

#define HSPI_CYCLE_MS       20      // 等命令超时：空载时休眠时长
#define HSPI_OFFLINE_CNT    1500    // 1500×~20ms=30s 无数据才判离线（原60仅1.2s，易误判）
#define HSPI_ERR_THRESHOLD  10      // 连续 10 次校验错误触发复位

static luat_rtos_task_handle g_task_hdl;
static volatile uint8_t g_running = 0;
static int g_peer_online = 1;       // 从机在线状态，由 transport 自己维护
static int g_idle_cnt = 0;          // 连续无数据计数
static int g_hspi_err_cnt = 0;      // 连续校验错误计数


/* 重建完整 luat_airlink_cmd_t 并分发 */
static void dispatch_cmd(uint16_t cmd_id, uint8_t *data, uint16_t len) {
    if (!data || len == 0) return;
    g_airlink_statistic.tx_pkg.total++;
    g_airlink_statistic.tx_pkg.ok++;
    uint16_t total = sizeof(luat_airlink_cmd_t) + len;
    uint8_t *buf = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, total);
    if (!buf) return;
    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)buf;
    cmd->cmd = cmd_id;
    cmd->len = len;
    memcpy(cmd->data, data, len);
    luat_airlink_on_data_recv(buf, total);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, buf);
}

/**
 * Phase 1 核心: 中断驱动读数据并分发
 * 返回 1=读到数据, 0=无数据
 */
static int hspi_handle_interrupt(void) {
    uint8_t resp[1600];
    uint16_t resp_len = sizeof(resp);
    uint16_t cmd_id = 0;

    int ret = xt804_hspi_read_data_intr(resp, &resp_len, &cmd_id);
    if (ret == 0 && resp_len > 0) {
        //LLOGI("HSPI intr got cmd=0x%04X len=%d", cmd_id, resp_len);
        g_airlink_statistic.event_new_data.total++;
        dispatch_cmd(cmd_id, resp, resp_len);
        return 1;
    }
    return 0;
}

// 声明：主机侧使能 XT804 HSPI INT 脚
extern int xt804_hspi_enable_host_int(void);

static void hspi_transport_task(void *param) {
    LLOGI("HSPI master transport started");
    // 先做一次 SPI 初始化 + 使能 XT804 INT 脚
    // （SPI 在 xt804_hspi_spi_xfer 第一次调用时懒初始化）
    xt804_hspi_enable_host_int();

    // 配置 GPIO12 下降沿中断，接收 XT804 的 INT 信号
    hspi_int_gpio_init();

    // 设置当前模式，使命令能路由到 HSPI 队列
    luat_airlink_current_mode_set(LUAT_AIRLINK_MODE_HSPI_MASTER);
    // 设置 peer 标志，使 RPC NOTIFY 事件能被注册和接收
    airlink_flags_t peer_flags = {.rpc_supported = 1, .frag_supported = 0};
    luat_airlink_peer_flags_update(&peer_flags);

    // ★ 记录任务句柄供 ISR 定向通知
    g_hspi_task_handle = xTaskGetCurrentTaskHandle();
    g_running = 1;

    // 等待XT804 HSPI就绪后再发devinfo请求（解决重启后HSPI状态不确定的问题）
    int _xt804_ready = 0;
    for (int _i = 0; _i < 50; _i++) {
        int _dr = 0, _cr = 0;
        if (xt804_hspi_check_status(&_dr, &_cr) == 0) {
            _xt804_ready = 1;
            break;
        }
        luat_rtos_task_sleep(10);
    }
    if (_xt804_ready) {
        // 发送 peer reboot 通知，让 103 同步恢复到 WiFi 初始化状态
        // 这必须在任何其他命令之前发送，确保 103 收到后先重置状态再处理后续命令
        luat_airlink_send_cmd_simple_nodata(0x22);
        int _devinfo_req_ret = luat_airlink_send_cmd_simple_nodata(0x10);
        LLOGI("HSPI XT804 ready, devinfo request sent ret=%d", _devinfo_req_ret);
    } else {
        LLOGW("HSPI XT804 not ready after 500ms, skip devinfo request");
    }

    while (g_running) {
        // ===== Phase 1: 读数据 (中断驱动) =====
        if (g_peer_online) {
            if (hspi_handle_interrupt()) {
                g_idle_cnt = 0;
                continue;
            }
        } else {
            // 离线: 每轮都嗅探, 读到数据就连续读完
            int _got = 0;
            while (hspi_handle_interrupt()) {
                _got++;
            }
            if (_got) {
                LLOGI("HSPI back online (drained %d frames)", _got);
                g_peer_online = 1;
                g_idle_cnt = 0;
                // 数据已排空, 回到循环头, 走在线路径处理命令
                continue;
            }
            // 离线时也检查命令队列, 尝试发送
            {
                airlink_queue_item_t _item = {0};
                if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_CMD, &_item, 0) == 0 && _item.cmd) {
                    LLOGI("HSPI offline but has cmd 0x%04X, trying send", _item.cmd->cmd);
                    int _ret = xt804_hspi_send_cmd(_item.cmd->cmd, _item.cmd->data, _item.cmd->len, NULL, NULL, 0);
                    if (_ret == 0) {
                        LLOGI("HSPI peer back online (send success)");
                        g_peer_online = 1;
                        g_idle_cnt = 0;
                        luat_airlink_cmd_free(_item.cmd);
                        continue;  // ★ 回 Phase 1 读从机回复
                    }
                    luat_airlink_cmd_free(_item.cmd);
                } else {
                    if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_IPPKG, &_item, 0) == 0 && _item.cmd) {
                        LLOGI("HSPI offline but has IP, trying send");
                        int _ret = xt804_hspi_send_cmd(_item.cmd->cmd, _item.cmd->data, _item.cmd->len, NULL, NULL, 0);
                        if (_ret == 0) {
                            LLOGI("HSPI peer back online (IP send success)");
                            g_peer_online = 1;
                            g_idle_cnt = 0;
                            luat_airlink_cmd_free(_item.cmd);
                            continue;  // ★ 回 Phase 1 读从机回复
                        }
                        luat_airlink_cmd_free(_item.cmd);
                    }
                }
            }
            if (!g_peer_online) {
                ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(50));
                continue;
            }
            // online了, 继续执行 Phase 2
        }

        // ===== FOTA 检查: 如果 g_airlink_fota->state 已设置, 执行 HSPI FOTA =====
        {
            extern luat_airlink_fota_t *g_airlink_fota;
            if (g_airlink_fota && g_airlink_fota->state) {
                LLOGI("HSPI FOTA detected, starting...");
                g_peer_online = 1;
                g_idle_cnt = 0;
                hspi_fota_exec();
                continue;
            }
        }

        // ===== Phase 2: 等命令 (定向通知 + 超时) =====
        int has_cmd = -1;
        airlink_queue_item_t item = {0};

        // 先非阻塞查 CMD 队列
        if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_CMD, &item, 0) == 0) {
            has_cmd = 0;
        } else {
            // 进入循环前先非阻塞消费可能积压的通知
            if (ulTaskNotifyTake(pdTRUE, 0) > 0) {
                if (hspi_handle_interrupt())
                    g_idle_cnt = 0;
                continue;
            }
            // 循环等通知 (INT 来了立即跳出)
            uint32_t elapsed = 0;
            while (elapsed < HSPI_CYCLE_MS) {
                uint32_t notified = ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(5));
                if (notified > 0) {
                    // INT 来了 — 在读数据前先看看有没有命令要发
                    // 但要记得: INT 可能意味着新数据, 需要先读后写
                    if (hspi_handle_interrupt())
                        g_idle_cnt = 0;
                    // 读完数据后继续检查命令, 不 break
                    // 但重新检查 CMD 队列
                    if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_CMD, &item, 0) == 0) {
                        has_cmd = 0;
                        break;
                    }
                    // 没有命令, 继续等周期结束
                    continue;
                }
                elapsed += 5;
                // 超时: 检查 IPPKG 队列
                if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_IPPKG, &item, 0) == 0) {
                    has_cmd = 0;
                    break;
                }
            }
        }
        // Phase 2 未取到命令 → 先非阻塞检查从机是否有自主上行数据
        // 从机(103)可能自主上报 WiFi 状态等通知, 此时不应判离线
        if (has_cmd != 0) {
            if (hspi_handle_interrupt()) {
                g_idle_cnt = 0;
                continue;  // 有线数据, 回到 Phase 1 处理
            }
            g_airlink_statistic.event_timeout.total++;
            if (g_peer_online && ++g_idle_cnt >= HSPI_OFFLINE_CNT) {
                g_peer_online = 0;
                g_idle_cnt = 0;
                LLOGW("HSPI peer offline (%d cycles no data)", HSPI_OFFLINE_CNT);
            }
            continue;
        }

        // ===== Phase 3: 发送命令 =====
        if (item.cmd) {
            luat_airlink_cmd_t *cmd = item.cmd;
            //LLOGI("hspi TX cmd=0x%04X len=%d", cmd->cmd, cmd->len);
            int ret = xt804_hspi_send_cmd(cmd->cmd, cmd->data, cmd->len, NULL, NULL, 0);
            if (ret == 0) {
                g_peer_online = 1;
                g_idle_cnt = 0;
            } else {
                LLOGW("HSPI send cmd 0x%04X failed %d", cmd->cmd, ret);
                // (不设 online, 不重置 idle — 让离线检测自然判离线)
            }
            // 发完 CMD 后非阻塞看 IPPKG，防止 IP 包被饿死
            item = (airlink_queue_item_t){0};
            if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_IPPKG, &item, 0) == 0 && item.cmd) {
                //LLOGI("[DHCP_DEBUG] HSPI TX IP pkg: cmd=0x%04X len=%d", item.cmd->cmd, item.cmd->len);
                int ip_ret = xt804_hspi_send_cmd(item.cmd->cmd, item.cmd->data, item.cmd->len, NULL, NULL, 0);
                if (ip_ret == 0) {
                    g_airlink_statistic.tx_ip.total++;
                    g_airlink_statistic.tx_ip.ok++;
                    g_airlink_statistic.tx_bytes.total += item.cmd->len;
                    g_airlink_statistic.tx_bytes.ok += item.cmd->len;
                } else {
                    g_airlink_statistic.tx_ip.total++;
                    g_airlink_statistic.tx_ip.err++;
                    LLOGW("HSPI IP send failed %d", ip_ret);
                }
                luat_airlink_cmd_free(item.cmd);  // fire-and-forget, TCP 层重传
            }
            luat_airlink_cmd_free(cmd);
        }

        // 离线检测
        if (g_peer_online && ++g_idle_cnt >= HSPI_OFFLINE_CNT) {
            g_peer_online = 0;
            g_idle_cnt = 0;
            LLOGW("HSPI peer offline (%d cycles no data)", HSPI_OFFLINE_CNT);
        }
    }

    LLOGI("HSPI master transport stopped");
    g_running = 0;
    g_hspi_task_handle = NULL;
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
