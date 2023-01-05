
#include "luat_base.h"
#include "luat_spi.h"

#ifndef u8
#define u8 uint8_t
#endif

#define LUAT_GT_DEBUG 0
#define LUAT_LOG_TAG "gt"
#include "luat_log.h"

luat_spi_device_t* gt_spi_dev = NULL;

unsigned long r_dat_bat(unsigned long address,unsigned long DataLen,unsigned char *pBuff) {
    if (gt_spi_dev == NULL)
        return 0;
    char send_buf[4] = {
        0x03,
        (u8)((address)>>16),
        (u8)((address)>>8),
        (u8)(address)
    };
    luat_spi_device_transfer(gt_spi_dev, send_buf, 4, (char *)pBuff, DataLen);
    #if LUAT_GT_DEBUG
    LLOGD("r_dat_bat addr %08X len %d pBuff %X", address, DataLen,*pBuff);
    for(int i = 0; i < DataLen;i++){
        LLOGD("pBuff[%d]:0x%02X",i,pBuff[i]);
    }
    #endif
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
    luat_spi_device_transfer(gt_spi_dev, send_buf, 4, (char *)p_arr, byte_long);
    // return p_arr[0];
    return 1;
}

unsigned char gt_read_data(unsigned char* sendbuf , unsigned char sendlen , unsigned char* receivebuf, unsigned int receivelen)
{
    if (gt_spi_dev == NULL)
        return 0;
    luat_spi_device_transfer(gt_spi_dev, (const char *)sendbuf, sendlen,(char *)receivebuf, receivelen);
    #if LUAT_GT_DEBUG
    LLOGD("gt_read_data sendlen:%d receivelen:%d",sendlen,receivelen);
    for(int i = 0; i < sendlen;i++){
        LLOGD("sendbuf[%d]:0x%02X",i,sendbuf[i]);
    }
    for(int i = 0; i < receivelen;i++){
        LLOGD("receivebuf[%d]:0x%02X",i,receivebuf[i]);
    }
    #endif
    return 1;
}
