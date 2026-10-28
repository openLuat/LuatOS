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
extern uint32_t g_airlink_pause;
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
 * HSPI 版 FOTA exec — 命令入队走标准 CMD 队列, 由传输任务统一发送 (与 UART 对齐)
 * 在独立 task 内执行, 不阻塞传输任务收发 → FOTA 期间 airlink.ready() 保持 true
 * 流程: fota_init(0x04) → fota_write(0x05)×N → fota_done(0x06) → fota_end(0x07) → reset(0x03)
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

    // 1. fota_init(0x04) — 通知从机擦除 OTA 区 (376KB, 约需4~5秒)
    luat_airlink_send_cmd_simple(0x04, NULL, 0);
    LLOGI("HSPI FOTA init(0x04) queued, wait 5s for slave erase OTA...");
    luat_rtos_task_sleep(5000);

    // 2. fota_write chunks (1KB/帧, 走标准命令帧, 由传输任务串行发送)
    uint8_t *chunk = luat_heap_malloc(1050);
    size_t sent = 0;
    while (g_airlink_fota->state) {
        int ret = (int)luat_fs_fread(chunk, 1, 1024, fd);
        if (ret < 1) break;
        luat_airlink_send_cmd_simple(0x05, chunk, ret);
        sent += ret;
        if (sent == 8 * 1024) {
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
    luat_airlink_send_cmd_simple(0x06, NULL, 0);
    luat_rtos_task_sleep(500);

    // 4. fota_end
    luat_airlink_send_cmd_simple(0x07, NULL, 0);
    luat_rtos_task_sleep(500);

    // 5. 复位指令 (CMD 0x03) → 从机重启加载新固件
    LLOGI("HSPI FOTA done, sending reset...");
    luat_airlink_send_cmd_simple_nodata(0x03);
    luat_rtos_task_sleep(3000);

    g_airlink_fota->state = 0;
    LLOGI("HSPI FOTA done");
}

// ==================== HSPI INT 引脚（XT804 PB_07 → 1601 GPIO12）====================
// 由 airlink.config(airlink.CONF_SPI_IRQ, <pin>) 配置, 未配置则不初始化 INT 中断
// (传输任务本身有 20ms 轮询兜底, 无 INT 引脚时退化为轮询模式)

static TaskHandle_t g_hspi_task_handle = NULL;  // 传输任务句柄 (ISR→定向通知)
static int hspi_int_irq_cb(int pin, void* args) {
    if (g_hspi_task_handle != NULL) {
        BaseType_t xHigherPriorityTaskWoken = pdFALSE;
        vTaskNotifyGiveFromISR(g_hspi_task_handle, &xHigherPriorityTaskWoken);
        portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
    }
    return 0;
}

// PIT 1ms 周期定时器: 兜底唤醒传输任务轮询 (不依赖 FreeRTOS tick)。
// 根因: configTICK_RATE_HZ=50 时 pdMS_TO_TICKS(1)=(1*50)/1000=0 退化成忙等;
//       soc_timer(PIT) 由 luat_rtos_timer_start 驱动, 1ms 精度与 tick 无关。
static luat_rtos_timer_t g_hspi_pit_timer = NULL;
static void hspi_pit_timer_cb(void *param) {
    (void)param;
    // timer_start_ms 走任务上下文回调 (timer_task 分发), 故用 xTaskNotifyGive 而非 FromISR
    if (g_hspi_task_handle != NULL) {
        xTaskNotifyGive(g_hspi_task_handle);
    }
}

static void hspi_int_gpio_init(void) {
    if (g_airlink_spi_conf.irq_pin == 0) {
        LLOGW("HSPI INT pin not configured, skip INT GPIO init (polling mode)");
        return;
    }
    luat_gpio_cfg_t cfg = {0};
    luat_gpio_set_default_cfg(&cfg);
    cfg.pin = g_airlink_spi_conf.irq_pin;
    cfg.mode = Luat_GPIO_IRQ;
    cfg.pull = Luat_GPIO_PULLUP;
    cfg.irq_type = Luat_GPIO_FALLING;
    cfg.irq_cb = hspi_int_irq_cb;
    int ret = luat_gpio_open(&cfg);
    if (ret == 0) {
        LLOGI("HSPI INT GPIO%d configured, falling edge", g_airlink_spi_conf.irq_pin);
    } else {
        LLOGE("HSPI INT GPIO%d open failed %d", g_airlink_spi_conf.irq_pin, ret);
    }
}

// ==================== 平台 SPI 回调 ====================

// 默认参数: Lua 未配置 airlink.config(CONF_SPI_ID/CS/SPEED) 时使用
#define HSPI_DEFAULT_SPI_ID   1
#define HSPI_DEFAULT_CS_PIN   8
#define HSPI_DEFAULT_SPEED    4000000

static uint8_t g_spi_inited = 0;
static int      s_spi_id = HSPI_DEFAULT_SPI_ID;
static int      s_cs_pin = HSPI_DEFAULT_CS_PIN;
static uint32_t s_speed  = HSPI_DEFAULT_SPEED;

/* 轮询直读 SPI (SDK luat_spi_ccm42xx.c), 跳过 DMA+信号量路径。
 * 根因: luat_spi_transfer 对大帧(len>=speed>>20≈9B@10MHz)走 spi_master_transfer
 *       (256B×N DMA 分包 + 每包中断/缓存失效 + 末尾信号量往返), 每帧实测 2ms,
 *       而 1604B@10MHz 理论仅 1.28ms → 每帧 ~0.7ms 纯开销。轮询路径无此开销。 */
extern void luat_spi_fast_transfer(int spi_id, const void* send_buf, void* recv_buf, size_t recv_length);

int xt804_hspi_spi_xfer(const uint8_t *tx, uint8_t *rx, uint16_t len) {
    if (!g_spi_inited) {
        // SPI id/CS/速度由 airlink.config() 配置 (g_airlink_spi_conf), 未配置时用默认值
        // 判据: cs_pin 非 0 视为已配置 (1601 可用 CS 引脚为 4/8/37, 不会配 0)
        s_spi_id = (g_airlink_spi_conf.cs_pin != 0) ? g_airlink_spi_conf.spi_id    : HSPI_DEFAULT_SPI_ID;
        s_cs_pin = (g_airlink_spi_conf.cs_pin != 0) ? g_airlink_spi_conf.cs_pin    : HSPI_DEFAULT_CS_PIN;
        s_speed  = g_airlink_spi_conf.speed ? g_airlink_spi_conf.speed : HSPI_DEFAULT_SPEED;
        luat_spi_t cfg = {
            .id = s_spi_id,
            .CPHA = 0, .CPOL = 0,
            .dataw = 8, .bit_dict = 1,
            .master = 1, .mode = 1,
            .bandrate = s_speed,
            .cs = 255,              // 软件 CS，手动 GPIO 控制
        };
        if (luat_spi_setup(&cfg) != 0) return -1;
        luat_gpio_cfg_t cs_cfg = {0};
        luat_gpio_set_default_cfg(&cs_cfg);
        cs_cfg.pin = s_cs_pin;
        cs_cfg.mode = Luat_GPIO_OUTPUT;
        cs_cfg.pull = Luat_GPIO_PULLUP;
        cs_cfg.output_level = 1;    // CS 默认高（非选中）
        luat_gpio_open(&cs_cfg);
        g_spi_inited = 1;
    }
    // CS 低 → 传输 → CS 高（确保 XT804 检测到 CS 上升沿）
    luat_gpio_set(s_cs_pin, 0);
    luat_spi_fast_transfer(s_spi_id, tx, rx, len);   // 轮询直读, 无 DMA/信号量开销
    luat_gpio_set(s_cs_pin, 1);
    return len;
}

// ==================== 传输任务 ====================

#define HSPI_OFFLINE_CNT    30000   // 30000×~1ms=30s 无数据才判离线（PIT 1ms 兜底周期；原 1500×20ms）
#define HSPI_ERR_THRESHOLD  10      // 连续 10 次校验错误触发复位
#define HSPI_HEARTBEAT_MS   2000    // 空闲心跳: 每 2s 主动发 devinfo(0x10), 激活从机+保 ready() (与 UART 对齐)

static luat_rtos_task_handle g_task_hdl;
static volatile uint8_t g_running = 0;
static int g_peer_online = 1;       // 从机在线状态，由 transport 自己维护
static int g_idle_cnt = 0;          // 连续无数据计数
static int g_hspi_err_cnt = 0;      // 连续校验错误计数
static uint32_t g_rd_batch = 0;     // Phase 1 读帧计数，每 N 帧冲一次 ACK


/* 独立 FOTA 任务 — 与 UART 对齐: 不在传输任务内执行, 避免阻塞收发 */
static void hspi_fota_task(void *param) {
    (void)param;
    while (g_running) {
        extern luat_airlink_fota_t *g_airlink_fota;
        if (g_airlink_fota && g_airlink_fota->state) {
            hspi_fota_exec();
        }
        luat_rtos_task_sleep(100);
    }
    luat_rtos_task_delete(NULL);
}

static void luat_airlink_hspi_fota_task_create(void) {
    static luat_rtos_task_handle fota_task = NULL;
    if (fota_task != NULL) return;
    int ret = luat_rtos_task_create(&fota_task, 4 * 1024, 51, "hspi_fota", hspi_fota_task, NULL, 0);
    if (ret) {
        LLOGW("创建hspi_fota_task ret:%d", ret);
    }
}


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
        g_airlink_statistic.event_new_data.total++;
        dispatch_cmd(cmd_id, resp, resp_len);
        return 1;
    }
    return 0;
}

// 读数据时周期性冲发积压的 ACK，避免 ACK 憋到数据流停顿才发导致 RTT 过高
// 8→1: 下载 373帧/s 下 8 帧≈21ms，ACK 被白白攒批 ~21ms，直接推高 RTT；改每帧 flush 砍掉 ~18ms
#define HSPI_ACK_FLUSH_BATCH 1

static void hspi_flush_ip_pkg(void) {
    airlink_queue_item_t item = {0};
    while (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_IPPKG, &item, 0) == 0 && item.cmd) {
        int ret = xt804_hspi_send_cmd(item.cmd->cmd, item.cmd->data, item.cmd->len, NULL, NULL, 0);
        if (ret == 0) {
            g_airlink_statistic.tx_ip.total++;
            g_airlink_statistic.tx_ip.ok++;
            g_airlink_statistic.tx_bytes.total += item.cmd->len;
            g_airlink_statistic.tx_bytes.ok += item.cmd->len;
        } else {
            g_airlink_statistic.tx_ip.total++;
            g_airlink_statistic.tx_ip.err++;
            LLOGW("HSPI IP flush failed %d", ret);
        }
        luat_airlink_cmd_free(item.cmd);
        item = (airlink_queue_item_t){0};
    }
}

// 声明：主机侧使能 XT804 HSPI INT 脚
extern int xt804_hspi_enable_host_int(void);

static void hspi_transport_task(void *param) {
    LLOGI("HSPI master transport started");
    // 先做一次 SPI 初始化 + 使能 XT804 INT 脚
    // （SPI 在 xt804_hspi_spi_xfer 第一次调用时懒初始化）
    xt804_hspi_enable_host_int();

    // 配置 INT 下降沿中断接收 XT804 信号（引脚由 airlink.config(CONF_SPI_IRQ) 指定）
    hspi_int_gpio_init();

    // 设置当前模式，使命令能路由到 HSPI 队列
    luat_airlink_current_mode_set(LUAT_AIRLINK_MODE_HSPI_MASTER);
    // 对端能力(rpc/frag)改由收到从机 devinfo(cmd 0x10) 后经 luat_airlink_peer_caps_update 更新,
    // 不再在此硬编码

    // 记录任务句柄供 ISR 定向通知
    g_hspi_task_handle = xTaskGetCurrentTaskHandle();
    g_running = 1;

    // 创建 1ms 周期 PIT 定时器: 兜底唤醒传输任务轮询 (见 hspi_pit_timer_cb)
    if (luat_rtos_timer_create(&g_hspi_pit_timer) == 0) {
        luat_rtos_timer_start(g_hspi_pit_timer, 1, 1, hspi_pit_timer_cb, NULL);
    } else {
        LLOGW("HSPI PIT timer create failed, fallback to blocking wait");
    }

    // 创建独立 FOTA 任务 (FOTA 期间不阻塞本传输任务收发)
    luat_airlink_hspi_fota_task_create();

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

    // 空闲心跳: 从机(6208)重启后 g_hspi_transport_active 复位为0, 其自主心跳会被 send2slave 丢弃,
    // 必须主机先发一帧才能重新激活从机 → 每 2s 主动发一次 devinfo(0x10), 与 UART uart_transfer_task 对齐
    uint64_t last_hb_ms = 0;

    while (g_running) {
        // 暂停检查
        if (g_airlink_pause) {
            if (g_airlink_pause_mutex) {
                luat_rtos_mutex_lock(g_airlink_pause_mutex, LUAT_WAIT_FOREVER);
                luat_rtos_mutex_unlock(g_airlink_pause_mutex);
            } else {
                while (g_airlink_pause) {
                    luat_rtos_task_sleep(1000);
                }
            }
        }

        // 空闲心跳发送 (每 2s): 激活从机 + 刷新 ready() 时间戳
        if (luat_mcu_tick64_ms() - last_hb_ms >= HSPI_HEARTBEAT_MS) {
            last_hb_ms = luat_mcu_tick64_ms();
            luat_airlink_send_cmd_simple_nodata(0x10);
        }

        // ===== Phase 1: 读数据 (中断驱动) =====
        if (g_peer_online) {
            if (hspi_handle_interrupt()) {
                g_idle_cnt = 0;
                // 每 N 帧冲一次积压 ACK
                if (++g_rd_batch >= HSPI_ACK_FLUSH_BATCH) {
                    g_rd_batch = 0;
                    hspi_flush_ip_pkg();
                }
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
                        continue;  // 回 Phase 1 读从机回复
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
                            continue;  // 回 Phase 1 读从机回复
                        }
                        luat_airlink_cmd_free(_item.cmd);
                    }
                }
            }
            if (!g_peer_online) {
                // 离线: 靠 PIT 1ms / INT notify 唤醒后继续嗅探 (彻底不依赖 tick)
                ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
                continue;
            }
            // online了, 继续执行 Phase 2
        }

        // ===== Phase 2: 等命令 (INT 中断 + PIT 1ms 定时器, 均 notify 唤醒) =====
        int has_cmd = -1;
        airlink_queue_item_t item = {0};

        // 先非阻塞查 CMD 队列
        if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_CMD, &item, 0) == 0) {
            has_cmd = 0;
        } else {
            // 无限等待: INT 中断(从机有数据→边沿→ISR notify) 或 PIT 1ms 定时器(兜底轮询) 任一唤醒。
            // portMAX_DELAY 不进延时列表, 唤醒完全靠 notify, 与 configTICK_RATE_HZ 无关
            // (tick=50 下 pdMS_TO_TICKS(1)=0 会退化成忙等饿死 lwip, 故不再用 tick 超时)。
            ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

            // 唤醒后优先读数据: INT 边沿意味着从机有数据, 也可能只是 PIT 兜底轮询
            if (hspi_handle_interrupt()) {
                g_idle_cnt = 0;
                continue;  // 读到数据, 回 Phase 1 连续读
            }

            // 没数据 → 查命令队列
            if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_CMD, &item, 0) == 0) {
                has_cmd = 0;
            } else if (luat_airlink_cmd_recv(LUAT_AIRLINK_QUEUE_IPPKG, &item, 0) == 0) {
                has_cmd = 0;
            }
            // has_cmd 仍 -1: 无数据无命令 → 走下方离线计数
        }
        // Phase 2 未取到命令 → 无数据无命令 (从机自主上行已在唤醒后读过), 累计离线计数
        if (has_cmd != 0) {
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
    // 清理 PIT 兜底定时器
    if (g_hspi_pit_timer) {
        luat_rtos_timer_stop(g_hspi_pit_timer);
        luat_rtos_timer_delete(g_hspi_pit_timer);
        g_hspi_pit_timer = NULL;
    }
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
    // 优先级 50（低于 lwip 110）：transport 任务唤醒后快速读帧即再次阻塞(notify 唤醒)，
    // 不长时间占 CPU；TO() 宏修复后队列检查非阻塞，读帧不被 lwip 抢占拖慢(实测 935KB/s)。
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
