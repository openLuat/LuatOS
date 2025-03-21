
/**
airlink数据打包解包,数据链路层
 */
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_crypto.h"
#include "luat_netdrv.h"
#include "luat_netdrv_whale.h"
#include "lwip/prot/ethernet.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

static uint32_t next_pkg_id;

airlink_link_data_t* luat_airlink_data_unpack(uint8_t *buff, size_t len)
{
    size_t tlen = 0;
    uint16_t crc16 = 0;
    uint16_t crc16_data = 0;
    if (len < 12)
    {
        return NULL;
    }
    airlink_link_data_t *link = NULL;
    for (size_t i = 0; i < len - 12; i++)
    {
        // magic = 0xA1B1CA66
        if (buff[i] == 0xA1 && buff[i + 1] == 0xB1 && buff[i + 2] == 0xCA && buff[i + 3] == 0x66)
        {
            // 找到了magic
            link = (airlink_link_data_t*)(buff + i);
            tlen = link->len;
            crc16 = link->crc16;
            // LLOGD("找到magic, 且数据长度为 %d", tlen);
            if (tlen > 0 && tlen + 4 + i + 4 <= len)
            {
                // 计算crc16
                crc16_data = luat_crc16(buff + i + 4 + 4, tlen + 8, 0xFFFF, 0x1021, 0);
                if (crc16_data == crc16)
                {
                    return link;
                }
                else
                {
                    LLOGD("crc16校验失败 %d %d", crc16_data, crc16);
                }
            }
            else
            {
                LLOGD("数据长度错误");
            }
        }
    }
    return NULL;
}

void luat_airlink_data_pack(uint8_t *buff, size_t len, uint8_t *dst)
{
    // 先写入magic
    airlink_link_data_t* data = dst;
    dst[0] = 0xA1;
    dst[1] = 0xB1;
    dst[2] = 0xCA;
    dst[3] = 0x66;

    // 写入长度和crc16
    data->len = len;
    data->pkgid = next_pkg_id++;
    data->flags = 0;
    memcpy(data->data, buff, len);
    
    data->crc16 = luat_crc16(&data->pkgid, len + 8, 0xFFFF, 0x1021, 0);
}
