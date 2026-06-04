
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

__AIRLINK_CODE_IN_RAM__ airlink_link_data_t* luat_airlink_data_unpack(uint8_t *buff, size_t len)
{
    size_t tlen = 0;
    uint16_t crc16 = 0;
    uint16_t crc16_data = 0;
    if (len < 12)
    {
        LLOGD("数据长度异常 %d", len);
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
            if (tlen > 0 && tlen + 4 + i + 4 <= len)
            {
                // 计算crc16
                crc16_data = luat_crc16_modbus(&buff[i + 4 + 4], tlen + 8);
                if (crc16_data == crc16)
                {
                    // 更新对端 flags, 用于能力协商
                    luat_airlink_peer_flags_update(&link->flags);
                    return link;
                }
                else
                {
                    LLOGW("crc16校验失败 %d %d", crc16_data, crc16);
                    // 继续扫描 buffer 中后续 magic，不因单帧 CRC 失败而丢弃后续有效帧
                    i += 3; // 跳过当前 magic 的 4 字节 (循环末尾 i++ 会再+1)
                    continue;
                }
            }
            else
            {
                LLOGW("数据长度错误 tlen=%u total=%u buf_remain=%u offset=%u buf_len=%u",
                      tlen, (unsigned)(tlen + 16), (unsigned)(len - i), (unsigned)i, (unsigned)len);
                return NULL;
            }
        }
    }

    return NULL;
}

__AIRLINK_CODE_IN_RAM__ void luat_airlink_data_pack(uint8_t *buff, size_t len, uint8_t *dst)
{
    luat_airlink_link_data_cb link_data_cb = NULL;
    // 先写入magic
    airlink_link_data_t* data = dst;
    dst[0] = 0xA1;
    dst[1] = 0xB1;
    dst[2] = 0xCA;
    dst[3] = 0x66;

    // 写入长度和crc16
    memset(&data->flags, 0, sizeof(data->flags));
    data->len = len;
    data->pkgid = next_pkg_id++;
    memset(&data->flags, 0, sizeof(data->flags));

    // 如果支持RPC, 那就把对应的flags设置一下
    if (luat_airlink_mode_link_data_cb_get() != NULL) {
        data->flags.rpc_supported = 1;
    }
    // 分片传输能力标记
    data->flags.frag_supported = 1;


    memcpy(data->data, buff, len);
    link_data_cb = luat_airlink_mode_link_data_cb_get();
    if (link_data_cb) {
        link_data_cb(data);
    }
    
    // data->crc16 = luat_crc16(&data->pkgid, len + 8, 0xFFFF, 0x1021, 0);
    data->crc16 = luat_crc16_modbus(&data->pkgid, len + 8);
}
