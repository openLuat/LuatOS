
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

typedef char airlink_wire_header_must_be_16_bytes[(sizeof(airlink_link_data_t) == 16) ? 1 : -1];

void luat_airlink_flags_fill(airlink_flags_t* flags) {
    flags->rpc_supported = 0;
    flags->frag_supported = 0;
#ifdef LUAT_USE_AIRLINK_RPC
    flags->rpc_supported = 1;
#ifndef LUAT_AIRLINK_NO_FRAGMENT
    flags->frag_supported = 1;
#endif
#endif
    flags->reserved = 0;
}

__AIRLINK_CODE_IN_RAM__ airlink_link_data_t* luat_airlink_data_unpack_uart(uint8_t *buff, size_t len)
{
    size_t tlen = 0;
    uint16_t crc16 = 0;
    uint16_t crc16_data = 0;
    if (len < sizeof(airlink_link_data_t))
    {
        LLOGD("数据长度异常 %d", len);
        return NULL;
    }
    airlink_link_data_t *link = NULL;

    for (size_t i = 0; i + sizeof(airlink_link_data_t) <= len; i++)
    {
        // magic = 0xA1B1CA66
        if (buff[i] == 0xA1 && buff[i + 1] == 0xB1 && buff[i + 2] == 0xCA && buff[i + 3] == 0x66)
        {
            // 找到了magic
            link = (airlink_link_data_t*)(buff + i);
            tlen = link->len;
            crc16 = link->crc16;
            if (tlen > 0 && tlen + sizeof(airlink_link_data_t) + i <= len)
            {
                // 计算crc16
                crc16_data = luat_crc16_modbus(&buff[i + 4 + 4], tlen + 8);
                if (crc16_data == crc16)
                {
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
                LLOGD("数据长度错误 tlen=%u total=%u buf_remain=%u offset=%u buf_len=%u",
                      tlen, (unsigned)(tlen + 16), (unsigned)(len - i), (unsigned)i, (unsigned)len);
                // 与 CRC 失败一致: 跳过当前 magic 继续扫描后续 magic。
                // 主机 UART overrun 丢字节后, 0x7E 帧界可能被破坏, 两帧合并进同一 buffer,
                // 帧内会含第二个完整帧; 直接 return 会连它一起丢掉。这里改为 continue 自愈。
                i += 3; // 跳过当前 magic 的 4 字节 (循环末尾 i++ 会再+1)
                continue;
            }
        }
    }

    return NULL;
}

__AIRLINK_CODE_IN_RAM__ airlink_link_data_t* luat_airlink_data_unpack(uint8_t *buff, size_t len) {
    airlink_link_data_t* frame = luat_airlink_data_unpack_uart(buff, len);
    if (frame) luat_airlink_peer_frame_update(frame);
    return frame;
}

__AIRLINK_CODE_IN_RAM__ void luat_airlink_data_pack(uint8_t *buff, size_t len, uint8_t *dst)
{
    luat_airlink_link_data_cb link_data_cb = NULL;
    // 先写入magic
    airlink_link_data_t* data = (void*)dst;
    dst[0] = 0xA1;
    dst[1] = 0xB1;
    dst[2] = 0xCA;
    dst[3] = 0x66;

    // 写入长度和pkgid
    memset(&data->flags, 0, sizeof(data->flags));
    data->len = len;
    data->pkgid = luat_airlink_next_frame_id();

    if (data->data != buff) memmove(data->data, buff, len);
    link_data_cb = luat_airlink_mode_link_data_cb_get();
    if (link_data_cb) {
        link_data_cb(data);
    }
    // Write capabilities after callbacks, which may clear the flags word.
    luat_airlink_flags_fill(&data->flags);
    data->crc16 = luat_crc16_modbus((const uint8_t*)&data->pkgid, len + 8);
}
