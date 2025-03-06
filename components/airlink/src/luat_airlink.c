
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

int luat_airlink_start(int id) {
    if (id == 0) {
        extern int luat_airlink_start_slave(void);
        luat_airlink_start_slave();
    }
    else {
        extern int luat_airlink_start_master(void);
        luat_airlink_start_master();
    }
    return 0;
}

int luat_airlink_stop(int id) {
    return 0;
}

void luat_airlink_data_unpack(uint8_t* buff, size_t len, size_t* pkg_offset, size_t* pkg_size) {
    size_t tlen = 0;
    uint16_t crc16 = 0;
    uint16_t crc16_data = 0;
    for (size_t i = 0; i < len - 12; i++)
    {
        // magic = 0xA1B1CA66
        if (buff[i] == 0xA1 && buff[i + 1] == 0xB1 && buff[i + 2] == 0xCA && buff[i + 3] == 0x66)
        {
            // 找到了magic
            tlen = buff[i + 4] + buff[i+5] * 256;
            crc16 = buff[i + 6] + buff[i+7] * 256;
            LLOGD("找到magic, 且数据长度为 %d", tlen);
            if (tlen > 0 && tlen + 4 + i + 4 <= len) {
                // 计算crc16
                crc16_data = luat_crc16(buff + i + 4 + 4, tlen, 0xFFFF, 0x1021, 0);
                if (crc16_data == crc16) {
                    LLOGD("crc16校验成功");
                    *pkg_offset = i + 4 + 4;
                    *pkg_size = tlen;
                    return;
                }
                else {
                    LLOGD("crc16校验失败 %d %d", crc16_data, crc16);
                }
            }
            else {
                LLOGD("数据长度错误");
            }
        }
    }
    
}

void luat_airlink_data_pack(uint8_t* buff, size_t len, uint8_t* dst) {
    // 先写入magic
    dst[0] = 0xA1;
    dst[1] = 0xB1;
    dst[2] = 0xCA;
    dst[3] = 0x66;

    // 写入长度
    dst[4] = len & 0xFF;
    dst[5] = (len >> 8) & 0xFF;

    // 写入crc16
    uint16_t crc16 = luat_crc16(buff, len, 0xFFFF, 0x1021, 0);
    dst[6] = crc16 & 0xFF;
    dst[7] = (crc16 >> 8) & 0xFF;

    memcpy(dst + 8, buff, len);
}

void luat_airlink_print_buff(const char* tag, uint8_t* buff, size_t len) {
    static char tmpbuff[1024] = {0};
    for (size_t i = 0; i < len; i+=8)
    {
        // sprintf(tmpbuff + i * 2, "%02X", buff[i]);
        // LLOGD("SPI TX[%d] 0x%02X", i, buff[i]);
        LLOGD("AirLink %s [%04X-%04X] %02X%02X%02X%02X%02X%02X%02X%02X", tag, i, i + 8, 
            buff[i+0], buff[i+1], buff[i+2], buff[i+3], 
            buff[i+4], buff[i+5], buff[i+6], buff[i+7]);
    }
    // LLOGD("SPI0 %s", tmpbuff);
}