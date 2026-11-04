#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_HSPI_MASTER

#include <stdlib.h>

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_hspi_master.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.hspi"
#include "luat_log.h"

static void hspi_pack(const uint8_t *payload, uint16_t plen,
                       uint8_t *out, uint16_t *out_len) {
    uint8_t hdr_chk = (0x00 + (plen >> 8) + (plen & 0xFF) + 1) & 0xFF;
    uint16_t total = 9 + plen;
    while (total & 3) total++;
    if (total > *out_len) return; // 缓冲区不足
    out[0] = 0xAA; out[1] = 0x00;
    out[2] = (plen >> 8) & 0xFF; out[3] = plen & 0xFF;
    out[4] = 1; out[5] = 0; out[6] = 0; out[7] = hdr_chk;
    memcpy(out + 8, payload, plen);
    uint8_t pl_chk = 0;
    for (uint16_t i = 0; i < plen; i++) pl_chk += payload[i];
    out[8 + plen] = pl_chk;
    *out_len = total;
}

static int airlink_pack(uint16_t cmd_id, const uint8_t *payload, uint16_t payload_len,
                          uint8_t *out, uint16_t *out_len) {
    if (payload_len > 1580) return -1;
    uint16_t cmd_total = 4 + payload_len;
    uint16_t link_total = 16 + cmd_total;
    if (*out_len < link_total) return -1;
    if (payload_len && !payload) return -1;
    uint8_t *p = out + sizeof(airlink_link_data_t);
    p[0]=cmd_id & 0xFF; p[1]=(cmd_id>>8)&0xFF;
    p[2]=payload_len & 0xFF; p[3]=(payload_len>>8)&0xFF;
    if (payload_len) memcpy(p+4, payload, payload_len);
    // Same incremental pkgid, real capability flags and CRC as UART/SPI.
    luat_airlink_data_pack(p, cmd_total, out);
    *out_len = link_total;
    return 0;
}

static airlink_link_data_t* airlink_unpack(const uint8_t *data, size_t len) {
    return luat_airlink_data_unpack((uint8_t*)data, len);
}

extern int xt804_hspi_spi_xfer(const uint8_t *tx, uint8_t *rx, uint16_t len);

/* 前向声明: hspi_rd 在 hspi_wr 之后定义, 但 hspi_tx_ready 需要调用它 */
static int hspi_rd(uint8_t addr, uint8_t *data, uint16_t len);

/**
 * 手册 10.4.2.2: 下发前查询 TX_BUFF_AVAIL
 *   bit0 = 1: 数据通道就绪, 主机可以下发数据
 *   bit1 = 1: 命令通道就绪, 主机可以下发命令
 * 超时 ~100ms 返回 -1
 */
static int hspi_tx_ready(int is_cmd) {
    int retry = 100;
    while (retry-- > 0) {
        uint8_t sts[2];
        if (hspi_rd(0x03, sts, 2) < 0) continue;
        int ready = is_cmd ? ((sts[0] >> 1) & 1) : (sts[0] & 1);
        if (ready) return 0;
        luat_rtos_task_sleep(1);
    }
    return -1;
}

/**
 * 手册 10.4.3.4 下行数据流程:
 *   1. 查询 TX_BUFF_AVAIL[0] 直到就绪 (仅数据端口, 寄存器直接写)
 *   2. 分多次下发: 非末段用 DAT_PORT0(addr=0x00, CMD 0x80)
 *                    末段用 DAT_PORT1(addr=0x10, CMD 0x90)
 *
 * @param addr  0x00=非末段, 0x10=末段; 0x02-0x07=寄存器 (不查 TX_BUFF_AVAIL)
 * @param data  待发送数据 (数据端口已 4 字节对齐填充)
 * @param len   数据长度
 * @return 0=成功, -1=失败
 */
static int hspi_wr(uint8_t addr, const uint8_t *data, uint16_t len) {
    // 数据端口(0x00/0x10)写前查 TX_BUFF_AVAIL[0]; 寄存器(0x02-0x07)直接写
    if (addr == 0x00 || addr == 0x10) {
        int retry = 100;
        while (retry-- > 0) {
            uint8_t sts[2];
            if (hspi_rd(0x03, sts, 2) < 0) continue;
            if (sts[0] & 0x01) break;
            luat_rtos_task_sleep(1);
        }
        if (retry < 0) return -1;
    }

    uint16_t xfer = (addr >= 0x10) ? ((1 + len + 3) & ~3) : (1 + len);
    // 用 malloc 避免嵌套调用时栈溢出 (调用链: transport_task → send_cmd → hspi_wr, 叠加超 8KB)
    uint8_t *tx = malloc(xfer + 4);
    if (!tx) return -1;
    tx[0] = addr | 0x80;
    memcpy(tx + 1, data, len);
    if (xfer > 1 + len)
        memset(tx + 1 + len, 0, xfer - 1 - len);
    uint8_t *rx = malloc(xfer + 4);
    if (!rx) { free(tx); return -1; }
    int ret = xt804_hspi_spi_xfer(tx, rx, xfer);
    free(tx); free(rx);
    return ret;
}

/**
 * 手册 10.4.3.4 上行数据流程:
 *   addr=0x00: 非末段读取 (CMD 0x00)
 *   addr=0x10: 末段读取 (CMD 0x10), 通知硬件帧结束释放 TX 描述符
 */
static int hspi_rd(uint8_t addr, uint8_t *data, uint16_t len) {
    uint8_t original_len = len;
    // 所有传输必须 4 字节对齐（含寄存器读），否则 XT804 不锁存 RX_DAT_LEN
    uint16_t xfer = ((1 + len + 3) & ~3);
    uint8_t tx[20];
    uint8_t rx[20];
    if (xfer > sizeof(tx)) return -1;
    memset(tx, 0, sizeof(tx));
    tx[0] = addr;
    memset(tx + 1, 0xFF, xfer - 1);
    int ret = xt804_hspi_spi_xfer(tx, rx, xfer);
    if (ret >= 0 && data) {
        memcpy(data, rx + 1, original_len);
    }
    return ret;
}

/**
 * @brief 主机侧使能 XT804 HSPI INT 脚输出
 *
 * 写 HSPI 外部寄存器 SPI_INT_HOST_MASK(offset 0x05) = 0x0000 确保不屏蔽中断
 * 注意: 不能读 SPI_INT_HOST_STTS(0x06) 来"确认" — "读可清"会清 pending 中断。
 * 验证接口通可以通过写 MASK 寄存器是否成功来判断。
 * 返回 0 成功, -1 失败
 */
int xt804_hspi_enable_host_int(void) {
    uint8_t val[2] = {0x00, 0x00};
    // SPI_INT_HOST_MASK = 0 (不屏蔽)
    int ret = hspi_wr(0x05, val, 2);
    if (ret < 0) {
        LLOGE("write SPI_INT_HOST_MASK failed %d", ret);
        return ret;
    }
    LLOGI("HSPI host INT enable done (MASK=0x0000)");
    return 0;
}

int xt804_hspi_check_status(int *data_rdy, int *cmd_rdy) {
    uint8_t sts[2];
    if (hspi_rd(0x03, sts, 2) < 0) return -1;
    if (data_rdy) *data_rdy = sts[0] & 1;
    if (cmd_rdy)  *cmd_rdy  = (sts[0] >> 1) & 1;
    return 0;
}

// Blocking response reads use the same validated frame path and capability
// extraction as asynchronous reads; there is no stripped-header shortcut.
int xt804_hspi_read_response(uint8_t *resp, uint16_t *resp_len,
                               uint16_t *cmd_id, uint32_t timeout_ms) {
    if (!resp_len) return -1;
    uint64_t deadline = luat_mcu_tick64_ms() + timeout_ms;
    while (luat_mcu_tick64_ms() < deadline) {
        uint16_t len = *resp_len;
        if (xt804_hspi_read_data_intr(resp, &len, cmd_id) == 0) { *resp_len = len; return 0; }
        luat_rtos_task_sleep(2);
    }
    return -1;
}

/**
 * 读取从机→主机数据 (上行) — 精简为 2 次 SPI 事务 (原 3 次)
 *
 * 流程:
 *   [事务1] 读 RX_DAT_LEN(0x02) → 判定有无数据 + 帧长 (固定 1600)
 *   [事务2] 读 DAT_PORT1(0x10)  → 读取数据 (末段读, 消耗 desc)
 *
 * 为何砍掉 0x06(SPI_INT_HOST_STTS): 它是"读可清"边沿, 灌流时恒 0 (边沿只在
 * 空闲→首帧时出现一次), 不提供额外信息; 从机环空时把 RX_DAT_LEN 写回 0
 * (wm_hspi.c SDIO_RX_IRQHandler) 作为唯一可靠的"无数据"信号, 主控据此停读。
 * 读 0x10 后靠 CRC 区分真帧/陈旧垃圾 (环空写0正是防主控反复读陈旧帧)。
 *
 * 响应数据格式 (从机→主机):
 *   数据端口返回完整 AirLink 帧头 magic(4)+len(2)+crc16(2)+pkgid(4)+flags(4)
 *   先用公共解包函数校验长度/CRC 并更新真实 flags，再读取 cmd_t+payload
 *   不接受剥离帧头的格式，避免绕过校验或猜测对端能力
 *
 * 所有缓冲区用栈上数组 (任务栈 8KB, 最大帧 1600B 足够)
 *
 * @param resp     输出: cmd->data 负载
 * @param resp_len 输入: buf大小 / 输出: 实际数据长度
 * @param cmd_id   输出: AirLink 命令 ID
 * @return 0=成功, -1=无数据/硬件错
 */
int xt804_hspi_read_data_intr(uint8_t *resp, uint16_t *resp_len,
                               uint16_t *cmd_id) {
    // [事务1] 直接读 RX_DAT_LEN 判定有无数据 (唯一可靠的"有数据"信号, 环空=0)
    uint8_t rxl[2];
    if (hspi_rd(0x02, rxl, 2) < 0) return -1;
    uint16_t n = rxl[0] | ((uint16_t)rxl[1] << 8);
    if (n == 0 || n == 0xFFFF) return -1;  // 确实无数据
    if (n > 1600) return -1;               // 防御: 垃圾长度写穿栈缓冲 (死机根因)

    // [事务2] 读数据 (栈上数组, 4字节对齐) + CRC 校验
    // 主控用 0x10 末段读（读即消耗 desc，从机 valid 清后才写下一帧）；CRC 校验保留为防御
    uint16_t npad = (n + 3) & ~3;
    uint8_t tx_buf[1608];
    uint8_t rx_buf[1608];
    uint8_t buf[1608];
    memset(tx_buf, 0, sizeof(tx_buf));
    tx_buf[0] = 0x10;  // DAT_PORT1 末段读 — 通知硬件帧结束, 释放 TX 描述符
    memset(tx_buf + 1, 0xFF, npad);
    uint16_t xfer = ((npad + 1 + 3) & ~3);
    if (xfer > sizeof(tx_buf)) xfer = sizeof(tx_buf);

    if (xt804_hspi_spi_xfer(tx_buf, rx_buf, xfer) < 0) return -1;
    memcpy(buf, rx_buf + 1, npad);

    uint16_t plen = n;
    airlink_link_data_t* link = NULL;
    int is_fmt1 = (plen >= 4 && buf[0]==0xA1 && buf[1]==0xB1 && buf[2]==0xCA && buf[3]==0x66);
    if (is_fmt1) {
        // 格式1 (magic 开头) → 必须 CRC 通过 (防御: 单帧队列下不应失败)
        link = airlink_unpack(buf, plen);
        if (link == NULL) {
            // 环空时读到的陈旧帧/垃圾(CRC 不匹配)静默丢弃; 正常路径打印
            LLOGE("HSPI frame CRC fail len=%u — drop", plen);
            return -1;
        }
    } else {
        // 无 magic = 环空时读到的陈旧帧/垃圾, 静默丢弃
        return -1;
    }

    // 解析: 格式1 已校验通过, 跳过完整 airlink_link_data_t 帧头 (16 字节)
    uint8_t *pdata = link->data;
    plen = link->len;

    // 现在 pdata 指向 cmd_t+payload
    // cmd_t: cmd(2 LE) + payload_len(2 LE) + payload
    if (plen < 4) return -1;
    uint16_t cmd_id_val = pdata[0] | ((uint16_t)pdata[1] << 8);
    uint16_t pld_len_val = pdata[2] | ((uint16_t)pdata[3] << 8);
    //LLOGD("HSPI parsed: cmd=0x%04X pld_len=%u remain=%u", cmd_id_val, pld_len_val, plen - 4);
    if (plen - 4 < pld_len_val) return -1;
    if (*resp_len < pld_len_val) return -1;

    if (cmd_id) *cmd_id = cmd_id_val;
    *resp_len = pld_len_val;
    if (resp) memcpy(resp, pdata + 4, pld_len_val);
    return 0;
}

int xt804_hspi_send_cmd(uint16_t cmd_id, const uint8_t *payload, uint16_t payload_len,
                         uint8_t *resp, uint16_t *resp_len, uint32_t timeout_ms) {
    uint8_t link_buf[1600];
    uint16_t link_len = sizeof(link_buf);
    if (airlink_pack(cmd_id, payload, payload_len, link_buf, &link_len) != 0)
        return -1;
    //LLOGD("HSPI send: cmd=0x%04X pld=%u link=%u", cmd_id, payload_len, link_len);
    //LLOGD("HSPI link[0..7]: %02X%02X%02X%02X%02X%02X%02X%02X",
    //    link_buf[0],link_buf[1],link_buf[2],link_buf[3],
    //    link_buf[4],link_buf[5],link_buf[6],link_buf[7]);
    uint8_t hspi_buf[1600 + 16];
    uint16_t hspi_len = sizeof(hspi_buf);
    hspi_pack(link_buf, link_len, hspi_buf, &hspi_len);
    //LLOGD("HSPI hspi_frame_len=%u", hspi_len);
    if (hspi_wr(0x10, hspi_buf, hspi_len) < 0) return -1;
    if (!resp || !resp_len) return 0;
    uint16_t rcmd_id;
    uint16_t rlen = *resp_len;
    if (xt804_hspi_read_response(resp, &rlen, &rcmd_id, timeout_ms) != 0)
        return -1;
    *resp_len = rlen;
    return 0;
}

#endif /* LUAT_USE_AIRLINK_HSPI_MASTER */
