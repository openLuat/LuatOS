#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_HSPI_MASTER

#include <stdlib.h>

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.hspi"
#include "luat_log.h"

static uint16_t crc16_modbus(const uint8_t *data, size_t len) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++)
            crc = (crc >> 1) ^ ((crc & 1) ? 0xA001 : 0);
    }
    return crc;
}

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
    uint16_t cmd_total = 4 + payload_len;
    uint16_t link_total = 16 + cmd_total;
    if (*out_len < link_total) return -1;
    uint8_t *p = out;
    p[0]=0xA1; p[1]=0xB1; p[2]=0xCA; p[3]=0x66;
    p[4]=cmd_total & 0xFF; p[5]=(cmd_total>>8)&0xFF;
    p[6]=0; p[7]=0;
    memset(p+8, 0, 8);
    p[16]=cmd_id & 0xFF; p[17]=(cmd_id>>8)&0xFF;
    p[18]=payload_len & 0xFF; p[19]=(payload_len>>8)&0xFF;
    if (payload && payload_len) memcpy(p+20, payload, payload_len);
    uint16_t crc = crc16_modbus(p+8, cmd_total+8);
    p[6] = crc & 0xFF; p[7] = (crc >> 8) & 0xFF;
    *out_len = link_total;
    return 0;
}

static airlink_link_data_t* airlink_unpack(const uint8_t *data, size_t len) {
    for (size_t i = 0; i + 12 <= len; i++) {
        if (data[i]==0xA1 && data[i+1]==0xB1 && data[i+2]==0xCA && data[i+3]==0x66) {
            // 对齐保护：link_data_t 含 uint32_t，要求 4 字节对齐
            if (i & 3) continue;
            airlink_link_data_t *link = (airlink_link_data_t*)(data + i);
            // 防御：link->len 由对端控制，校验不超过剩余缓冲区
            size_t remain = len - i - 8;
            uint16_t crc_len = (link->len + 8 > remain) ? (uint16_t)remain : link->len + 8;
            uint16_t crc = crc16_modbus(data + i + 8, crc_len);
            if (crc == link->crc16) return link;
        }
    }
    return NULL;
}

extern int xt804_hspi_spi_xfer(const uint8_t *tx, uint8_t *rx, uint16_t len);
extern uint32_t xt804_hspi_get_tick_ms(void);

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
    // hspi_rd 只用于寄存器读 (0x02/0x03/0x06), 最大 4 字节 + 1 地址 = 5 字节
    uint16_t xfer = (addr < 0x10) ? (1 + len) : ((1 + len + 3) & ~3);
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
 * ★ 注意: 不能读 SPI_INT_HOST_STTS(0x06) 来"确认"。
 *   手册 10.4.2.4: "读可清" — 读 0x06 会清除 pending 的中断状态。
 *   如果从机在主机启动前已经拉低 INT，这一读会导致后面 Phase 1 永远检测不到 INT。
 *   验证接口通可以通过写 MASK 寄存器是否成功来判断。
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

int xt804_hspi_read_response(uint8_t *resp, uint16_t *resp_len,
                              uint16_t *cmd_id, uint32_t timeout_ms) {
    uint64_t deadline = luat_mcu_tick64_ms() + timeout_ms;
    while (luat_mcu_tick64_ms() < deadline) {
        uint8_t rxl[2];
        if (hspi_rd(0x02, rxl, 2) < 0) {
            luat_rtos_task_sleep(1);
            continue;
        }
        uint16_t n = rxl[0] | ((uint16_t)rxl[1] << 8);
        if (n == 0 || n == 0xFFFF) {
            luat_rtos_task_sleep(5);
            continue;
        }
        if (n > 1600) n = 1600;
        // rd02 返回的是完整帧长（含 airlink header）。
        // rd02 返回完整帧长。HW 剥离了 8 字节 airlink header（magic+len+crc），
        // 剩余 pkgid(4)+flags(4)+cmd_t+payload 在数据端口中。
        uint16_t data_len = (n > 8) ? (n - 8) : 0;
        if (data_len < 4 + 4 + 4) continue;  // pkgid+flags+空cmd_t
        uint16_t npad = (data_len + 3) & ~3;
        uint8_t *buf = malloc(npad + 4);
        if (!buf) return -1;
        // 数据端口读地址 0x00，要求 32*n bits 对齐
        // hspi_rd 对 addr<0x10 不做对齐，手动构造对齐传输
        uint16_t xfer_sz = npad + 1;
        while (xfer_sz & 3) xfer_sz++;
        uint8_t *_tx = malloc(xfer_sz + 4);
        uint8_t *_rx = malloc(xfer_sz + 4);
        if (!_tx || !_rx) { free(_tx); free(_rx); free(buf); return -1; }
        _tx[0] = 0x00;
        memset(_tx + 1, 0xFF, xfer_sz - 1);
        if (xt804_hspi_spi_xfer(_tx, _rx, xfer_sz) < 0) { free(_tx); free(_rx); free(buf); return -1; }
        memcpy(buf, _rx + 1, npad);
        free(_tx); free(_rx);
        // 跳过 pkgid(4)+flags(4)，后续是 luat_airlink_cmd_t + payload
        uint16_t remain_payload = data_len - 8;
        memmove(buf, buf + 8, remain_payload);
        luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)buf;
        if (resp && resp_len && *resp_len >= cmd->len && remain_payload >= (int)sizeof(luat_airlink_cmd_t) + cmd->len) {
            *resp_len = cmd->len;
            memcpy(resp, cmd->data, cmd->len);
            if (cmd_id) *cmd_id = cmd->cmd;
            free(buf);
            { uint8_t clr[2]; hspi_rd(0x06, clr, 2); }
            return 0;
        }
        free(buf);
    }
    return -1;
}

/**
 * 验证 H-SPI 帧头 checksum 和 payload checksum
 *
 * 帧格式: [SYN(0xAA)][TYPE][LEN_BE(2)][SN][FLG][DA][HDR_CHK][PAYLOAD...][PL_CHK][PAD]
 *
 * HDR_CHK = (TYPE + LEN_H + LEN_L + SN + FLG + DA) & 0xFF   ← 大端, 按字节累加
 * PL_CHK  = sum(PAYLOAD[0..LEN-1]) & 0xFF
 *
 * @return 1=校验通过, 0=失败
 */
static int hspi_frame_verify(const uint8_t *frame, uint16_t len) {
    if (len < 9) return 0;
    if (frame[0] != 0xAA) return 0;
    uint16_t plen = ((uint16_t)frame[2] << 8) | frame[3];  // 大端
    if (plen + 9 > len) return 0;
    uint8_t exp_hdr = (frame[1] + frame[2] + frame[3] + frame[4] + frame[5] + frame[6]) & 0xFF;
    if (frame[7] != exp_hdr) return 0;
    uint8_t pl_chk = 0;
    for (uint16_t i = 0; i < plen; i++) pl_chk += frame[8 + i];
    if (frame[8 + plen] != pl_chk) return 0;
    return 1;
}

/**
 * 中断驱动读取 — 严格按 HSPI 手册 10.4.3.3 流程
 *
 * 流程:
 *   [事务1] 读 SPI_INT_HOST_STTS(0x06) → 确认 bit0=1
 *   [事务2] 读 RX_DAT_LEN(0x02)       → 获取数据长度
 *   [事务3] 读 DAT_PORT1(0x10)        → 读取数据
 *   [事务4] 读 SPI_INT_HOST_STTS(0x06) → 确认清除 (bit0=0)
 *
 * ★ 响应数据格式 (从机→主机):
 *   HSPI 硬件剥离 AirLink 帧头 magic(4)+len(2)+crc16(2)=8B
 *   数据端口剩余: pkgid(4)+flags(4)+cmd_t(4)+payload
 *   再跳过 pkgid+flags(8B) 后得到 cmd_t
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
    // [事务0] 读 SPI_INT_HOST_STTS — 无 INT 则无新数据, RX_DAT_LEN 是旧值
    //   "读可清"会清除 INT, 但没关系 — 只要读到 INT=1, 就确认有数据待读
    uint8_t sts0[2];
    if (hspi_rd(0x06, sts0, 2) < 0) return -1;
    if (!(sts0[0] & 0x01)) return -1;  // INT 未触发 → 无新数据 (RX_DAT_LEN 旧值)

    // [事务1] 读 RX_DAT_LEN (已确认 INT 触发, 有数据. 如果=0 是硬件时序窗口, 重试)
    uint16_t n = 0;
    for (int _try = 0; _try < 3; _try++) {
        uint8_t rxl[2];
        if (hspi_rd(0x02, rxl, 2) < 0) return -1;
        n = rxl[0] | ((uint16_t)rxl[1] << 8);
        if (n != 0 && n != 0xFFFF) break;
        if (_try == 0 && (sts0[0] & 0x01)) {
            // INT 触发了但 RX_DAT_LEN=0, 硬件时序窗口, 等 1ms 重试
            luat_rtos_task_sleep(1);
            continue;
        }
        return -1;  // 真的没有数据
    }

    //LLOGD("HSPI RX_DAT_LEN=%u", n);
    uint16_t data_len = n;

    // [事务3] 读数据 (栈上数组, 4字节对齐)
    uint16_t npad = (data_len + 3) & ~3;
    uint8_t tx_buf[1608];
    uint8_t rx_buf[1608];
    uint8_t buf[1608];

    memset(tx_buf, 0, sizeof(tx_buf));
    tx_buf[0] = 0x10;  // DAT_PORT1 读 (末段, 命令0x10). 手册: 单帧就是末段, 用0x10通知硬件帧结束释放TX描述符
    memset(tx_buf + 1, 0xFF, npad);
    uint16_t xfer = ((npad + 1 + 3) & ~3);
    if (xfer > sizeof(tx_buf)) xfer = sizeof(tx_buf);

    if (xt804_hspi_spi_xfer(tx_buf, rx_buf, xfer) < 0) return -1;
    memcpy(buf, rx_buf + 1, npad);

    // [事务4] 验证 RX_DAT_LEN 归零 (INT 已在事务0被"读可清"清除)
    { uint8_t _chk[2]; if (hspi_rd(0x02, _chk, 2) == 0) {
        uint16_t _left = _chk[0] | ((uint16_t)_chk[1] << 8);
        if (_left != 0 && _left != 0xFFFF) {
            //LLOGD("HSPI more data pending: len=%u", _left);
        }
    }}

#if 0
    // ★ 调试: RAW 数据前 32 字节
    LLOGD("HSPI raw[0..31]: "
        "%02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X "
        "%02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X",
        buf[0],buf[1],buf[2],buf[3],buf[4],buf[5],buf[6],buf[7],
        buf[8],buf[9],buf[10],buf[11],buf[12],buf[13],buf[14],buf[15],
        buf[16],buf[17],buf[18],buf[19],buf[20],buf[21],buf[22],buf[23],
        buf[24],buf[25],buf[26],buf[27],buf[28],buf[29],buf[30],buf[31]);
#endif

    // 解析: 尝试两种格式
    // 格式1: 完整 AirLink frame (magic+len+crc16+pkgid+flags+cmd_t+payload)
    // 格式2: 无帧头, 直接 cmd_t+payload
    uint8_t *pdata = buf;
    uint16_t plen = data_len;

    // 如果以 A1B1CA66 开头 → 格式1, 跳过帧头
    if (plen >= 4 && buf[0]==0xA1 && buf[1]==0xB1 && buf[2]==0xCA && buf[3]==0x66) {
        // airlink_link_data_t 头部 16 字节
        uint16_t link_len = buf[4] | ((uint16_t)buf[5] << 8);  // LE
        //LLOGD("HSPI AirLink frame: magic=OK link_len=%u raw_len=%u", link_len, plen);
        if (plen < 16) return -1;
        pdata = buf + 16;  // 跳过完整帧头
        plen = plen - 16;
    }

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
