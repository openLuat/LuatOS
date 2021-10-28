
#include "luat_base.h"
#include "luat_spi.h"

#ifndef u8
#define u8 uint8_t
#endif

#define LUAT_GT_DEBUG 1
#define LUAT_LOG_TAG "gt"
#include "luat_log.h"

luat_spi_device_t* gt_spi_dev = NULL;

unsigned long r_dat_bat(unsigned long address,unsigned long DataLen,unsigned char *pBuff) {
    #if LUAT_GT_DEBUG
    LLOGD("r_dat_bat addr %08X len %d pBuff %X", address, DataLen,*pBuff);
    #endif
    if (gt_spi_dev == NULL)
        return 0;
    char send_buf[4] = {
        0x03,
        (u8)((address)>>16),
        (u8)((address)>>8),
        (u8)(address)
    };
    // luat_spi_device_send(gt_spi_dev, send_buf, 4);
    // luat_spi_device_recv(gt_spi_dev, pBuff, DataLen);
    luat_spi_device_transfer(gt_spi_dev, send_buf, 4, pBuff, DataLen);
    return pBuff[0];
}

unsigned char CheckID(unsigned char CMD, unsigned long address,unsigned long byte_long,unsigned char *p_arr) {
    #if LUAT_GT_DEBUG
    LLOGD("CheckID CMD %02X addr %08X len %d p_arr %X", CMD, address, byte_long,*p_arr);
    #endif
    if (gt_spi_dev == NULL)
        return 0;
    char send_buf[4] = {
        CMD,
        (u8)((address)>>16),
        (u8)((address)>>8),
        (u8)(address)
    };
    // luat_spi_device_send(gt_spi_dev, send_buf, 4);
    // luat_spi_device_recv(gt_spi_dev, p_arr, byte_long);
    luat_spi_device_transfer(gt_spi_dev, send_buf, 4, p_arr, byte_long);
    // return p_arr[0];
    return 1;
}

