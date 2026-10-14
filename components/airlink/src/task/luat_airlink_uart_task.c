#include <stdbool.h>
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_airlink_devinfo.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_airlink_fota.h"

#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#define AIRLINK_UART_RAW_FRAME_MAX (4096)
#define UART_BUFF_SIZE (4096)             // s_txbuff / s_rxbuff 大小 (临时缓冲)
#define UNPACK_BUFF_SIZE (8 * 1024)       // rxbuf 环形缓冲区大小
#define UART_ESC_FRAME_MAX   (UART_BUFF_SIZE)  // 单帧转义后最大长度, 与 s_txbuff/s_rxbuff 一致
// 解析器失步看门狗: 收到数据却超过该时长未解出任何帧, 则强制清空 rxoffset 重同步
#define AIRLINK_UART_RX_RESYNC_MS (500)

// 帧间间隙: 从机背靠背发帧会让主机 RX FIFO 溢出丢字节。睡眠 = 帧传输耗时 + 期望间隙(自适应)。0=关闭。
#define AIRLINK_UART_TX_FRAME_GAP_MS (1)   // 期望线上最小间隙(ms)

#ifdef TYPE_EC718M
#include "platform_def.h"
#endif

#ifndef __USER_FUNC_IN_RAM__
#define __USER_FUNC_IN_RAM__
#endif



#ifdef LUAT_CONF_AIRLINK_MODE_WAIT
#define AIRLINK_MODE_WAIT_TIMEOUT 100
#else
#define AIRLINK_MODE_WAIT_TIMEOUT 500
#endif

extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_pause;
extern luat_airlink_irq_ctx_t g_airlink_irq_ctx;
// UART RX overrun 标志: FIFO 溢出丢字节(帧界被破坏)时在驱动 ISR 内置位。
// ccm42xx 由 luat_uart_ccm42xx.c 强定义并置位; 其它设备平台(如 ec7xx/780EHM)没有该驱动,
// 此处用弱默认 0 兜底, 否则全平台共享代码链接报 undefined reference(2026-09-30 780EHM 编译实测)。
// 弱默认=0 时 overrun 立即重同步不生效, 自动退回下方 AIRLINK_UART_RX_RESYNC_MS 看门狗。
// PC 模拟器不编译 luat_uart_ccm42xx.c, 且 MSVC 不支持 __attribute__((weak)), 改为普通全局变量。
#if defined(LUAT_BSP_PC)
volatile uint32_t g_uart_rx_overrun = 0;
#else
volatile uint32_t g_uart_rx_overrun __attribute__((weak)) = 0;
#endif

static uint8_t basic_info[sizeof(luat_airlink_dev_info_t) + 64];
typedef struct
{
    luat_rtos_task_handle transfer_task;
    luat_rtos_task_handle receive_task;
    luat_rtos_queue_t tx_evt_queue;
    luat_rtos_queue_t rx_evt_queue;
    uint32_t rxoffset;
    uint8_t *s_txbuff;
    uint8_t *s_rxbuff;
    uint8_t *rxbuf;
    uint8_t uart_running;
}luat_airlink_uart_ctrl_t;

static luat_airlink_uart_ctrl_t g_airlink_uart = {0};

static void luat_airlink_uart_transfer_task(void);
static void luat_airlink_uart_receive_task(void);
static void luat_airlink_uart_fota_task_create(void);

static int luat_airlink_uart_ensure_buffers(void)
{
    uint8_t *new_txbuff = NULL;
    uint8_t *new_rxbuff = NULL;
    uint8_t *new_rxbuf = NULL;

    if (g_airlink_uart.s_txbuff == NULL) {
        new_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UART_BUFF_SIZE);
        if (new_txbuff == NULL) {
            goto alloc_failed;
        }
        g_airlink_uart.s_txbuff = new_txbuff;
    }
    if (g_airlink_uart.s_rxbuff == NULL) {
        new_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UART_BUFF_SIZE);
        if (new_rxbuff == NULL) {
            goto alloc_failed;
        }
        g_airlink_uart.s_rxbuff = new_rxbuff;
    }
    if (g_airlink_uart.rxbuf == NULL) {
        new_rxbuf = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UNPACK_BUFF_SIZE);
        if (new_rxbuf == NULL) {
            goto alloc_failed;
        }
        g_airlink_uart.rxbuf = new_rxbuf;
    }

    return 0;

alloc_failed:
    if (new_txbuff != NULL) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, new_txbuff);
        g_airlink_uart.s_txbuff = NULL;
    }
    if (new_rxbuff != NULL) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, new_rxbuff);
        g_airlink_uart.s_rxbuff = NULL;
    }
    if (new_rxbuf != NULL) {
        luat_heap_opt_free(AIRLINK_MEM_TYPE, new_rxbuf);
        g_airlink_uart.rxbuf = NULL;
    }
    LLOGE("uart buffer alloc failed tx=%u rx=%u unpack=%u", (unsigned)UART_BUFF_SIZE, (unsigned)UART_BUFF_SIZE, (unsigned)UNPACK_BUFF_SIZE);
    return -1;
}

static int airlink_uart_pack_frame_or_log(uint8_t *dst, size_t dst_size, uint8_t *src, size_t src_len, size_t *packed_len, const char *tag)
{
    size_t frame_len = src_len + sizeof(airlink_link_data_t);
    if (frame_len > dst_size) {
        LLOGE("%s frame too large src=%u raw=%u limit=%u — dropping (frag may not cover this path)",
              tag, (unsigned)src_len, (unsigned)frame_len, (unsigned)dst_size);
        g_airlink_statistic.tx_pkg.drop++;
        return -1;
    }
    luat_airlink_data_pack(src, src_len, dst);
    *packed_len = frame_len;
    return 0;
}

__USER_FUNC_IN_RAM__ static void on_newdata_notify(void)
{
    luat_event_t evt = {.id = 3};
    luat_rtos_queue_send(g_airlink_uart.tx_evt_queue, &evt, sizeof(evt), 0);
}

static void uart_cb(int uart_id, uint32_t data_len) {
    luat_event_t evt = {.id = 2};
    luat_rtos_queue_send(g_airlink_uart.rx_evt_queue, &evt, sizeof(evt), 0);
}

static void uart_gpio_setup(void)
{
    int ret = 0;
    if (g_airlink_spi_conf.uart_id == 0) {
        g_airlink_spi_conf.uart_id = 1;
    }
    ret = luat_uart_ctrl(g_airlink_spi_conf.uart_id, LUAT_UART_SET_RECV_CALLBACK, uart_cb);
    if (ret) {
        LLOGW("luat_uart_ctrl ret:%d", ret);
    }
}

__USER_FUNC_IN_RAM__ static void record_statistic(luat_event_t event)
{
    switch (event.id)
    {
    case 0:
        g_airlink_statistic.event_timeout.total++;
        break;
    case 2:
        g_airlink_statistic.event_rdy_irq.total++;
        break;
    case 3:
        g_airlink_statistic.event_new_data.total++;
        break;
    default:
        break;
    }
}


__USER_FUNC_IN_RAM__ static int on_link_data_notify(airlink_link_data_t* link) {
    // memset(&link->flags, 0, sizeof(uint32_t));
    if (g_airlink_irq_ctx.enable) {
        link->flags.irq_ready = 1;
        link->flags.irq_pin = g_airlink_irq_ctx.slave_pin - 140;
    }
    return 0;
}

static bool unpack_data(uint8_t* buff, size_t len)
{
    // LLOGD("unpack_data: src len = %d", len);
    if (len < 2) {
        LLOGE("unpack_data: data too short");
        return false; // 数据太短, 无法解析
    }
    // 存储最终数据到s_rxbuff
    uint8_t* unpacked_data = g_airlink_uart.s_rxbuff;
    size_t unpacked_len = 0;
    for (size_t i = 0; i < len; i++) {
        if (buff[i] == 0x7D) {
            // 转义字符, 下一个字节是转义码
            if (i + 1 < len) {
                if (unpacked_len >= UART_ESC_FRAME_MAX) {
                    LLOGW("unpack: overflow raw=%u limit=%u esc_len=%u — frame truncated",
                          (unsigned)(unpacked_len + 1), (unsigned)UART_ESC_FRAME_MAX, (unsigned)len);
                    return false;
                }
                if (buff[i + 1] == 0x02) {
                    unpacked_data[unpacked_len++] = 0x7E; // 转义为0x7E
                } else if (buff[i + 1] == 0x01) {
                    unpacked_data[unpacked_len++] = 0x7D; // 转义为0x7D
                }
                i++; // 跳过下一个字节
            }
        } else {
            if (unpacked_len >= UART_ESC_FRAME_MAX) {
                LLOGW("unpack: overflow raw=%u limit=%u esc_len=%u — frame truncated",
                      (unsigned)(unpacked_len + 1), (unsigned)UART_ESC_FRAME_MAX, (unsigned)len);
                return false;
            }
            unpacked_data[unpacked_len++] = buff[i]; // 普通数据直接复制
        }
    }
    if (unpacked_len < sizeof(airlink_link_data_t)) {
        // LLOGE("unpack_data: unpacked data too short, len %d", unpacked_len);
        return false; // 解包后的数据太短, 无法解析
    }
    airlink_link_data_t *link = NULL;
    link = luat_airlink_data_unpack(unpacked_data, unpacked_len);
    if (link == NULL) {
        g_airlink_statistic.tx_pkg.err++;
        g_airlink_statistic.tx_pkg.total++;
        return false; // 解析失败
    }
    // 解析成功了
    g_airlink_statistic.tx_pkg.ok++;
    g_airlink_statistic.tx_pkg.total++;
    // 那就走uart为主模式了
    if (luat_airlink_current_mode_get() == LUAT_AIRLINK_MODE_UNKNOW) {
        // LLOGD("luat_airlink_current_mode_get is UNKNOW, set to UART");
        luat_airlink_current_mode_set(LUAT_AIRLINK_MODE_UART);
    }
    // 更新最后通讯时间戳，用于airlink.ready()判断
    g_airlink_last_cmd_timestamp = luat_mcu_tick64_ms();
    luat_airlink_on_data_recv(link->data, link->len);
    return true;
}


void on_airlink_uart_data_in(uint8_t* buff, size_t len)
{
    // int ret = 0;
    size_t offset = 0;
    size_t end_offset = 0;
    // 首先, 输入的数据是否为0, 也可能是太长的数据
    if (len == 0) {
        return; // 不需要处理
    }
    // [修复] 解析器失步看门狗: 字节持续流入却长时间解不出任何帧(残帧吞帧/丢字节致帧尾被吞),
    // 会让 rxbuf 永久卡在"等帧尾"状态(实测: ok 冻结、rxoffset 卡 173、40KB 流入 0 帧解出)。
    // 帧有 CRC16 保护, 丢弃一个残帧无害(TCP 会重传); 不加干预则会拖到 link timeout(5.5s) 整链路断。
    // 阈值 500ms: 2Mbps 下满帧(≤8KB 转义)最多 ~40ms 到齐, 500ms 为 12x 裕量, 不会误伤正常分片帧。
    // [修复] overrun 信号驱动重同步: UART RX FIFO 溢出丢字节(帧界被破坏)是即时的确定性信号,
    // 立即清空 rxbuf 重新找 0x7E 帧头, 比 500ms 看门狗更快恢复(overrun→重同步 ~0ms)。
    if (g_uart_rx_overrun) {
        g_uart_rx_overrun = 0;
        if (g_airlink_uart.rxoffset > 0) {
            LLOGD("uart overrun 重同步: 清空 rxoffset=%u", (unsigned)g_airlink_uart.rxoffset);
            g_airlink_uart.rxoffset = 0;
        }
    }
    if (g_airlink_uart.rxoffset > 0 && g_airlink_last_cmd_timestamp > 0) {
        uint64_t _now = luat_mcu_tick64_ms();
        if (_now - g_airlink_last_cmd_timestamp > AIRLINK_UART_RX_RESYNC_MS) {
            // [修改] 长度感知看门狗: 500ms 未解出帧时, 先判 rxbuf 首部是否为合法帧头
            // (magic A1B1CA66 + len 字段)。若是合法半帧(大帧尾因从机 TX 暂顿 >500ms 未到),
            // 只等尾不 reset; 仅当帧头非法或已收字节 ≥ 理论帧长(帧损坏/丢字节)才重同步。
            uint8_t *_hdr = g_airlink_uart.rxbuf;
            size_t _have = (size_t)g_airlink_uart.rxoffset;
            int _wait_tail = 0;
            uint16_t _len = 0;
            size_t _raw_max = 0;
            if (_have >= 7 && _hdr[0] == 0x7E && _hdr[1] == 0xA1 && _hdr[2] == 0xB1
                && _hdr[3] == 0xCA && _hdr[4] == 0x66) {
                _len = (uint16_t)(_hdr[5] | ((uint16_t)_hdr[6] << 8));
                _raw_max = 2 + 2 * ((size_t)sizeof(airlink_link_data_t) + (size_t)_len);
                // len 是 u16(最大 65535) 理论可算 131104, 加 <= UART_BUFF_SIZE 兜底防等不存在的超长帧
                if (_raw_max <= UART_BUFF_SIZE && _have < _raw_max) {
                    _wait_tail = 1;
                }
            }
            if (_wait_tail) {
                // 合法半帧: 只等尾不 reset
            } else {
                LLOGD("uart rx 解析器失步: %llums 未解出帧, 强制清空 rxoffset=%u 重同步",
                      (unsigned long long)(_now - g_airlink_last_cmd_timestamp),
                      (unsigned)g_airlink_uart.rxoffset);
                g_airlink_uart.rxoffset = 0;
            }
        }
    }
    // 当前 mobile RPC 最大原始 frame 约 3663B，UART 最坏转义后约 7328B；
    // 这里保留 8KiB 接收缓存，允许单个最大帧完整进入并等待包尾。
    if (g_airlink_uart.rxoffset + len > UNPACK_BUFF_SIZE) {
        LLOGW("rxbuf 溢出: rxoffset=%u + len=%u > limit=%u — 重置缓冲区",
              (unsigned)g_airlink_uart.rxoffset, (unsigned)len, (unsigned)UNPACK_BUFF_SIZE);
        g_airlink_uart.rxoffset = 0;
        if (len > UNPACK_BUFF_SIZE) return;
    }
    uint8_t *rxbuff = g_airlink_uart.rxbuf;
    memcpy(rxbuff + g_airlink_uart.rxoffset, buff, len);
    g_airlink_uart.rxoffset += len;

    // 首先, 检查首个字节是不是0x7E, 如果不是, 那么就需要查找包头, 直至找到0x7E
    if (rxbuff[0] != 0x7E) {
        offset = 1;
        // 如果不是, 那么就需要查找包头, 直至找到0x7E
        while (offset < g_airlink_uart.rxoffset && rxbuff[offset] != 0x7E) {
            offset++;
        }
        if (offset >= g_airlink_uart.rxoffset) {
            //LLOGD("没有找到包头, 清空当前数据, 等待下次数据 %d", g_airlink_uart.rxoffset);
            g_airlink_uart.rxoffset = 0;
            return;
        }
        // 找到包头, 移动数据到前面
        if (offset > 1) {
            memmove(rxbuff, rxbuff + offset, g_airlink_uart.rxoffset - offset);
            g_airlink_uart.rxoffset -= offset;
        }
    }

    offset = 0;
    while (g_airlink_uart.rxoffset - offset >= 2) {
        // 搜索包头
        if (rxbuff[offset] == 0x7E) {
            // 找到包头, 继续查找包尾
            end_offset = offset + 1;
            while (end_offset < g_airlink_uart.rxoffset && rxbuff[end_offset] != 0x7E) {
                end_offset++;
                if ((end_offset - offset + 1) > UART_BUFF_SIZE) {
                    LLOGW("rxbuf 搜索帧尾超限: span=%u limit=%u rxoffset=%u — 重置缓冲区",
                          (unsigned)(end_offset - offset + 1), (unsigned)UART_BUFF_SIZE, (unsigned)g_airlink_uart.rxoffset);
                    g_airlink_uart.rxoffset = 0;
                    break;
                }
            }
            if (end_offset >= g_airlink_uart.rxoffset) {
                // 没有找到包尾, 等待下次数据
                break;
            }
            // 找到包尾, 解析数据
            size_t data_len = end_offset - offset - 1; // 包头和包尾不算在内
            // 反转义数据
            if (data_len > 1) {
                if (!unpack_data(rxbuff + offset + 1, data_len)) { // 包头和包尾不算在内
                    // 解包失败：半截帧(帧尾丢失)或假帧头会让 end_offset 落在下一帧头,
                    // 此时 end_offset 后紧跟的不是下一帧头 0x7E, 需丢弃到 end_offset 前、
                    // 保留 end_offset 作帧头重新同步; 否则(正常CRC错帧, end_offset 是真帧尾)
                    // 走下方默认整帧丢弃。
                    if (end_offset + 1 >= g_airlink_uart.rxoffset || rxbuff[end_offset + 1] != 0x7E) {
                        memmove(rxbuff, rxbuff + end_offset, g_airlink_uart.rxoffset - end_offset);
                        g_airlink_uart.rxoffset -= end_offset;
                        offset = 0;
                        continue;
                    }
                }
            }
            // 移动剩余数据到前面
            memmove(rxbuff, rxbuff + end_offset + 1, g_airlink_uart.rxoffset - end_offset - 1);
            // [修复] 原 rxoffset -= (end_offset+1-offset) 在 offset>0(帧界错位后扫描到假头)时
            // 少减了 offset 个字节: memmove 实际丢弃 [0..end_offset], 记账却只减 [offset..end_offset],
            // 导致 rxoffset 虚高 offset 字节、下一轮读到垃圾尾。成功路径 offset 恒应为 0,
            // 此处丢弃的是 [0..end_offset] 共 end_offset+1 字节, 与失败路径(丢 [0..end_offset-1])语义一致。
            g_airlink_uart.rxoffset -= (end_offset + 1);
            offset = 0;
        } else {
            // 没有找到包头, 移动一个字节
            offset++;
        }
    }
}

static void send_devinfo_update_evt(void) {
    airlink_queue_item_t item = {0};
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item); 
}

__USER_FUNC_IN_RAM__ static void uart_transfer_task(void *param)
{
    int ret;
    luat_event_t event = {0};
    airlink_queue_item_t item = {0};
    uint8_t* ptr = NULL;
    size_t offset = 0;
    int uart_id;
    uint8_t *pbuff = luat_heap_malloc(AIRLINK_UART_RAW_FRAME_MAX);
    event.id = 0;
    uint64_t last_heartbeat_ms = 0;

    while(g_airlink_uart.uart_running)
    {
        ret = luat_rtos_queue_recv(g_airlink_uart.tx_evt_queue, &event, sizeof(luat_event_t), AIRLINK_MODE_WAIT_TIMEOUT);//在evt_queue队列中复制数据到指定缓冲区event，阻塞等待60s
        if (ret == 0) {
            record_statistic(event);
        }
        #ifdef LUAT_CONF_AIRLINK_MODE_WAIT
        if (luat_airlink_current_mode_get() != LUAT_AIRLINK_MODE_UNKNOW && luat_airlink_current_mode_get() != LUAT_AIRLINK_MODE_UART) {
            luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
            break; // 如果当前模式已经确定了, 并且不是UART模式, 那么就退出这个任务
        }
        if (ret < 0) {
            // 空闲超时: 发送心跳帧（间隔 2s），保持对端 g_airlink_last_cmd_timestamp 刷新
            if (luat_mcu_tick64_ms() - last_heartbeat_ms > 2000) {
                last_heartbeat_ms = luat_mcu_tick64_ms();
                send_devinfo_update_evt();
            }
            continue;
        }
        #else
        if (ret != 0) {
            // 空闲超时: 发送心跳帧（间隔 2s），保持对端 g_airlink_last_cmd_timestamp 刷新
            if (luat_mcu_tick64_ms() - last_heartbeat_ms > 2000) {
                last_heartbeat_ms = luat_mcu_tick64_ms();
                send_devinfo_update_evt();
            }
        }
        #endif
        while (1) {
            uart_id = g_airlink_spi_conf.uart_id;
            // 有数据, 要处理了
            item.len = 0;
            item.cmd = NULL;
            ret = luat_airlink_cmd_recv_for_mode(LUAT_AIRLINK_MODE_UART, &item);//从（发送）队列里取出数据存在item中
            if (ret != 0) {
                break; // 没有数据了, 退出循环
            }
            size_t packed_len = 0;
            uint8_t *txbuff = g_airlink_uart.s_txbuff;
            if (item.len == 0 || item.cmd == NULL) {
                memcpy(basic_info + sizeof(luat_airlink_cmd_t), luat_airlink_self_dev_info_ptr(), sizeof(luat_airlink_dev_info_t));
                if (airlink_uart_pack_frame_or_log(pbuff, AIRLINK_UART_RAW_FRAME_MAX, basic_info, 128, &packed_len, "uart basic info") != 0) {
                    continue;
                }
                if (g_airlink_debug) {
                    LLOGD("send basic info %d", sizeof(basic_info));
                }
            } else {
                if (airlink_uart_pack_frame_or_log(pbuff, AIRLINK_UART_RAW_FRAME_MAX, (uint8_t*)item.cmd, item.len, &packed_len, "uart tx") != 0) {
                    luat_airlink_cmd_free(item.cmd);
                    continue;
                }
                luat_airlink_cmd_free(item.cmd);
            }
            if ((packed_len * 2 + 2) > UART_BUFF_SIZE) {
                LLOGE("uart tx: escaped frame too large raw=%u worst=%u limit=%u — dropping (consider enabling frag)",
                      (unsigned)packed_len, (unsigned)(packed_len * 2 + 2), (unsigned)UART_BUFF_SIZE);
                g_airlink_statistic.tx_pkg.drop++;
                continue;
            }
            // 0x7E 开始, 0x7D 结束, 遇到 0x7E/0x7D 要转义
            txbuff[0] = 0x7E;
            offset = 1;
            ptr = (uint8_t*)pbuff;
            for (size_t i = 0; i < packed_len; i++)
            {
                if (ptr[i] == 0x7E) {
                    txbuff[offset++] = 0x7D;
                    txbuff[offset++] = 0x02;
                }
                else if (ptr[i] == 0x7D) {
                    txbuff[offset++] = 0x7D;
                    txbuff[offset++] = 0x01;
                }
                else
                {
                    txbuff[offset++] = ptr[i];
                }
            }
            txbuff[offset++] = 0x7E;
            luat_uart_write(uart_id, txbuff, offset);
            // LLOGD("发送数据长度:%d", offset);
            // 留 ≥1ms 线上间隙, 防止主机 RX 溢出(睡眠与 DMA 传输重叠, 按帧长自适应)
            if (AIRLINK_UART_TX_FRAME_GAP_MS > 0) {
                uint32_t tx_frame_ms = (offset + 199u) / 200u; // 帧传输耗时(ms) @2Mbps 8N1
                luat_rtos_task_sleep(tx_frame_ms + AIRLINK_UART_TX_FRAME_GAP_MS);
            }
            if (offset > 1600) {
                LLOGW("uart tx large frame %u bytes", (unsigned)offset);
            }
        }
    }
    luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
    LLOGI("uart_transfer_task exit");
    luat_heap_free(pbuff);
    g_airlink_uart.transfer_task = NULL;
    luat_rtos_task_delete(NULL); // 删除当前任务
}
__USER_FUNC_IN_RAM__ static void uart_receive_task(void *param)
{
    int ret;
    luat_event_t event = {0};
    int uart_id;
    event.id = 0;
    while (g_airlink_uart.uart_running)
    {
        ret = luat_rtos_queue_recv(g_airlink_uart.rx_evt_queue, &event, sizeof(luat_event_t), AIRLINK_MODE_WAIT_TIMEOUT);//在evt_queue队列中复制数据到指定缓冲区event，阻塞等待60s
        //LLOGD("收到airlink数据事件 ret:%d, id:%d", ret, event.id);
        if (ret == 0) {
            record_statistic(event);
        }
        #ifdef LUAT_CONF_AIRLINK_MODE_WAIT
        if (luat_airlink_current_mode_get() != LUAT_AIRLINK_MODE_UNKNOW && luat_airlink_current_mode_get() != LUAT_AIRLINK_MODE_UART) {
            luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
            break; // 如果当前模式已经确定了, 并且不是UART模式, 那么就退出这个任务
        }
        #endif

        luat_airlink_check_link_timeout();

        while (1) {
            static uint64_t uart_read_last_log = 0;
            uart_id = g_airlink_spi_conf.uart_id;
            // [修改] 读块 1024→UART_BUFF_SIZE(4096): 下载大帧(≤~1415B)在 RX 积压时可整帧一次读入,
            // 减少跨读分片(1024+391)概率, 配合长度看门狗进一步降低失步
            ret = luat_uart_read(uart_id, (char *)g_airlink_uart.s_rxbuff, UART_BUFF_SIZE);
            if (ret <= 0)
            {
                if (ret < 0) {
                    uint64_t tnow = luat_mcu_tick64_ms();
                    if (tnow - uart_read_last_log > 5000) {
                        LLOGW("uart read error ret=%d", ret);
                        uart_read_last_log = tnow;
                    }
                }
                break;
            }
            // LLOGD("收到uart数据长度 %d", ret);
            // 推送数据, 并解析处理
            on_airlink_uart_data_in(g_airlink_uart.s_rxbuff, ret);
        }
    }
    luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
    LLOGI("uart_receive_task exit");
    g_airlink_uart.receive_task = NULL;
    luat_rtos_task_delete(NULL); // 删除当前任务
}

int luat_airlink_start_uart(void)
{
    
    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    cmd->cmd = 0x10;
    cmd->len = 128;
    int ret = 0;
    AIRLINK_DEV_INFO_UPDATE_CB device_info_update_cb = NULL;
    if (luat_airlink_uart_ensure_buffers() != 0) {
        return -1;
    }
    g_airlink_uart.uart_running = 1;
#if defined(LUAT_USE_AIRLINK_EXEC_MOBILE) || defined(LUAT_USE_AIRLINK_EXEC_WLAN)
    device_info_update_cb = send_devinfo_update_evt;
    extern void luat_airlink_devinfo_init();
    luat_airlink_devinfo_init(device_info_update_cb);
#endif
    ret = luat_rtos_queue_create(&g_airlink_uart.tx_evt_queue, 128, sizeof(luat_event_t));
    if (ret) {
        LLOGW("创建tx_evt_queue ret:%d", ret);
    }
    ret = luat_rtos_queue_create(&g_airlink_uart.rx_evt_queue, 128, sizeof(luat_event_t));
    if (ret) {
        LLOGW("创建rx_evt_queue ret:%d", ret);
    }
    luat_airlink_ip2br_init();
    luat_rtos_task_sleep(5);
    uart_gpio_setup();
    luat_airlink_mode_cb_register(LUAT_AIRLINK_MODE_UART, on_newdata_notify, on_link_data_notify, device_info_update_cb);
    luat_airlink_slot_register(LUAT_AIRLINK_MODE_UART, on_newdata_notify);

    luat_airlink_uart_transfer_task();
    luat_airlink_uart_receive_task();
    luat_airlink_uart_fota_task_create();

    return ret;
}

int luat_airlink_stop_uart(void)
{
    g_airlink_uart.uart_running = 0;
    luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
    if (g_airlink_uart.tx_evt_queue) {
        luat_event_t evt = {.id = 0};
        luat_rtos_queue_send(g_airlink_uart.tx_evt_queue, &evt, sizeof(evt), 0);
    }
    if (g_airlink_uart.rx_evt_queue) {
        luat_event_t evt = {.id = 0};
        luat_rtos_queue_send(g_airlink_uart.rx_evt_queue, &evt, sizeof(evt), 0);
    }
    return 0;
}

static void luat_airlink_uart_transfer_task(void)
{
    int ret = 0;
    if (g_airlink_uart.transfer_task != NULL)
    {
        LLOGE("UART TX任务已经启动过了!!! uart %d", g_airlink_spi_conf.uart_id);
        return;
    }
    ret = luat_rtos_task_create(&g_airlink_uart.transfer_task, 4 * 1024, 50, "uart_transfer", uart_transfer_task, NULL, 0);
    if (ret) {
        LLOGW("创建uart_transfer_task ret:%d", ret);
    }
}

static void luat_airlink_uart_receive_task(void)
{
    int ret = 0;
    if (g_airlink_uart.receive_task != NULL)
    {
        LLOGE("UART RX任务已经启动过了!!! uart %d", g_airlink_spi_conf.uart_id);
        return;
    }
    ret = luat_rtos_task_create(&g_airlink_uart.receive_task, 4 * 1024, 52, "uart_receive", uart_receive_task, NULL, 0);
    if (ret) {
        LLOGW("创建uart_receive_task ret:%d", ret);
    }
}

/* UART 版 FOTA 执行器 — 命令走标准 airlink 帧 (0x04/0x05/0x06/0x07, 对端需已注册)
 * 发送用 send_cmd_simple 入队 → uart_transfer_task 发送, 避免在 transport 任务内自锁
 * 节奏保守: XT804 XIP 写 flash 时 CPU stall 会丢 UART 字节, 慢节奏兼容各从机 */
static void uart_fota_exec(void) {
    extern luat_airlink_fota_t *g_airlink_fota;
    FILE *fd = luat_fs_fopen(g_airlink_fota->path, "rb");
    if (fd == NULL) {
        LLOGE("UART FOTA: open file fail %s", g_airlink_fota->path);
        g_airlink_fota->state = 0;
        return;
    }
    g_airlink_fota->total_size = luat_fs_fsize(g_airlink_fota->path);
    LLOGI("UART FOTA start, size=%ld", g_airlink_fota->total_size);

    // 1. fota_init — 从机同步擦除 OTA 区 (376KB, ~4.2秒)
    luat_airlink_send_cmd_simple(0x04, NULL, 0);
    LLOGI("UART FOTA init sent, waiting for erase (~4.2s)...");
    luat_rtos_task_sleep(5000);

    // 2. fota_write chunks (1KB/帧, 走标准命令帧)
    // 节奏: XT804 XIP 架构, 从机写 flash 时 CPU stall → UART RX 丢字节
    // 必须给从机充足时间写完再收下一帧: 每帧 40ms + 每 4KB 额外 200ms (页擦除余量)
    uint8_t *chunk = luat_heap_malloc(1050);
    size_t sent = 0;
    while (g_airlink_fota->state) {
        int ret = (int)luat_fs_fread(chunk, 1, 1024, fd);
        if (ret < 1) break;
        luat_airlink_send_cmd_simple(0x05, chunk, ret);
        sent += ret;
        if (sent == 8 * 1024) {
            LLOGI("UART FOTA 8KB, waiting for flash erase...");
            luat_rtos_task_sleep(8000);
        } else if (sent == 16 * 1024) {
            luat_rtos_task_sleep(3000);
        } else if ((sent & 0xFFF) == 0) {
            // 每 4KB 额外等待, 覆盖从机页擦除 (Sector Erase ~45ms × N)
            luat_rtos_task_sleep(200);
        } else {
            luat_rtos_task_sleep(40);
        }
    }
    luat_heap_free(chunk);
    luat_fs_fclose(fd);
    LLOGI("UART FOTA sent %zu bytes", sent);

    // 3. fota_done — 发前多等 3s, 让从机消化完 RX 缓冲里的数据帧
    LLOGI("UART FOTA drain 3s before done...");
    luat_rtos_task_sleep(3000);
    luat_airlink_send_cmd_simple(0x06, NULL, 0);
    luat_rtos_task_sleep(1000);

    // 4. fota_end
    luat_airlink_send_cmd_simple(0x07, NULL, 0);
    luat_rtos_task_sleep(1000);

    // 5. 复位指令 (CMD 0x03) → 从机重启加载新固件
    LLOGI("UART FOTA done, sending reset...");
    luat_airlink_send_cmd_simple_nodata(0x03);
    luat_rtos_task_sleep(3000);

    g_airlink_fota->state = 0;
    LLOGI("UART FOTA done");
}

static void uart_fota_task(void *param) {
    (void)param;
    while (g_airlink_uart.uart_running) {
        extern luat_airlink_fota_t *g_airlink_fota;
        if (g_airlink_fota && g_airlink_fota->state) {
            uart_fota_exec();
        }
        luat_rtos_task_sleep(100);
    }
    luat_rtos_task_delete(NULL);
}

static void luat_airlink_uart_fota_task_create(void) {
    static luat_rtos_task_handle fota_task = NULL;
    if (fota_task != NULL) return;
    int ret = luat_rtos_task_create(&fota_task, 4 * 1024, 51, "uart_fota", uart_fota_task, NULL, 0);
    if (ret) {
        LLOGW("创建uart_fota_task ret:%d", ret);
    }
}

