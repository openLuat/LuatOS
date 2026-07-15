#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_HSPI_MASTER

#include <stdlib.h>

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_mem.h"
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
    out[0] = 0xAA; out[1] = 0x00;
    out[2] = (plen >> 8) & 0xFF; out[3] = plen & 0xFF;
    out[4] = 1; out[5] = 0; out[6] = 0; out[7] = hdr_chk;
    memcpy(out + 8, payload, plen);
    uint8_t pl_chk = 0;
    for (uint16_t i = 0; i < plen; i++) pl_chk += payload[i];
    out[8 + plen] = pl_chk;
    uint16_t total = 9 + plen;
    while (total & 3) out[total++] = 0;
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
            airlink_link_data_t *link = (airlink_link_data_t*)(data + i);
            uint16_t crc = crc16_modbus(data + i + 8, link->len + 8);
            if (crc == link->crc16) return link;
        }
    }
    return NULL;
}

extern int xt804_hspi_spi_xfer(const uint8_t *tx, uint8_t *rx, uint16_t len);
extern uint32_t xt804_hspi_get_tick_ms(void);

static int hspi_wr(uint8_t addr, const uint8_t *data, uint16_t len) {
    uint16_t total = 1 + len;
    uint8_t *tx = malloc(total + 4);
    if (!tx) return -1;
    uint16_t orig_len = len;
    tx[0] = addr | 0x80;
    memcpy(tx + 1, data, len);
    while ((1 + len) & 3) tx[1 + len++] = 0;
    uint8_t *rx = malloc(1 + len + 4);
    if (!rx) { free(tx); return -1; }
    int ret = xt804_hspi_spi_xfer(tx, rx, 1 + orig_len);
    free(tx); free(rx);
    return ret;
}

static int hspi_rd(uint8_t addr, uint8_t *data, uint16_t len) {
    uint16_t total = 1 + len;
    uint8_t *tx = malloc(total + 4);
    if (!tx) return -1;
    uint8_t original_len = len;
    tx[0] = addr;
    memset(tx + 1, 0xFF, len);
    while ((1 + len) & 3) tx[1 + len++] = 0;
    uint8_t *rx = malloc(total + 4);
    if (!rx) { free(tx); return -1; }
    int ret = xt804_hspi_spi_xfer(tx, rx, total);
    if (ret >= 0 && data) {
        memcpy(data, rx + 1, original_len);
    }
    free(tx); free(rx);
    return ret;
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
    uint32_t deadline = xt804_hspi_get_tick_ms() + timeout_ms;
    while (xt804_hspi_get_tick_ms() < deadline) {
        uint8_t rxl[2];
        if (hspi_rd(0x02, rxl, 2) < 0) continue;
        uint16_t n = rxl[0] | ((uint16_t)rxl[1] << 8);
        if (n == 0) { static int pc=0; if(++pc%10==0) LLOGI("hspi rd02=0"); continue; }
        if (n > 1600) n = 1600;
        uint8_t *buf = malloc(n + 4);
        if (!buf) return -1;
        if (hspi_rd(0x10, buf, n) < 0) { free(buf); return -1; }
        airlink_link_data_t *link = airlink_unpack(buf, n);
        if (link) {
            luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t*)link->data;
            if (resp && resp_len && *resp_len >= cmd->len) {
                memcpy(resp, cmd->data, cmd->len);
                *resp_len = cmd->len;
            }
            if (cmd_id) *cmd_id = cmd->cmd;
            free(buf);
            return 0;
        }
        free(buf);
    }
    return -1;
}

int xt804_hspi_send_cmd(uint16_t cmd_id, const uint8_t *payload, uint16_t payload_len,
                         uint8_t *resp, uint16_t *resp_len, uint32_t timeout_ms) {
    uint8_t link_buf[1600];
    uint16_t link_len = sizeof(link_buf);
    if (airlink_pack(cmd_id, payload, payload_len, link_buf, &link_len) != 0)
        return -1;
    uint8_t hspi_buf[1600 + 16];
    uint16_t hspi_len = sizeof(hspi_buf);
    hspi_pack(link_buf, link_len, hspi_buf, &hspi_len);
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
